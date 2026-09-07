package cmd

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/adrg/xdg"
	"github.com/borland502/wordgen/internal/appconfig"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

const (
	appName                  = "wordgen"
	binaryName               = "wordgen"
	envPrefix                = "WORDGEN"
	configBaseName           = "config"
	configExtension          = "toml"
	generateSectionKey       = "generate"
	skipConfigLoadAnnotation = "skip-config-load"
)

type Config = appconfig.Config

type GenerateConfig = appconfig.GenerateConfig

var errConfigFileNotFound = errors.New("config file not found")

var (
	cfgFile          string
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

func shouldSkipConfigLoad(cmd *cobra.Command) bool {
	return cmd.Annotations[skipConfigLoadAnnotation] == "true"
}

func loadConfig(cmd *cobra.Command) error {
	loader, err := newConfigLoader(cmd)
	if err != nil {
		return err
	}

	shouldRead, err := configureConfigFile(loader)
	if err != nil {
		return err
	}

	if shouldRead {
		if err := loader.ReadInConfig(); err != nil {
			return fmt.Errorf("read config: %w", err)
		}
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

	loader.SetDefault(generateSectionKey+".dataset", defaults.Generate.Dataset)
	loader.SetDefault(generateSectionKey+".count", defaults.Generate.Count)
	loader.SetDefault(generateSectionKey+".min_length", defaults.Generate.MinLength)
	loader.SetDefault(generateSectionKey+".max_length", defaults.Generate.MaxLength)
	loader.SetDefault(generateSectionKey+".prefix", defaults.Generate.Prefix)
	loader.SetDefault(generateSectionKey+".contains", defaults.Generate.Contains)
	loader.SetDefault(generateSectionKey+".sources", defaults.Generate.Sources)
	loader.SetDefault(generateSectionKey+".seed", defaults.Generate.Seed)

	for _, key := range []string{
		generateSectionKey + ".dataset",
		generateSectionKey + ".count",
		generateSectionKey + ".min_length",
		generateSectionKey + ".max_length",
		generateSectionKey + ".prefix",
		generateSectionKey + ".contains",
		generateSectionKey + ".sources",
		generateSectionKey + ".seed",
	} {
		if err := loader.BindEnv(key); err != nil {
			return nil, fmt.Errorf("bind env %s: %w", key, err)
		}
	}

	if flag := cmd.Flags().Lookup("dataset"); flag != nil {
		if err := loader.BindPFlag(generateSectionKey+".dataset", flag); err != nil {
			return nil, fmt.Errorf("bind dataset flag: %w", err)
		}
	}
	if flag := cmd.Flags().Lookup("count"); flag != nil {
		if err := loader.BindPFlag(generateSectionKey+".count", flag); err != nil {
			return nil, fmt.Errorf("bind count flag: %w", err)
		}
	}
	if flag := cmd.Flags().Lookup("min-length"); flag != nil {
		if err := loader.BindPFlag(generateSectionKey+".min_length", flag); err != nil {
			return nil, fmt.Errorf("bind min-length flag: %w", err)
		}
	}
	if flag := cmd.Flags().Lookup("max-length"); flag != nil {
		if err := loader.BindPFlag(generateSectionKey+".max_length", flag); err != nil {
			return nil, fmt.Errorf("bind max-length flag: %w", err)
		}
	}
	if flag := cmd.Flags().Lookup("prefix"); flag != nil {
		if err := loader.BindPFlag(generateSectionKey+".prefix", flag); err != nil {
			return nil, fmt.Errorf("bind prefix flag: %w", err)
		}
	}
	if flag := cmd.Flags().Lookup("contains"); flag != nil {
		if err := loader.BindPFlag(generateSectionKey+".contains", flag); err != nil {
			return nil, fmt.Errorf("bind contains flag: %w", err)
		}
	}
	if flag := cmd.Flags().Lookup("source"); flag != nil {
		if err := loader.BindPFlag(generateSectionKey+".sources", flag); err != nil {
			return nil, fmt.Errorf("bind source flag: %w", err)
		}
	}
	if flag := cmd.Flags().Lookup("seed"); flag != nil {
		if err := loader.BindPFlag(generateSectionKey+".seed", flag); err != nil {
			return nil, fmt.Errorf("bind seed flag: %w", err)
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
