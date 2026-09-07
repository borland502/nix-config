package assets

import _ "embed"

// AllJSONZst contains the bundled compressed dataset used by default.
//
//go:embed all.json.zst
var AllJSONZst []byte
