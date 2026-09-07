package generator

import (
	"bytes"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"strings"

	wordAssets "github.com/borland502/wordgen/assets"
	"github.com/klauspost/compress/zstd"
)

const EmbeddedDatasetPath = "embedded://all.json.zst"

type compositeReadCloser struct {
	reader io.Reader
	closer func() error
}

func (reader compositeReadCloser) Read(buffer []byte) (int, error) {
	return reader.reader.Read(buffer)
}

func (reader compositeReadCloser) Close() error {
	return reader.closer()
}

func openWordIndexReader(path string) (io.ReadCloser, error) {
	if isEmbeddedDatasetPath(path) {
		return openEmbeddedWordIndexReader()
	}

	var openErr error
	for _, candidatePath := range candidateWordIndexPaths(path) {
		file, err := os.Open(candidatePath)
		if err != nil {
			if os.IsNotExist(err) {
				openErr = err
				continue
			}
			return nil, fmt.Errorf("open word index %s: %w", candidatePath, err)
		}

		lowerPath := strings.ToLower(candidatePath)
		if strings.HasSuffix(lowerPath, ".zst") {
			zstdReader, err := zstd.NewReader(file)
			if err != nil {
				_ = file.Close()
				return nil, fmt.Errorf("open zstd word index %s: %w", candidatePath, err)
			}

			return compositeReadCloser{
				reader: zstdReader,
				closer: func() error {
					zstdReader.Close()
					return file.Close()
				},
			}, nil
		}

		if !strings.HasSuffix(lowerPath, ".gz") {
			return file, nil
		}

		gzipReader, err := gzip.NewReader(file)
		if err != nil {
			_ = file.Close()
			return nil, fmt.Errorf("open gzip word index %s: %w", candidatePath, err)
		}

		return compositeReadCloser{
			reader: gzipReader,
			closer: func() error {
				gzipErr := gzipReader.Close()
				fileErr := file.Close()
				if gzipErr != nil {
					return gzipErr
				}
				return fileErr
			},
		}, nil
	}

	if openErr == nil {
		openErr = os.ErrNotExist
	}

	return nil, fmt.Errorf("open word index %s: %w", path, openErr)
}

func openEmbeddedWordIndexReader() (io.ReadCloser, error) {
	if len(wordAssets.AllJSONZst) == 0 {
		return nil, fmt.Errorf("embedded word index is empty")
	}

	return openEmbeddedZstReader()
}

// openEmbeddedZstReader decompresses the embedded zstd dataset entirely in
// memory.
func openEmbeddedZstReader() (io.ReadCloser, error) {
	buffer := bytes.NewReader(wordAssets.AllJSONZst)
	zstdReader, err := zstd.NewReader(buffer)
	if err != nil {
		return nil, fmt.Errorf("open embedded zstd word index: %w", err)
	}

	return compositeReadCloser{
		reader: zstdReader,
		closer: func() error {
			zstdReader.Close()
			return nil
		},
	}, nil
}

func isEmbeddedDatasetPath(path string) bool {
	switch strings.ToLower(strings.TrimSpace(path)) {
	case "embedded", EmbeddedDatasetPath:
		return true
	default:
		return false
	}
}

func candidateWordIndexPaths(path string) []string {
	paths := []string{path}
	lowerPath := strings.ToLower(path)
	if strings.HasSuffix(lowerPath, ".json") {
		basePath := path[:len(path)-len(".json")]
		paths = append(paths, basePath+".json.zst", basePath+".json.gz")
	}

	return paths
}
