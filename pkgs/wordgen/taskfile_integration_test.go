package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
)

const skipTaskIntegrationEnv = "WORDGEN_SKIP_TASK_INTEGRATION"

func TestTaskUndeployPreservesExistingConfig(t *testing.T) {
	skipTaskIntegrationIfNeeded(t)

	installDir := t.TempDir()
	configDir := t.TempDir()
	configPath := filepath.Join(configDir, "config.toml")
	markerPath := configPath + ".task-managed"
	const wantConfig = "sentinel\n"

	if err := os.WriteFile(configPath, []byte(wantConfig), 0o600); err != nil {
		t.Fatalf("write existing config: %v", err)
	}

	repoRoot := repoRoot(t)
	runTask(t, repoRoot, "deploy", "INSTALL_DIR="+installDir, "CONFIG_PATH="+configPath)
	runTask(t, repoRoot, "undeploy", "INSTALL_DIR="+installDir, "CONFIG_PATH="+configPath)

	gotConfig, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("expected config to be preserved, got error: %v", err)
	}
	if string(gotConfig) != wantConfig {
		t.Fatalf("expected preserved config %q, got %q", wantConfig, string(gotConfig))
	}
	if _, err := os.Stat(markerPath); !os.IsNotExist(err) {
		t.Fatalf("expected no task-managed marker for existing config, got %v", err)
	}
	if _, err := os.Stat(filepath.Join(installDir, "wordgen")); !os.IsNotExist(err) {
		t.Fatalf("expected installed binary to be removed, got %v", err)
	}
}

func TestTaskUndeployRemovesGeneratedConfig(t *testing.T) {
	skipTaskIntegrationIfNeeded(t)

	installDir := t.TempDir()
	configDir := t.TempDir()
	configPath := filepath.Join(configDir, "config.toml")
	markerPath := configPath + ".task-managed"
	repoRoot := repoRoot(t)

	runTask(t, repoRoot, "deploy", "INSTALL_DIR="+installDir, "CONFIG_PATH="+configPath)
	if _, err := os.Stat(configPath); err != nil {
		t.Fatalf("expected deploy to create config, got %v", err)
	}
	if _, err := os.Stat(markerPath); err != nil {
		t.Fatalf("expected deploy to create config marker, got %v", err)
	}

	runTask(t, repoRoot, "undeploy", "INSTALL_DIR="+installDir, "CONFIG_PATH="+configPath)

	if _, err := os.Stat(configPath); !os.IsNotExist(err) {
		t.Fatalf("expected generated config to be removed, got %v", err)
	}
	if _, err := os.Stat(markerPath); !os.IsNotExist(err) {
		t.Fatalf("expected config marker to be removed, got %v", err)
	}
	if _, err := os.Stat(filepath.Join(installDir, "wordgen")); !os.IsNotExist(err) {
		t.Fatalf("expected installed binary to be removed, got %v", err)
	}
}

func skipTaskIntegrationIfNeeded(t *testing.T) {
	t.Helper()

	if os.Getenv(skipTaskIntegrationEnv) == "1" {
		t.Skip("skipping recursive task integration test")
	}
	if runtime.GOOS == "windows" {
		t.Skip("task integration test uses POSIX shell commands")
	}
	if _, err := exec.LookPath("task"); err != nil {
		t.Skip("task executable not available")
	}
}

func repoRoot(t *testing.T) string {
	t.Helper()

	_, filePath, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve repository root")
	}

	return filepath.Dir(filePath)
}

func runTask(t *testing.T, dir string, args ...string) string {
	t.Helper()

	command := exec.Command("task", args...)
	command.Dir = dir
	command.Env = append(os.Environ(), skipTaskIntegrationEnv+"=1")
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("task %v failed: %v\n%s", args, err, string(output))
	}

	return string(output)
}
