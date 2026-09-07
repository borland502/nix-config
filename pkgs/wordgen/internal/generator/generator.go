package generator

import (
	"context"
	"encoding/json"
	"fmt"
	"iter"
	"math/rand"
	"strings"
	"time"
	"unicode/utf8"
)

// Request controls word selection from the JSON index.
type Request struct {
	Dataset   string
	Count     int
	MinLength int
	MaxLength int
	Prefix    string
	Contains  string
	Sources   []string
	Seed      int64
}

type wordEntry struct {
	Word    string   `json:"word"`
	Sources []string `json:"sources"`
}

type wordIndex struct {
	path string
}

type compiledMatcher struct {
	prefix         string
	contains       string
	minLength      int
	maxLength      int
	allowedSources map[string]struct{}
}

func (index wordIndex) entries() iter.Seq2[wordEntry, error] {
	return func(yield func(wordEntry, error) bool) {
		reader, err := openWordIndexReader(index.path)
		if err != nil {
			yield(wordEntry{}, err)
			return
		}
		defer reader.Close()

		decoder := json.NewDecoder(reader)
		firstToken, err := decoder.Token()
		if err != nil {
			yield(wordEntry{}, fmt.Errorf("read word index header: %w", err))
			return
		}

		delim, ok := firstToken.(json.Delim)
		if !ok || delim != '[' {
			yield(wordEntry{}, fmt.Errorf("decode word index: expected JSON array in %s", index.path))
			return
		}

		for decoder.More() {
			var entry wordEntry
			if err := decoder.Decode(&entry); err != nil {
				yield(wordEntry{}, fmt.Errorf("decode word index entry: %w", err))
				return
			}

			if !yield(entry, nil) {
				return
			}
		}

		lastToken, err := decoder.Token()
		if err != nil {
			yield(wordEntry{}, fmt.Errorf("read word index footer: %w", err))
			return
		}

		delim, ok = lastToken.(json.Delim)
		if !ok || delim != ']' {
			yield(wordEntry{}, fmt.Errorf("decode word index: expected closing array in %s", index.path))
		}
	}
}

// SelectWords streams the JSON word index and returns up to Count sampled words.
func SelectWords(request Request) ([]string, int, error) {
	return SelectWordsWithContext(context.Background(), request)
}

// SelectWordsWithContext streams the JSON word index and returns up to Count sampled words.
func SelectWordsWithContext(ctx context.Context, request Request) ([]string, int, error) {
	if err := validateRequest(request); err != nil {
		return nil, 0, err
	}

	matcher := compileMatcher(request)
	seed := request.Seed
	if seed == 0 {
		seed = time.Now().UnixNano()
	}

	rng := rand.New(rand.NewSource(seed))
	selectedWords := make([]string, 0, request.Count)
	matchedCount := 0
	index := wordIndex{path: requestDatasetPath(request.Dataset)}

	for entry, err := range index.entries() {
		if err != nil {
			return nil, 0, err
		}
		if err := ctx.Err(); err != nil {
			return nil, 0, err
		}
		if !matcher.matches(entry) {
			continue
		}

		matchedCount++
		if len(selectedWords) < request.Count {
			selectedWords = append(selectedWords, entry.Word)
			continue
		}

		candidateIndex := rng.Intn(matchedCount)
		if candidateIndex < request.Count {
			selectedWords[candidateIndex] = entry.Word
		}
	}

	if len(selectedWords) > 1 {
		rng.Shuffle(len(selectedWords), func(left, right int) {
			selectedWords[left], selectedWords[right] = selectedWords[right], selectedWords[left]
		})
	}

	return selectedWords, matchedCount, nil
}

// StreamMatchedWordsWithContext streams matching words to the provided callback.
func StreamMatchedWordsWithContext(ctx context.Context, request Request, yield func(string) bool) (int, error) {
	if err := validateRequest(request); err != nil {
		return 0, err
	}

	matcher := compileMatcher(request)
	index := wordIndex{path: requestDatasetPath(request.Dataset)}
	matchedCount := 0

	for entry, err := range index.entries() {
		if err != nil {
			return matchedCount, err
		}
		if err := ctx.Err(); err != nil {
			return matchedCount, err
		}
		if !matcher.matches(entry) {
			continue
		}

		matchedCount++
		if !yield(entry.Word) {
			return matchedCount, nil
		}
	}

	return matchedCount, nil
}

func validateRequest(request Request) error {
	if request.Count < 1 {
		return fmt.Errorf("generate.count must be at least 1")
	}
	if request.MaxLength > 0 && request.MaxLength < request.MinLength {
		return fmt.Errorf("generate.max_length must be greater than or equal to generate.min_length")
	}

	return nil
}

func requestDatasetPath(path string) string {
	if strings.TrimSpace(path) == "" {
		return EmbeddedDatasetPath
	}

	return path
}

func compileMatcher(request Request) compiledMatcher {
	matcher := compiledMatcher{
		prefix:    strings.ToLower(request.Prefix),
		contains:  strings.ToLower(request.Contains),
		minLength: request.MinLength,
		maxLength: request.MaxLength,
	}

	if len(request.Sources) == 0 {
		return matcher
	}

	matcher.allowedSources = make(map[string]struct{}, len(request.Sources))
	for _, source := range request.Sources {
		matcher.allowedSources[strings.ToLower(source)] = struct{}{}
	}

	return matcher
}

func (matcher compiledMatcher) matches(entry wordEntry) bool {
	word := strings.ToLower(entry.Word)

	if matcher.prefix != "" && !strings.HasPrefix(word, matcher.prefix) {
		return false
	}
	if matcher.contains != "" && !strings.Contains(word, matcher.contains) {
		return false
	}

	wordLength := utf8.RuneCountInString(entry.Word)
	if wordLength < matcher.minLength {
		return false
	}
	if matcher.maxLength > 0 && wordLength > matcher.maxLength {
		return false
	}

	if len(matcher.allowedSources) == 0 {
		return true
	}

	for _, source := range entry.Sources {
		if _, ok := matcher.allowedSources[strings.ToLower(source)]; ok {
			return true
		}
	}

	return false
}
