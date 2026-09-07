package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:          binaryName,
	Short:        "Generate secure passphrases from random words with optional special characters",
	Long:         "gopwgen generates secure passphrases using random words from the wordgen library. When run without subcommands, it generates a password using configured settings.",
	SilenceUsage: true,
	PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
		if shouldSkipConfigLoad(cmd) {
			return nil
		}

		return loadConfig(cmd)
	},
	RunE: func(cmd *cobra.Command, args []string) error {
		// If a subcommand is being used, let it handle things
		if len(args) > 0 {
			return nil
		}
		// Generate a password using default config
		return runPassword(cmd)
	},
}

// Execute runs the root command while keeping the main package free of CLI
// wiring details. When the binary moves beyond the current demo objective,
// replace or add command registrations inside package cmd and leave main as a
// thin entrypoint.
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

	// Password generation flags for default/root command behavior
	rootCmd.Flags().IntVar(
		&passwordFlagCount,
		"word-count",
		0,
		"number of words in the passphrase (0 = use config)",
	)

	rootCmd.Flags().StringVar(
		&passwordFlagSeparator,
		"separator",
		"",
		"separator between words (empty = use config)",
	)

	rootCmd.Flags().StringVar(
		&passwordFlagCaseFormat,
		"case-format",
		"",
		"case formatting: traincase, camelcase, lower, upper, title, none (empty = use config)",
	)

	rootCmd.Flags().BoolVar(
		&passwordFlagAppendRequirements,
		"append-requirements",
		false,
		"append digits and special characters for common password requirements",
	)

	rootCmd.Flags().IntVar(
		&passwordFlagBatch,
		"batch",
		1,
		"generate multiple passwords",
	)
}
