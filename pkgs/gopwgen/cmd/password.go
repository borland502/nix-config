package cmd

import (
	"context"
	"fmt"

	"github.com/borland502/gopwgen/pkg/password"

	"github.com/spf13/cobra"
)

var passwordCmd = &cobra.Command{
	Use:   "password",
	Short: "Generate secure passphrases from words with optional special characters",
	Long: `Generate secure passphrases using random words from wordgen library.

The generated passphrase format is configurable with:
  - Word count (default 5)
  - Maximum word length (default 12)
  - Custom separator (default -)
  - Case formatting: traincase, camelcase, lower, upper, title, none
  - Optional appending of digits and special characters for password requirements

Example: Harbor-Lantern-Maple-Canvas-Breeze7!
`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runPassword(cmd)
	},
}

func init() {
	rootCmd.AddCommand(passwordCmd)

	passwordCmd.Flags().IntVar(
		&passwordFlagCount,
		"word-count",
		0,
		"number of words in the passphrase (0 = use config)",
	)

	passwordCmd.Flags().StringVar(
		&passwordFlagSeparator,
		"separator",
		"",
		"separator between words (empty = use config)",
	)

	passwordCmd.Flags().StringVar(
		&passwordFlagCaseFormat,
		"case-format",
		"",
		"case formatting: traincase, camelcase, lower, upper, title, none (empty = use config)",
	)

	passwordCmd.Flags().BoolVar(
		&passwordFlagAppendRequirements,
		"append-requirements",
		false,
		"append digits and special characters for common password requirements",
	)

	passwordCmd.Flags().IntVar(
		&passwordFlagBatch,
		"batch",
		1,
		"generate multiple passwords",
	)
}

var (
	passwordFlagCount              int
	passwordFlagSeparator          string
	passwordFlagCaseFormat         string
	passwordFlagAppendRequirements bool
	passwordFlagBatch              int
)

func runPassword(cmd *cobra.Command) error {
	ctx := context.Background()

	// Create password generator using config
	cfg := copyPasswordConfig(cmd)
	gen, err := password.NewGenerator(ctx, cfg)
	if err != nil {
		return fmt.Errorf("failed to initialize password generator: %w", err)
	}

	// Generate passwords
	count := passwordFlagBatch
	if count < 1 {
		count = 1
	}

	if count == 1 {
		pwd, err := gen.Generate(ctx)
		if err != nil {
			return fmt.Errorf("failed to generate password: %w", err)
		}
		fmt.Fprintln(cmd.OutOrStdout(), pwd)
	} else {
		pwds, err := gen.GenerateBatch(ctx, count)
		if err != nil {
			return fmt.Errorf("failed to generate passwords: %w", err)
		}
		for _, pwd := range pwds {
			fmt.Fprintln(cmd.OutOrStdout(), pwd)
		}
	}

	return nil
}

// copyPasswordConfig creates a password config from the loaded config and flag overrides
func copyPasswordConfig(cmd *cobra.Command) password.Config {
	config := password.Config{
		WordCount:          cfg.Password.WordCount,
		MaxWordLength:      cfg.Password.MaxWordLength,
		Separator:          cfg.Password.Separator,
		CaseFormat:         cfg.Password.CaseFormat,
		AppendRequirements: cfg.Password.AppendRequirements,
		Requirements: password.PasswordRequirement{
			IncludeUppercase: cfg.Password.RequireUppercase,
			IncludeLowercase: cfg.Password.RequireLowercase,
			IncludeNumbers:   cfg.Password.RequireNumbers,
			IncludeSpecial:   cfg.Password.RequireSpecial,
		},
		WordgenDataset: cfg.Password.WordgenDataset,
	}

	// Apply flag overrides
	if passwordFlagCount > 0 {
		config.WordCount = passwordFlagCount
	}

	if passwordFlagSeparator != "" {
		config.Separator = passwordFlagSeparator
	}

	if passwordFlagCaseFormat != "" {
		config.CaseFormat = passwordFlagCaseFormat
	}

	if passwordFlagAppendRequirements {
		config.AppendRequirements = true
	}

	return config
}
