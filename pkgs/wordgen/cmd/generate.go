/*
Copyright © 2026 Jeremy Hettenhouser <jhettenh@gmail.com>
*/
package cmd

import (
	"context"
	"fmt"

	"github.com/borland502/wordgen/internal/generator"
	"github.com/spf13/cobra"
)

var generateCmd = &cobra.Command{
	Use:   "generate",
	Short: "Generate random words from the indexed word datasets",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runGenerate(cmd)
	},
}

func runGenerate(cmd *cobra.Command) error {
	ctx := cmd.Context()
	if ctx == nil {
		ctx = context.Background()
	}
	selectedWords, matchedCount, err := generator.SelectWordsWithContext(ctx, cfg.Generate.ToRequest())
	if err != nil {
		return err
	}

	if len(selectedWords) == 0 {
		return fmt.Errorf("no words matched the configured filters in %s", cfg.Generate.Dataset)
	}

	for _, word := range selectedWords {
		fmt.Fprintln(cmd.OutOrStdout(), word)
	}

	if matchedCount < cfg.Generate.Count {
		fmt.Fprintf(cmd.ErrOrStderr(), "requested %d words but only %d matched the configured filters\n", cfg.Generate.Count, matchedCount)
	}

	return nil
}

func init() {
	rootCmd.AddCommand(generateCmd)

	defaults := defaultConfig()
	generateCmd.Flags().String("dataset", defaults.Generate.Dataset, "dataset source: embedded://all.json.zst (default) or path to all.json(.gz|.zst)")
	generateCmd.Flags().Int("count", defaults.Generate.Count, "number of words to emit")
	generateCmd.Flags().Int("min-length", defaults.Generate.MinLength, "minimum word length")
	generateCmd.Flags().Int("max-length", defaults.Generate.MaxLength, "maximum word length; set 0 to disable")
	generateCmd.Flags().String("prefix", defaults.Generate.Prefix, "require words to start with this prefix")
	generateCmd.Flags().String("contains", defaults.Generate.Contains, "require words to contain this substring")
	generateCmd.Flags().StringSlice("source", defaults.Generate.Sources, "restrict matches to one or more source files from all.json")
	generateCmd.Flags().Int64("seed", defaults.Generate.Seed, "random seed; 0 uses the current time")
}
