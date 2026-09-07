// Package version holds build-time injected version metadata.
// These variables are set by the linker (typically via GoReleaser) at build time.
//
// Usage in ldflags:
//
//	-ldflags "-X github.com/borland502/wordgen/internal/version.Version=v1.2.3 ..."
package version

// Version is the semantic version of the build (e.g., "v1.2.3", or "dev" for debug builds).
var Version = "dev"

// Commit is the git commit hash included in this build.
var Commit = "unknown"

// Date is the build timestamp in RFC3339 format (e.g., "2026-04-24T22:15:30Z").
var Date = "unknown"
