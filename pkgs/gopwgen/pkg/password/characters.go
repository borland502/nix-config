package password

import (
	"crypto/rand"
	"math/big"
)

// PasswordRequirement defines which special characters to include for common password requirements.
type PasswordRequirement struct {
	// IncludeUppercase ensures at least one uppercase letter (handled by case formatting)
	IncludeUppercase bool
	// IncludeLowercase ensures at least one lowercase letter (handled by case formatting)
	IncludeLowercase bool
	// IncludeNumbers includes at least one digit
	IncludeNumbers bool
	// IncludeSpecial includes at least one special character like !@#$%^&*
	IncludeSpecial bool
}

const (
	// DefaultNumberChars are digits commonly used in passwords
	DefaultNumberChars = "0123456789"
	// DefaultSpecialChars are special characters commonly accepted in passwords
	DefaultSpecialChars = "!@#$%^&*-_=+?."
)

// SpecialCharacters contains characters to append/prepend to meet requirements.
type SpecialCharacters struct {
	Numbers []string
	Special []string
}

// GenerateSpecialCharacters generates random special characters to meet password requirements.
// It returns up to one number and one special character.
func GenerateSpecialCharacters(req PasswordRequirement) (SpecialCharacters, error) {
	var chars SpecialCharacters

	if req.IncludeNumbers {
		num, err := randomChar(DefaultNumberChars)
		if err != nil {
			return chars, err
		}
		chars.Numbers = append(chars.Numbers, num)
	}

	if req.IncludeSpecial {
		special, err := randomChar(DefaultSpecialChars)
		if err != nil {
			return chars, err
		}
		chars.Special = append(chars.Special, special)
	}

	return chars, nil
}

// randomChar returns a random character from the provided string.
func randomChar(chars string) (string, error) {
	if len(chars) == 0 {
		return "", nil
	}

	randIndex, err := rand.Int(rand.Reader, big.NewInt(int64(len(chars))))
	if err != nil {
		return "", err
	}

	return string(chars[randIndex.Int64()]), nil
}
