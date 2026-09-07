package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:          binaryName,
	Short:        "Generate filtered random words from the indexed word datasets",
	SilenceUsage: true,
	Args:         cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runGenerate(cmd)
	},
	PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
		if shouldSkipConfigLoad(cmd) {
			return nil
		}

		return loadConfig(cmd)
	},
}

// Execute runs the root command while keeping the main package free of CLI
// wiring details.
func Execute() {
	cobra.CheckErr(rootCmd.Execute())
}

func init() {
	rootCmd.PersistentFlags().StringVar(
		&cfgFile,
		"config",
		"",
		fmt.Sprintf("path to a TOML config file (default XDG path: %s)", defaultUserConfigFilePath()),
	)
}
