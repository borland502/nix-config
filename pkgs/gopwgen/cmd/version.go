package cmd

import (
	"fmt"

	"github.com/borland502/gopwgen/internal/version"

	"github.com/spf13/cobra"
)

var versionCmd = &cobra.Command{
	Use:         "version",
	Short:       "Show version information",
	Annotations: map[string]string{skipConfigLoadAnnotation: "true"},
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Fprintf(cmd.OutOrStdout(), "%s version %s (commit %s, built %s)\n", binaryName, version.Version, version.Commit, version.Date)
	},
}

func init() {
	rootCmd.AddCommand(versionCmd)
}
