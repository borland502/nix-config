package cmd

import (
	"bytes"
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/borland502/wordgen/internal/appconfig"
	"github.com/spf13/cobra"
)

type generateFixtureEntry struct {
	Word    string   `json:"word"`
	Sources []string `json:"sources"`
}

func TestGenerateCommandNoMatchesReturnsError(t *testing.T) {
	setGenerateConfigForTest(t, appconfig.GenerateConfig{
		Dataset:   writeGenerateDataset(t, []generateFixtureEntry{{Word: "alpha", Sources: []string{"fsu/wordle.txt"}}}),
		Count:     1,
		MinLength: 5,
		Prefix:    "zz",
	})

	command := newGenerateCommandForTest()
	err := command.RunE(command, nil)
	if err == nil {
		t.Fatal("expected no-match error")
	}
	if !strings.Contains(err.Error(), "no words matched") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestGenerateCommandWritesWarningWhenMatchedLessThanCount(t *testing.T) {
	setGenerateConfigForTest(t, appconfig.GenerateConfig{
		Dataset: writeGenerateDataset(t, []generateFixtureEntry{
			{Word: "steel", Sources: []string{"fsu/wordle.txt"}},
			{Word: "stale", Sources: []string{"fsu/wordle.txt"}},
		}),
		Count:     5,
		MinLength: 5,
		Prefix:    "st",
		Seed:      1,
	})

	command := newGenerateCommandForTest()
	err := command.RunE(command, nil)
	if err != nil {
		t.Fatalf("unexpected generate error: %v", err)
	}

	stdout := command.OutOrStdout().(*bytes.Buffer).String()
	stderr := command.ErrOrStderr().(*bytes.Buffer).String()
	if stdout == "" {
		t.Fatal("expected generated words on stdout")
	}
	if !strings.Contains(stderr, "requested 5 words but only 2 matched") {
		t.Fatalf("unexpected stderr: %q", stderr)
	}
}

func newGenerateCommandForTest() *cobra.Command {
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	command := &cobra.Command{RunE: generateCmd.RunE}
	command.SetOut(&stdout)
	command.SetErr(&stderr)
	return command
}

func setGenerateConfigForTest(t *testing.T, generateConfig appconfig.GenerateConfig) {
	t.Helper()
	originalConfig := cfg
	t.Cleanup(func() {
		cfg = originalConfig
	})
	cfg = appconfig.Config{Generate: generateConfig}
}

func writeGenerateDataset(t *testing.T, entries []generateFixtureEntry) string {
	t.Helper()
	content, err := json.Marshal(entries)
	if err != nil {
		t.Fatalf("marshal dataset: %v", err)
	}

	path := t.TempDir() + "/all.json"
	if err := os.WriteFile(path, append(content, '\n'), 0o600); err != nil {
		t.Fatalf("write dataset: %v", err)
	}

	return path
}
