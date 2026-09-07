package cmd

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/borland502/gopwgen/internal/appconfig"

	"github.com/adrg/xdg"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

const (
	appName                  = "gopwgen"
	binaryName               = "gopwgen"
	envPrefix                = "GOPWGEN"
	configBaseName           = "config"
	configExtension          = "toml"
	passwordSectionKey       = "password"
	skipConfigLoadAnnotation = "skip-config-load"
)

type Config = appconfig.Config

type PasswordConfig = appconfig.PasswordConfig

var errConfigFileNotFound = errors.New("config file not found")

var (
	cfgFile          string
	loadedConfigPath string
	cfg              = defaultConfig()
	searchConfigFile = searchConfigFileInXDGPaths
)

func defaultConfig() Config {
	return appconfig.Default()
}

func configFileName() string {
	return configBaseName + "." + configExtension
}

func configRelativePath() string {
	return filepath.Join(appName, configFileName())
}

func defaultUserConfigFilePath() string {
	return filepath.Join(xdg.ConfigHome, configRelativePath())
}

func configSourceDescription() string {
	if loadedConfigPath != "" {
		return loadedConfigPath
	}

	return "defaults, environment variables, and flags"
}

func shouldSkipConfigLoad(cmd *cobra.Command) bool {
	return cmd.Annotations[skipConfigLoadAnnotation] == "true"
}

func loadConfig(cmd *cobra.Command) error {
	loader, err := newConfigLoader(cmd)
	if err != nil {
		return err
	}

	loadedConfigPath = ""

	shouldRead, err := configureConfigFile(loader)
	if err != nil {
		return err
	}

	if shouldRead {
		if err := loader.ReadInConfig(); err != nil {
			return fmt.Errorf("read config: %w", err)
		}
		loadedConfigPath = loader.ConfigFileUsed()
	}

	cfg = defaultConfig()
	if err := loader.Unmarshal(&cfg); err != nil {
		return fmt.Errorf("decode config: %w", err)
	}

	return nil
}

func newConfigLoader(cmd *cobra.Command) (*viper.Viper, error) {
	defaults := defaultConfig()
	loader := viper.New()

	loader.SetEnvPrefix(envPrefix)
	loader.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	loader.AutomaticEnv()

	loader.SetDefault(passwordSectionKey+".word_count", defaults.Password.WordCount)
	loader.SetDefault(passwordSectionKey+".max_word_length", defaults.Password.MaxWordLength)
	loader.SetDefault(passwordSectionKey+".separator", defaults.Password.Separator)
	loader.SetDefault(passwordSectionKey+".case_format", defaults.Password.CaseFormat)
	loader.SetDefault(passwordSectionKey+".append_requirements", defaults.Password.AppendRequirements)
	loader.SetDefault(passwordSectionKey+".require_uppercase", defaults.Password.RequireUppercase)
	loader.SetDefault(passwordSectionKey+".require_lowercase", defaults.Password.RequireLowercase)
	loader.SetDefault(passwordSectionKey+".require_numbers", defaults.Password.RequireNumbers)
	loader.SetDefault(passwordSectionKey+".require_special", defaults.Password.RequireSpecial)
	loader.SetDefault(passwordSectionKey+".wordgen_dataset", defaults.Password.WordgenDataset)

	for _, key := range []string{
		passwordSectionKey + ".word_count",
		passwordSectionKey + ".max_word_length",
		passwordSectionKey + ".separator",
		passwordSectionKey + ".case_format",
		passwordSectionKey + ".append_requirements",
		passwordSectionKey + ".require_uppercase",
		passwordSectionKey + ".require_lowercase",
		passwordSectionKey + ".require_numbers",
		passwordSectionKey + ".require_special",
		passwordSectionKey + ".wordgen_dataset",
	} {
		if err := loader.BindEnv(key); err != nil {
			return nil, fmt.Errorf("bind env %s: %w", key, err)
		}
	}

	return loader, nil
}

func configureConfigFile(loader *viper.Viper) (bool, error) {
	if cfgFile != "" {
		loader.SetConfigFile(cfgFile)
		return true, nil
	}

	configPath, err := searchConfigFile(configRelativePath())
	if err != nil {
		if errors.Is(err, errConfigFileNotFound) {
			return false, nil
		}

		return false, fmt.Errorf("search config file: %w", err)
	}

	loader.SetConfigFile(configPath)
	return true, nil
}

func searchConfigFileInXDGPaths(relPath string) (string, error) {
	searchPaths := append([]string{xdg.ConfigHome}, xdg.ConfigDirs...)
	searchedPaths := make([]string, 0, len(searchPaths))

	for _, basePath := range searchPaths {
		candidatePath := filepath.Join(basePath, relPath)
		info, err := os.Stat(candidatePath)
		if err == nil {
			if info.IsDir() {
				return "", fmt.Errorf("config path is a directory: %s", candidatePath)
			}

			return candidatePath, nil
		}
		if errors.Is(err, os.ErrNotExist) {
			searchedPaths = append(searchedPaths, filepath.Dir(candidatePath))
			continue
		}

		return "", fmt.Errorf("stat config path %s: %w", candidatePath, err)
	}

	return "", fmt.Errorf("%w: %s", errConfigFileNotFound, strings.Join(searchedPaths, ", "))
}

func writableConfigFilePath() (string, error) {
	if cfgFile != "" {
		if err := os.MkdirAll(filepath.Dir(cfgFile), 0o700); err != nil {
			return "", fmt.Errorf("create config directory: %w", err)
		}
		return cfgFile, nil
	}

	configPath, err := xdg.ConfigFile(configRelativePath())
	if err != nil {
		return "", fmt.Errorf("resolve XDG config path: %w", err)
	}

	return configPath, nil
}

func renderConfig(config Config) string {
	return appconfig.Render(config, binaryName)
}
