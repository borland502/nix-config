package generator

import (
	"compress/gzip"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/klauspost/compress/zstd"
)

type testWordEntry struct {
	Word    string   `json:"word"`
	Sources []string `json:"sources"`
}

func TestSelectWordsWithContextAppliesFilters(t *testing.T) {
	datasetPath := writeTestDataset(t, []testWordEntry{
		{Word: "steel", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stale", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stone", Sources: []string{"dwyl/words.txt"}},
		{Word: "apple", Sources: []string{"fsu/wordle.txt"}},
	})

	words, matched, err := SelectWordsWithContext(context.Background(), Request{
		Dataset:   datasetPath,
		Count:     10,
		MinLength: 5,
		MaxLength: 5,
		Prefix:    "st",
		Contains:  "e",
		Sources:   []string{"FSU/WORDLE.TXT"},
		Seed:      42,
	})
	if err != nil {
		t.Fatalf("select words: %v", err)
	}

	if matched != 2 {
		t.Fatalf("expected 2 matched words, got %d", matched)
	}
	if len(words) != 2 {
		t.Fatalf("expected 2 selected words, got %d", len(words))
	}

	allowed := map[string]struct{}{
		"steel": {},
		"stale": {},
	}
	for _, word := range words {
		if _, ok := allowed[word]; !ok {
			t.Fatalf("unexpected selected word %q", word)
		}
	}
}

func TestSelectWordsWithContextUsesEmbeddedDatasetByDefault(t *testing.T) {
	words, matched, err := SelectWordsWithContext(context.Background(), Request{
		Count:     1,
		MinLength: 1,
		MaxLength: 0,
	})
	if err != nil {
		t.Fatalf("select words from embedded dataset: %v", err)
	}

	if matched < 1 {
		t.Fatalf("expected at least one matched word from embedded dataset, got %d", matched)
	}
	if len(words) != 1 {
		t.Fatalf("expected one selected word from embedded dataset, got %d", len(words))
	}
}

func TestStreamMatchedWordsWithContextStopsOnYieldFalse(t *testing.T) {
	datasetPath := writeTestDataset(t, []testWordEntry{
		{Word: "alpha", Sources: []string{"fsu/wordle.txt"}},
		{Word: "bravo", Sources: []string{"fsu/wordle.txt"}},
		{Word: "charlie", Sources: []string{"fsu/wordle.txt"}},
	})

	seen := 0
	matched, err := StreamMatchedWordsWithContext(context.Background(), Request{
		Dataset:   datasetPath,
		Count:     1,
		MinLength: 1,
		MaxLength: 0,
	}, func(word string) bool {
		seen++
		return seen < 2
	})
	if err != nil {
		t.Fatalf("stream words: %v", err)
	}

	if matched != 2 {
		t.Fatalf("expected stream to stop after 2 matches, got %d", matched)
	}
}

func TestSelectWordsWithContextCancelled(t *testing.T) {
	datasetPath := writeTestDataset(t, []testWordEntry{
		{Word: "alpha", Sources: []string{"fsu/wordle.txt"}},
		{Word: "bravo", Sources: []string{"fsu/wordle.txt"}},
	})

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	_, _, err := SelectWordsWithContext(ctx, Request{
		Dataset:   datasetPath,
		Count:     1,
		MinLength: 1,
	})
	if err == nil {
		t.Fatal("expected cancellation error")
	}
}

func TestIndexedDatasetSelectWordsWithContext(t *testing.T) {
	datasetPath := writeTestDataset(t, []testWordEntry{
		{Word: "steel", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stale", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stone", Sources: []string{"dwyl/words.txt"}},
	})

	indexed, err := LoadIndexedDataset(datasetPath)
	if err != nil {
		t.Fatalf("load indexed dataset: %v", err)
	}

	words, matched, err := indexed.SelectWordsWithContext(context.Background(), Request{
		Count:     5,
		MinLength: 5,
		Prefix:    "st",
		Sources:   []string{"fsu/wordle.txt"},
		Seed:      7,
	})
	if err != nil {
		t.Fatalf("select from indexed dataset: %v", err)
	}

	if matched != 2 {
		t.Fatalf("expected 2 matched words from indexed dataset, got %d", matched)
	}
	if len(words) != 2 {
		t.Fatalf("expected 2 selected words from indexed dataset, got %d", len(words))
	}
}

