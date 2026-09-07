package cmd

import (
	"bytes"
	"testing"

	"github.com/borland502/gopwgen/internal/version"

	"github.com/spf13/cobra"
)

func TestVersionCommand(t *testing.T) {
	output := &bytes.Buffer{}
	command := &cobra.Command{Run: versionCmd.Run}
	command.SetOut(output)

	command.Run(command, nil)

	result := output.String()
	if result == "" {
		t.Fatal("version command produced no output")
	}

	if !bytes.Contains(output.Bytes(), []byte(binaryName+" version")) {
		t.Errorf("output missing binary version prefix: %s", result)
	}

	if !bytes.Contains(output.Bytes(), []byte(version.Version)) {
		t.Errorf("output missing version %q: %s", version.Version, result)
	}

	if !bytes.Contains(output.Bytes(), []byte(version.Commit)) {
		t.Errorf("output missing commit %q: %s", version.Commit, result)
	}

	if !bytes.Contains(output.Bytes(), []byte(version.Date)) {
		t.Errorf("output missing build date %q: %s", version.Date, result)
	}
}
