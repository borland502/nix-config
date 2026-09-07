/*
Copyright © 2026 Jeremy Hettenhouser <jhettenh@gmail.com>
*/
package cmd

import (
	"errors"
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var initConfigForce bool

var initConfigCmd = &cobra.Command{
	Use:   "init-config",
	Short: "Write a starter config file for the word generator",
	Long: fmt.Sprintf(
		"Write a starter TOML config file for the word generator to the default XDG location (%s). Use --config to target a different path.",
		defaultUserConfigFilePath(),
	),
	Annotations: map[string]string{
		skipConfigLoadAnnotation: "true",
	},
	RunE: func(cmd *cobra.Command, args []string) error {
		configPath, err := writableConfigFilePath()
		if err != nil {
			return err
		}

		if !initConfigForce {
			if _, err := os.Stat(configPath); err == nil {
				return fmt.Errorf("config file already exists at %s; use --force to overwrite", configPath)
			} else if !errors.Is(err, os.ErrNotExist) {
				return fmt.Errorf("check config file: %w", err)
			}
		}

		if err := os.WriteFile(configPath, []byte(renderConfig(defaultConfig())), 0o600); err != nil {
			return fmt.Errorf("write config file: %w", err)
		}

		fmt.Fprintf(cmd.OutOrStdout(), "wrote starter config to %s\n", configPath)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(initConfigCmd)
	initConfigCmd.Flags().BoolVar(&initConfigForce, "force", false, "overwrite an existing config file")
}
