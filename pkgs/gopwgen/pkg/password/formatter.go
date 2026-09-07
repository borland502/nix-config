package password

import (
	"strings"
	"unicode"
)

// CaseFormat defines the supported case transformations for passphrases.
type CaseFormat string

const (
	// CaseFormatNone keeps words as-is
	CaseFormatNone CaseFormat = "none"
	// CaseFormatLower converts to lowercase
	CaseFormatLower CaseFormat = "lower"
	// CaseFormatUpper converts to uppercase
	CaseFormatUpper CaseFormat = "upper"
	// CaseFormatTitle converts to Title Case
	CaseFormatTitle CaseFormat = "title"
	// CaseFormatTrainCase converts to Train-Case (each word capitalized)
	CaseFormatTrainCase CaseFormat = "traincase"
	// CaseFormatCamelCase converts to camelCase (first word lowercase, rest capitalized)
	CaseFormatCamelCase CaseFormat = "camelcase"
)

// FormatWords applies the specified case transformation to a slice of words.
func FormatWords(words []string, format CaseFormat) []string {
	if len(words) == 0 {
		return words
	}

	formatted := make([]string, len(words))
	copy(formatted, words)

	switch format {
	case CaseFormatNone:
		// No transformation
	case CaseFormatLower:
		for i := range formatted {
			formatted[i] = strings.ToLower(formatted[i])
		}
	case CaseFormatUpper:
		for i := range formatted {
			formatted[i] = strings.ToUpper(formatted[i])
		}
	case CaseFormatTitle:
		for i := range formatted {
			formatted[i] = strings.Title(strings.ToLower(formatted[i]))
		}
	case CaseFormatTrainCase:
		// Train-Case: Each word is capitalized
		for i := range formatted {
			formatted[i] = capitalizeWord(formatted[i])
		}
	case CaseFormatCamelCase:
		// camelCase: first word lowercase, rest capitalized
		formatted[0] = strings.ToLower(formatted[0])
		for i := 1; i < len(formatted); i++ {
			formatted[i] = capitalizeWord(formatted[i])
		}
	}

	return formatted
}

// capitalizeWord capitalizes the first letter and lowercases the rest.
func capitalizeWord(word string) string {
	if len(word) == 0 {
		return word
	}

	runes := []rune(strings.ToLower(word))
	runes[0] = unicode.ToUpper(runes[0])
	return string(runes)
}