func TestSelectWordsWithContextSupportsGzipDataset(t *testing.T) {
	datasetPath := writeGzipTestDataset(t, []testWordEntry{
		{Word: "steel", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stale", Sources: []string{"fsu/wordle.txt"}},
		{Word: "apple", Sources: []string{"fsu/wordle.txt"}},
	})

	words, matched, err := SelectWordsWithContext(context.Background(), Request{
		Dataset:   datasetPath,
		Count:     5,
		MinLength: 5,
		Prefix:    "st",
		Seed:      3,
	})
	if err != nil {
		t.Fatalf("select words from gzip dataset: %v", err)
	}

	if matched != 2 {
		t.Fatalf("expected 2 matched words from gzip dataset, got %d", matched)
	}
	if len(words) != 2 {
		t.Fatalf("expected 2 selected words from gzip dataset, got %d", len(words))
	}
}

func TestLoadIndexedDatasetSupportsGzipDataset(t *testing.T) {
	datasetPath := writeGzipTestDataset(t, []testWordEntry{
		{Word: "steel", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stale", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stone", Sources: []string{"dwyl/words.txt"}},
	})

	indexed, err := LoadIndexedDataset(datasetPath)
	if err != nil {
		t.Fatalf("load gzip indexed dataset: %v", err)
	}

	words, matched, err := indexed.SelectWordsWithContext(context.Background(), Request{
		Count:     5,
		MinLength: 5,
		Prefix:    "st",
		Sources:   []string{"fsu/wordle.txt"},
		Seed:      11,
	})
	if err != nil {
		t.Fatalf("select from gzip indexed dataset: %v", err)
	}

	if matched != 2 {
		t.Fatalf("expected 2 matched words from gzip indexed dataset, got %d", matched)
	}
	if len(words) != 2 {
		t.Fatalf("expected 2 selected words from gzip indexed dataset, got %d", len(words))
	}
}

func TestSelectWordsWithContextSupportsZstdDataset(t *testing.T) {
	datasetPath := writeZstdTestDataset(t, []testWordEntry{
		{Word: "steel", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stale", Sources: []string{"fsu/wordle.txt"}},
		{Word: "apple", Sources: []string{"fsu/wordle.txt"}},
	})

	words, matched, err := SelectWordsWithContext(context.Background(), Request{
		Dataset:   datasetPath,
		Count:     5,
		MinLength: 5,
		Prefix:    "st",
		Seed:      3,
	})
	if err != nil {
		t.Fatalf("select words from zstd dataset: %v", err)
	}

	if matched != 2 {
		t.Fatalf("expected 2 matched words from zstd dataset, got %d", matched)
	}
	if len(words) != 2 {
		t.Fatalf("expected 2 selected words from zstd dataset, got %d", len(words))
	}
}

func TestLoadIndexedDatasetSupportsZstdDataset(t *testing.T) {
	datasetPath := writeZstdTestDataset(t, []testWordEntry{
		{Word: "steel", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stale", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stone", Sources: []string{"dwyl/words.txt"}},
	})

	indexed, err := LoadIndexedDataset(datasetPath)
	if err != nil {
		t.Fatalf("load zstd indexed dataset: %v", err)
	}

	words, matched, err := indexed.SelectWordsWithContext(context.Background(), Request{
		Count:     5,
		MinLength: 5,
		Prefix:    "st",
		Sources:   []string{"fsu/wordle.txt"},
		Seed:      11,
	})
	if err != nil {
		t.Fatalf("select from zstd indexed dataset: %v", err)
	}

	if matched != 2 {
		t.Fatalf("expected 2 matched words from zstd indexed dataset, got %d", matched)
	}
	if len(words) != 2 {
		t.Fatalf("expected 2 selected words from zstd indexed dataset, got %d", len(words))
	}
}

func TestSelectWordsWithContextFallsBackToZstdWhenJSONMissing(t *testing.T) {
	datasetPath := writeZstdTestDatasetWithJSONPath(t, []testWordEntry{
		{Word: "steel", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stale", Sources: []string{"fsu/wordle.txt"}},
		{Word: "apple", Sources: []string{"fsu/wordle.txt"}},
	})

	words, matched, err := SelectWordsWithContext(context.Background(), Request{
		Dataset:   datasetPath,
		Count:     5,
		MinLength: 5,
		Prefix:    "st",
		Seed:      17,
	})
	if err != nil {
		t.Fatalf("select words from fallback zstd dataset: %v", err)
	}

	if matched != 2 {
		t.Fatalf("expected 2 matched words from fallback zstd dataset, got %d", matched)
	}
	if len(words) != 2 {
		t.Fatalf("expected 2 selected words from fallback zstd dataset, got %d", len(words))
	}
}

func TestLoadIndexedDatasetFallsBackToZstdWhenJSONMissing(t *testing.T) {
	datasetPath := writeZstdTestDatasetWithJSONPath(t, []testWordEntry{
		{Word: "steel", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stale", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stone", Sources: []string{"dwyl/words.txt"}},
	})

	indexed, err := LoadIndexedDataset(datasetPath)
	if err != nil {
		t.Fatalf("load fallback zstd indexed dataset: %v", err)
	}

	words, matched, err := indexed.SelectWordsWithContext(context.Background(), Request{
		Count:     5,
		MinLength: 5,
		Prefix:    "st",
		Sources:   []string{"fsu/wordle.txt"},
		Seed:      11,
	})
	if err != nil {
		t.Fatalf("select from fallback zstd indexed dataset: %v", err)
	}

	if matched != 2 {
		t.Fatalf("expected 2 matched words from fallback zstd indexed dataset, got %d", matched)
	}
	if len(words) != 2 {
		t.Fatalf("expected 2 selected words from fallback zstd indexed dataset, got %d", len(words))
	}
}

func BenchmarkSelectWordsWithContext(b *testing.B) {
	datasetPath := writeBenchmarkDataset(b)
	request := Request{
		Dataset:   datasetPath,
		Count:     10,
		MinLength: 5,
		MaxLength: 10,
		Prefix:    "wo",
		Contains:  "rd",
		Sources:   []string{"fsu/wordle.txt", "dwyl/words.txt"},
		Seed:      99,
	}

	b.ResetTimer()
	for range b.N {
		_, _, err := SelectWordsWithContext(context.Background(), request)
		if err != nil {
			b.Fatalf("select words: %v", err)
		}
	}
}

func writeTestDataset(tb testing.TB, entries []testWordEntry) string {
	tb.Helper()

	bytes, err := json.Marshal(entries)
	if err != nil {
		tb.Fatalf("marshal dataset: %v", err)
	}

	path := filepath.Join(tb.TempDir(), "all.json")
	if err := os.WriteFile(path, append(bytes, '\n'), 0o600); err != nil {
		tb.Fatalf("write dataset: %v", err)
	}

	return path
}

func writeGzipTestDataset(tb testing.TB, entries []testWordEntry) string {
	tb.Helper()

	bytes, err := json.Marshal(entries)
	if err != nil {
		tb.Fatalf("marshal gzip dataset: %v", err)
	}

	path := filepath.Join(tb.TempDir(), "all.json.gz")
	file, err := os.Create(path)
	if err != nil {
		tb.Fatalf("create gzip dataset: %v", err)
	}

	gzipWriter := gzip.NewWriter(file)
	if _, err := gzipWriter.Write(append(bytes, '\n')); err != nil {
		_ = gzipWriter.Close()
		_ = file.Close()
		tb.Fatalf("write gzip dataset: %v", err)
	}

	if err := gzipWriter.Close(); err != nil {
		_ = file.Close()
		tb.Fatalf("close gzip writer: %v", err)
	}
	if err := file.Close(); err != nil {
		tb.Fatalf("close gzip file: %v", err)
	}

	return path
}

func writeZstdTestDataset(tb testing.TB, entries []testWordEntry) string {
	tb.Helper()

	bytes, err := json.Marshal(entries)
	if err != nil {
		tb.Fatalf("marshal zstd dataset: %v", err)
	}

	path := filepath.Join(tb.TempDir(), "all.json.zst")
	file, err := os.Create(path)
	if err != nil {
		tb.Fatalf("create zstd dataset: %v", err)
	}

	encoder, err := zstd.NewWriter(file)
	if err != nil {
		_ = file.Close()
		tb.Fatalf("create zstd encoder: %v", err)
	}

	if _, err := encoder.Write(append(bytes, '\n')); err != nil {
		encoder.Close()
		_ = file.Close()
		tb.Fatalf("write zstd dataset: %v", err)
	}

	encoder.Close()
	if err := file.Close(); err != nil {
		tb.Fatalf("close zstd dataset: %v", err)
	}

	return path
}

func writeZstdTestDatasetWithJSONPath(tb testing.TB, entries []testWordEntry) string {
	tb.Helper()

	bytes, err := json.Marshal(entries)
	if err != nil {
		tb.Fatalf("marshal zstd fallback dataset: %v", err)
	}

	jsonPath := filepath.Join(tb.TempDir(), "all.json")
	zstdPath := jsonPath + ".zst"
	file, err := os.Create(zstdPath)
	if err != nil {
		tb.Fatalf("create zstd fallback dataset: %v", err)
	}

	encoder, err := zstd.NewWriter(file)
	if err != nil {
		_ = file.Close()
		tb.Fatalf("create zstd fallback encoder: %v", err)
	}

	if _, err := encoder.Write(append(bytes, '\n')); err != nil {
		encoder.Close()
		_ = file.Close()
		tb.Fatalf("write zstd fallback dataset: %v", err)
	}

	encoder.Close()
	if err := file.Close(); err != nil {
		tb.Fatalf("close zstd fallback dataset: %v", err)
	}

	return jsonPath
}

func writeBenchmarkDataset(tb testing.TB) string {
	tb.Helper()

	entries := make([]testWordEntry, 0, 10000)
	for index := range 10000 {
		sources := []string{"dwyl/words.txt"}
		if index%2 == 0 {
			sources = []string{"fsu/wordle.txt"}
		}
		entries = append(entries, testWordEntry{
			Word:    "word" + string(rune('a'+(index%26))) + "x",
			Sources: sources,
		})
	}

	return writeTestDataset(tb, entries)
}
