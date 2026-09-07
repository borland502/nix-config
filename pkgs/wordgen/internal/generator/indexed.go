package generator

import (
	"context"
	"encoding/gob"
	"encoding/json"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/adrg/xdg"
)

// IndexedDataset stores the parsed word index in memory for repeated low-latency calls.
type IndexedDataset struct {
	entries []wordEntry
}

// LoadIndexedDataset loads the word index into memory.
// On the first call it decodes from the source (JSON/zstd/gzip) and writes a
// gob sidecar alongside the dataset for fast subsequent loads.
// If the gob sidecar already exists it is read directly, skipping JSON decoding.
func LoadIndexedDataset(path string) (*IndexedDataset, error) {
	path = requestDatasetPath(path)
	gobPath := gobSidecarPath(path)

	if dataset, err := loadGobDataset(gobPath); err == nil {
		return dataset, nil
	}

	reader, err := openWordIndexReader(path)
	if err != nil {
		return nil, err
	}
	defer reader.Close()

	decoder := json.NewDecoder(reader)
	var entries []wordEntry
	if err := decoder.Decode(&entries); err != nil {
		return nil, fmt.Errorf("decode indexed word dataset: %w", err)
	}

	dataset := &IndexedDataset{entries: entries}
	_ = writeGobDataset(gobPath, dataset)
	return dataset, nil
}

// gobSidecarPath returns the path of the gob sidecar for the given dataset.
// For the embedded dataset it resolves to $XDG_CACHE_HOME/wordgen/all.gob.
// For file paths it replaces the known extension (.json, .json.zst, .json.gz)
// with .gob in the same directory.
func gobSidecarPath(datasetPath string) string {
	if isEmbeddedDatasetPath(datasetPath) {
		return filepath.Join(xdg.CacheHome, "wordgen", "all.gob")
	}

	lower := strings.ToLower(datasetPath)
	for _, ext := range []string{".json.zst", ".json.gz", ".json"} {
		if strings.HasSuffix(lower, ext) {
			return datasetPath[:len(datasetPath)-len(ext)] + ".gob"
		}
	}

	return datasetPath + ".gob"
}

func loadGobDataset(gobPath string) (*IndexedDataset, error) {
	f, err := os.Open(gobPath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var entries []wordEntry
	if err := gob.NewDecoder(f).Decode(&entries); err != nil {
		return nil, fmt.Errorf("decode gob dataset %s: %w", gobPath, err)
	}

	return &IndexedDataset{entries: entries}, nil
}

// writeGobDataset atomically writes the dataset entries to gobPath using a
// temp-file + rename so a partially-written file is never visible to readers.
func writeGobDataset(gobPath string, dataset *IndexedDataset) error {
	gobDir := filepath.Dir(gobPath)
	if err := os.MkdirAll(gobDir, 0o700); err != nil {
		return fmt.Errorf("create gob cache dir: %w", err)
	}

	tmp, err := os.CreateTemp(gobDir, "all.*.gob.tmp")
	if err != nil {
		return fmt.Errorf("create temp gob file: %w", err)
	}
	tmpPath := tmp.Name()

	if err := gob.NewEncoder(tmp).Encode(dataset.entries); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpPath)
		return fmt.Errorf("encode gob dataset: %w", err)
	}

	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpPath)
		return fmt.Errorf("close temp gob file: %w", err)
	}

	if err := os.Rename(tmpPath, gobPath); err != nil {
		_ = os.Remove(tmpPath)
		return fmt.Errorf("install gob sidecar: %w", err)
	}

	return nil
}

// SelectWordsWithContext selects up to Count sampled words from the in-memory dataset.
func (dataset *IndexedDataset) SelectWordsWithContext(ctx context.Context, request Request) ([]string, int, error) {
	if dataset == nil {
		return nil, 0, fmt.Errorf("indexed dataset is nil")
	}
	if err := validateRequest(request); err != nil {
		return nil, 0, err
	}

	matcher := compileMatcher(request)
	seed := request.Seed
	if seed == 0 {
		seed = time.Now().UnixNano()
	}

	rng := rand.New(rand.NewSource(seed))
	selectedWords := make([]string, 0, request.Count)
	matchedCount := 0

	for _, entry := range dataset.entries {
		if err := ctx.Err(); err != nil {
			return nil, 0, err
		}
		if !matcher.matches(entry) {
			continue
		}

		matchedCount++
		if len(selectedWords) < request.Count {
			selectedWords = append(selectedWords, entry.Word)
			continue
		}

		candidateIndex := rng.Intn(matchedCount)
		if candidateIndex < request.Count {
			selectedWords[candidateIndex] = entry.Word
		}
	}

	if len(selectedWords) > 1 {
		rng.Shuffle(len(selectedWords), func(left, right int) {
			selectedWords[left], selectedWords[right] = selectedWords[right], selectedWords[left]
		})
	}

	return selectedWords, matchedCount, nil
}

// StreamMatchedWordsWithContext streams matching words from the in-memory dataset.
func (dataset *IndexedDataset) StreamMatchedWordsWithContext(ctx context.Context, request Request, yield func(string) bool) (int, error) {
	if dataset == nil {
		return 0, fmt.Errorf("indexed dataset is nil")
	}
	if err := validateRequest(request); err != nil {
		return 0, err
	}

	matcher := compileMatcher(request)
	matchedCount := 0
	for _, entry := range dataset.entries {
		if err := ctx.Err(); err != nil {
			return matchedCount, err
		}
		if !matcher.matches(entry) {
			continue
		}

		matchedCount++
		if !yield(entry.Word) {
			return matchedCount, nil
		}
	}

	return matchedCount, nil
}
