package cmd

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type rootFixtureEntry struct {
	Word    string   `json:"word"`
	Sources []string `json:"sources"`
}

func TestRootCommandDefaultsToGenerateFromConfig(t *testing.T) {
	configPath := writeRootConfigFile(t)

	originalCfgFile := cfgFile
	originalSearchConfigFile := searchConfigFile
	originalConfig := cfg
	t.Cleanup(func() {
		cfgFile = originalCfgFile
		searchConfigFile = originalSearchConfigFile
		cfg = originalConfig
		rootCmd.SetArgs(nil)
		rootCmd.SetOut(nil)
		rootCmd.SetErr(nil)
	})

	cfgFile = ""
	searchConfigFile = func(relPath string) (string, error) {
		if relPath != configRelativePath() {
			t.Fatalf("unexpected config search path %q", relPath)
		}
		return configPath, nil
	}

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	rootCmd.SetOut(&stdout)
	rootCmd.SetErr(&stderr)
	rootCmd.SetArgs([]string{})

	if _, err := rootCmd.ExecuteC(); err != nil {
		t.Fatalf("execute root command: %v", err)
	}

	if strings.TrimSpace(stdout.String()) != "alpha" {
		t.Fatalf("expected generated word from config, got %q", stdout.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("expected no stderr output, got %q", stderr.String())
	}
}

func TestRootCommandRejectsUnexpectedArgs(t *testing.T) {
	originalCfgFile := cfgFile
	originalSearchConfigFile := searchConfigFile
	originalConfig := cfg
	t.Cleanup(func() {
		cfgFile = originalCfgFile
		searchConfigFile = originalSearchConfigFile
		cfg = originalConfig
		rootCmd.SetArgs(nil)
		rootCmd.SetOut(nil)
		rootCmd.SetErr(nil)
	})

	cfgFile = ""
	searchConfigFile = func(relPath string) (string, error) {
		if relPath != configRelativePath() {
			t.Fatalf("unexpected config search path %q", relPath)
		}
		return "", errConfigFileNotFound
	}

	rootCmd.SetArgs([]string{"genrate"})

	_, err := rootCmd.ExecuteC()
	if err == nil {
		t.Fatal("expected root command to reject unexpected args")
	}
	if !strings.Contains(err.Error(), "unknown command \"genrate\"") {
		t.Fatalf("expected unknown command error, got %v", err)
	}
}

func TestTOMLLiteralStringEscapesSingleQuotes(t *testing.T) {
	input := `C:\tmp\it's\dataset.json`
	got := tomlLiteralString(input)
	want := `'C:\tmp\it''s\dataset.json'`
	if got != want {
		t.Fatalf("expected %q, got %q", want, got)
	}
}

func writeRootConfigFile(t *testing.T) string {
	t.Helper()

	datasetPath := filepath.Join(t.TempDir(), "all.json")
	entries := []rootFixtureEntry{{Word: "alpha", Sources: []string{"fsu/wordle.txt"}}}
	content, err := json.Marshal(entries)
	if err != nil {
		t.Fatalf("marshal dataset: %v", err)
	}
	if err := os.WriteFile(datasetPath, append(content, '\n'), 0o600); err != nil {
		t.Fatalf("write dataset: %v", err)
	}

	configPath := filepath.Join(t.TempDir(), "config.toml")
	config := strings.Join([]string{
		"[generate]",
		"dataset = " + tomlLiteralString(datasetPath),
		"count = 1",
		"min_length = 5",
		"max_length = 5",
		"seed = 1",
	}, "\n") + "\n"
	if err := os.WriteFile(configPath, []byte(config), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	return configPath
}

func tomlLiteralString(value string) string {
	// TOML literal strings treat backslashes as plain characters.
	escaped := strings.ReplaceAll(value, "'", "''")
	return "'" + escaped + "'"
}
