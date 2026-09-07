package cmd

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/adrg/xdg"
	"github.com/spf13/viper"
)

func TestConfigureConfigFilePropagatesSearchErrors(t *testing.T) {
	originalCfgFile := cfgFile
	originalSearch := searchConfigFile
	t.Cleanup(func() {
		cfgFile = originalCfgFile
		searchConfigFile = originalSearch
	})

	cfgFile = ""
	expectedErr := errors.New("boom")
	searchConfigFile = func(relPath string) (string, error) {
		if relPath != filepath.Join(appName, configFileName()) {
			t.Fatalf("unexpected relative path %q", relPath)
		}

		return "", expectedErr
	}

	_, err := configureConfigFile(viper.New())
	if !errors.Is(err, expectedErr) {
		t.Fatalf("expected search error %v, got %v", expectedErr, err)
	}
}

func TestConfigureConfigFileIgnoresConfigNotFound(t *testing.T) {
	originalCfgFile := cfgFile
	originalSearch := searchConfigFile
	t.Cleanup(func() {
		cfgFile = originalCfgFile
		searchConfigFile = originalSearch
	})

	cfgFile = ""
	searchConfigFile = func(relPath string) (string, error) {
		if relPath != filepath.Join(appName, configFileName()) {
			t.Fatalf("unexpected relative path %q", relPath)
		}

		return "", errConfigFileNotFound
	}

	shouldRead, err := configureConfigFile(viper.New())
	if err != nil {
		t.Fatalf("expected no error for missing config, got %v", err)
	}
	if shouldRead {
		t.Fatal("expected missing config to skip reading")
	}
}

func TestConfigureConfigFileUsesExplicitPath(t *testing.T) {
	originalCfgFile := cfgFile
	originalSearch := searchConfigFile
	t.Cleanup(func() {
		cfgFile = originalCfgFile
		searchConfigFile = originalSearch
	})

	configPath := filepath.Join(t.TempDir(), "config.toml")
	cfgFile = configPath
	searchCalled := false
	searchConfigFile = func(string) (string, error) {
		searchCalled = true
		return "", nil
	}

	shouldRead, err := configureConfigFile(viper.New())
	if err != nil {
		t.Fatalf("expected no error for explicit config path, got %v", err)
	}
	if !shouldRead {
		t.Fatal("expected explicit config path to be read")
	}
	if searchCalled {
		t.Fatal("expected explicit config path to bypass XDG search")
	}
}

func TestSearchConfigFileInXDGPathsPrefersConfigHome(t *testing.T) {
	relPath := filepath.Join(appName, configFileName())
	configHome := t.TempDir()
	configDir := t.TempDir()
	setXDGConfigPaths(t, configHome, []string{configDir})

	homeConfigPath := filepath.Join(configHome, relPath)
	dirConfigPath := filepath.Join(configDir, relPath)
	writeConfigFixture(t, homeConfigPath)
	writeConfigFixture(t, dirConfigPath)

	gotPath, err := searchConfigFileInXDGPaths(relPath)
	if err != nil {
		t.Fatalf("expected config path, got error: %v", err)
	}
	if gotPath != homeConfigPath {
		t.Fatalf("expected config home path %q, got %q", homeConfigPath, gotPath)
	}
}

func TestSearchConfigFileInXDGPathsUsesConfigDirsInOrder(t *testing.T) {
	relPath := filepath.Join(appName, configFileName())
	configHome := t.TempDir()
	firstConfigDir := t.TempDir()
	secondConfigDir := t.TempDir()
	setXDGConfigPaths(t, configHome, []string{firstConfigDir, secondConfigDir})

	firstConfigPath := filepath.Join(firstConfigDir, relPath)
	secondConfigPath := filepath.Join(secondConfigDir, relPath)
	writeConfigFixture(t, firstConfigPath)
	writeConfigFixture(t, secondConfigPath)

	gotPath, err := searchConfigFileInXDGPaths(relPath)
	if err != nil {
		t.Fatalf("expected config path, got error: %v", err)
	}
	if gotPath != firstConfigPath {
		t.Fatalf("expected first config dir path %q, got %q", firstConfigPath, gotPath)
	}
}

func TestSearchConfigFileInXDGPathsWrapsNotFound(t *testing.T) {
	relPath := filepath.Join(appName, configFileName())
	configHome := t.TempDir()
	configDir := t.TempDir()
	setXDGConfigPaths(t, configHome, []string{configDir})

	_, err := searchConfigFileInXDGPaths(relPath)
	if !errors.Is(err, errConfigFileNotFound) {
		t.Fatalf("expected not found error, got %v", err)
	}
}

func TestSearchConfigFileInXDGPathsRejectsDirectoryCandidate(t *testing.T) {
	relPath := filepath.Join(appName, configFileName())
	configHome := t.TempDir()
	setXDGConfigPaths(t, configHome, nil)

	directoryPath := filepath.Join(configHome, relPath)
	if err := os.MkdirAll(directoryPath, 0o755); err != nil {
		t.Fatalf("create directory candidate: %v", err)
	}

	_, err := searchConfigFileInXDGPaths(relPath)
	if err == nil {
		t.Fatal("expected error for directory candidate path")
	}
	if !strings.Contains(err.Error(), "config path is a directory") {
		t.Fatalf("expected directory candidate error, got %v", err)
	}
}

func setXDGConfigPaths(t *testing.T, configHome string, configDirs []string) {
	t.Helper()

	originalConfigHome := xdg.ConfigHome
	originalConfigDirs := append([]string(nil), xdg.ConfigDirs...)
	xdg.ConfigHome = configHome
	xdg.ConfigDirs = append([]string(nil), configDirs...)
	t.Cleanup(func() {
		xdg.ConfigHome = originalConfigHome
		xdg.ConfigDirs = originalConfigDirs
	})
}

func writeConfigFixture(t *testing.T, configPath string) {
	t.Helper()

	if err := os.MkdirAll(filepath.Dir(configPath), 0o755); err != nil {
		t.Fatalf("create config fixture directory: %v", err)
	}
	if err := os.WriteFile(configPath, []byte("demo = true\n"), 0o600); err != nil {
		t.Fatalf("write config fixture: %v", err)
	}
}
