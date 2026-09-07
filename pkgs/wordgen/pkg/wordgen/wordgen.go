package wordgen

import (
	"context"
	"fmt"

	"github.com/borland502/wordgen/internal/generator"
)

const EmbeddedDataset = generator.EmbeddedDatasetPath

// Config is the public library request model for generating words.
type Config struct {
	Dataset   string
	Count     int
	MinLength int
	MaxLength int
	Prefix    string
	Contains  string
	Sources   []string
	Seed      int64
}

// Generator provides a reusable library entrypoint for word generation.
type Generator struct {
	config Config
}

// IndexedGenerator serves requests from an in-memory indexed dataset.
type IndexedGenerator struct {
	indexed *generator.IndexedDataset
}

// New constructs a reusable generator with the provided config.
func New(config Config) Generator {
	return Generator{config: config}
}

// LoadIndexed loads a dataset once for repeated low-latency generation calls.
func LoadIndexed(datasetPath string) (IndexedGenerator, error) {
	indexed, err := generator.LoadIndexedDataset(datasetPath)
	if err != nil {
		return IndexedGenerator{}, err
	}

	return IndexedGenerator{indexed: indexed}, nil
}

// Generate returns a random sample of words and the total matched count.
func Generate(ctx context.Context, config Config) ([]string, int, error) {
	return generator.SelectWordsWithContext(ctx, toRequest(config))
}

// Generate returns a random sample of words and the total matched count.
func (generatorInstance Generator) Generate(ctx context.Context) ([]string, int, error) {
	return Generate(ctx, generatorInstance.config)
}

// Stream streams matching words to the callback and returns the matched count.
func Stream(ctx context.Context, config Config, yield func(string) bool) (int, error) {
	return generator.StreamMatchedWordsWithContext(ctx, toRequest(config), yield)
}

// Stream streams matching words to the callback and returns the matched count.
func (generatorInstance Generator) Stream(ctx context.Context, yield func(string) bool) (int, error) {
	return Stream(ctx, generatorInstance.config, yield)
}

// Generate returns a random sample of words and the total matched count.
func (generatorInstance IndexedGenerator) Generate(ctx context.Context, config Config) ([]string, int, error) {
	if generatorInstance.indexed == nil {
		return nil, 0, fmt.Errorf("indexed generator is not initialized")
	}

	return generatorInstance.indexed.SelectWordsWithContext(ctx, toRequest(config))
}

// Stream streams matching words to the callback and returns the matched count.
func (generatorInstance IndexedGenerator) Stream(ctx context.Context, config Config, yield func(string) bool) (int, error) {
	if generatorInstance.indexed == nil {
		return 0, fmt.Errorf("indexed generator is not initialized")
	}

	return generatorInstance.indexed.StreamMatchedWordsWithContext(ctx, toRequest(config), yield)
}

func toRequest(config Config) generator.Request {
	return generator.Request{
		Dataset:   config.Dataset,
		Count:     config.Count,
		MinLength: config.MinLength,
		MaxLength: config.MaxLength,
		Prefix:    config.Prefix,
		Contains:  config.Contains,
		Sources:   config.Sources,
		Seed:      config.Seed,
	}
}
