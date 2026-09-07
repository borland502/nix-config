package password

import (
	"context"
	"fmt"
	"strings"

	"github.com/borland502/wordgen/pkg/wordgen"
)

// Config defines the password generation configuration.
type Config struct {
	// WordCount is the number of words in the passphrase
	WordCount int `mapstructure:"word_count"`
	// MaxWordLength limits word length to 12 characters as specified
	MaxWordLength int `mapstructure:"max_word_length"`
	// Separator is the character(s) used between words
	Separator string `mapstructure:"separator"`
	// CaseFormat defines how to format the words (traincase, camelcase, etc.)
	CaseFormat string `mapstructure:"case_format"`
	// AppendRequirements adds special characters to the end for common password requirements
	AppendRequirements bool `mapstructure:"append_requirements"`
	// Requirements defines which special characters to include if AppendRequirements is true
	Requirements PasswordRequirement `mapstructure:"requirements"`
	// WordgenDataset is the word source (e.g., "embedded://all.json.zst")
	WordgenDataset string `mapstructure:"wordgen_dataset"`
}

// Generator generates passwords using words and optional special characters.
type Generator struct {
	config Config
	words  wordgen.IndexedGenerator
}

// NewGenerator creates a new password generator.
// It loads the wordgen index once for efficient repeated use.
func NewGenerator(ctx context.Context, cfg Config) (*Generator, error) {
	if cfg.WordCount == 0 {
		cfg.WordCount = 5
	}
	if cfg.MaxWordLength == 0 {
		cfg.MaxWordLength = 12
	}
	if cfg.Separator == "" {
		cfg.Separator = "-"
	}
	if cfg.CaseFormat == "" {
		cfg.CaseFormat = "traincase"
	}
	if cfg.WordgenDataset == "" {
		cfg.WordgenDataset = "embedded://all.json.zst"
	}

	// Load the wordgen index once
	indexed, err := wordgen.LoadIndexed(cfg.WordgenDataset)
	if err != nil {
		return nil, fmt.Errorf("failed to load wordgen index: %w", err)
	}

	return &Generator{
		config: cfg,
		words:  indexed,
	}, nil
}

// Generate creates a password using the configured settings.
func (g *Generator) Generate(ctx context.Context) (string, error) {
	// Generate words using wordgen
	wordList, _, err := g.words.Generate(ctx, wordgen.Config{
		Count:     g.config.WordCount,
		MaxLength: g.config.MaxWordLength,
		MinLength: 3, // Minimum 3 characters for meaningful words
	})
	if err != nil {
		return "", fmt.Errorf("failed to generate words: %w", err)
	}

	// Format words according to case format
	format := CaseFormat(g.config.CaseFormat)
	formattedWords := FormatWords(wordList, format)

	// Build the passphrase
	passphrase := strings.Join(formattedWords, g.config.Separator)

	// Add special characters if required
	if g.config.AppendRequirements {
		specialChars, err := GenerateSpecialCharacters(g.config.Requirements)
		if err != nil {
			return "", fmt.Errorf("failed to generate special characters: %w", err)
		}

		// Append numbers and special characters
		appendStr := ""
		for _, num := range specialChars.Numbers {
			appendStr += num
		}
		for _, char := range specialChars.Special {
			appendStr += char
		}

		passphrase = passphrase + appendStr
	}

	return passphrase, nil
}

// GenerateBatch generates multiple passwords.
func (g *Generator) GenerateBatch(ctx context.Context, count int) ([]string, error) {
	passwords := make([]string, count)
	for i := 0; i < count; i++ {
		pwd, err := g.Generate(ctx)
		if err != nil {
			return nil, err
		}
		passwords[i] = pwd
	}
	return passwords, nil
}
