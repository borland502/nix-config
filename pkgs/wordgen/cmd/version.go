package cmd

import (
	"fmt"

	"github.com/borland502/wordgen/internal/version"
	"github.com/spf13/cobra"
)

// versionCmd represents the version command
var versionCmd = &cobra.Command{
	Use:         "version",
	Short:       "Show version information",
	Annotations: map[string]string{skipConfigLoadAnnotation: "true"},
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Fprintf(cmd.OutOrStdout(), "wordgen version %s (commit %s, built %s)\n", version.Version, version.Commit, version.Date)
	},
}

func init() {
	rootCmd.AddCommand(versionCmd)
}
