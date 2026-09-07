package wordgen

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

type fixtureEntry struct {
	Word    string   `json:"word"`
	Sources []string `json:"sources"`
}

func TestGeneratorGenerateAndStream(t *testing.T) {
	datasetPath := writeDataset(t, []fixtureEntry{
		{Word: "steel", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stale", Sources: []string{"fsu/wordle.txt"}},
		{Word: "apple", Sources: []string{"fsu/wordle.txt"}},
	})

	generatorInstance := New(Config{
		Dataset:   datasetPath,
		Count:     2,
		MinLength: 5,
		Prefix:    "st",
		Seed:      1,
	})

	words, matched, err := generatorInstance.Generate(context.Background())
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	if matched != 2 {
		t.Fatalf("expected matched=2, got %d", matched)
	}
	if len(words) != 2 {
		t.Fatalf("expected 2 generated words, got %d", len(words))
	}

	streamMatched, err := generatorInstance.Stream(context.Background(), func(word string) bool {
		return word != "stale"
	})
	if err != nil {
		t.Fatalf("stream: %v", err)
	}
	if streamMatched != 2 {
		t.Fatalf("expected stream matched=2, got %d", streamMatched)
	}
}

func TestLoadIndexedAndIndexedGenerator(t *testing.T) {
	datasetPath := writeDataset(t, []fixtureEntry{
		{Word: "steel", Sources: []string{"fsu/wordle.txt"}},
		{Word: "stale", Sources: []string{"fsu/wordle.txt"}},
	})

	indexed, err := LoadIndexed(datasetPath)
	if err != nil {
		t.Fatalf("load indexed: %v", err)
	}

	words, matched, err := indexed.Generate(context.Background(), Config{
		Count:     5,
		MinLength: 5,
		Prefix:    "st",
		Seed:      99,
	})
	if err != nil {
		t.Fatalf("indexed generate: %v", err)
	}
	if matched != 2 {
		t.Fatalf("expected indexed matched=2, got %d", matched)
	}
	if len(words) != 2 {
		t.Fatalf("expected indexed words=2, got %d", len(words))
	}
}

func TestIndexedGeneratorZeroValueReturnsError(t *testing.T) {
	var indexed IndexedGenerator

	_, _, err := indexed.Generate(context.Background(), Config{Count: 1})
	if err == nil {
		t.Fatal("expected error for zero-value indexed generator")
	}

	_, err = indexed.Stream(context.Background(), Config{Count: 1}, func(string) bool { return true })
	if err == nil {
		t.Fatal("expected stream error for zero-value indexed generator")
	}
}

func writeDataset(t *testing.T, entries []fixtureEntry) string {
	t.Helper()

	content, err := json.Marshal(entries)
	if err != nil {
		t.Fatalf("marshal dataset: %v", err)
	}

	path := filepath.Join(t.TempDir(), "all.json")
	if err := os.WriteFile(path, append(content, '\n'), 0o600); err != nil {
		t.Fatalf("write dataset: %v", err)
	}

	return path
}
