#!/usr/bin/env python3

from __future__ import annotations

import argparse
import gzip
import json
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path
import tomllib


WORD_PATTERN = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)?")


def extract_words(text: str) -> set[str]:
    return {match.group(0).lower() for match in WORD_PATTERN.finditer(text)}


def load_source_files(config_path: Path, assets_dir: Path) -> list[Path]:
    config = tomllib.loads(config_path.read_text(encoding="utf-8"))
    sources = config.get("sources", [])

    if not isinstance(sources, list) or not sources:
        raise ValueError(f"no sources configured in {config_path}")

    source_files: dict[str, Path] = {}

    for source in sources:
        if not isinstance(source, dict):
            raise ValueError(f"invalid source entry in {config_path}")

        files = source.get("files", [])
        if not isinstance(files, list):
            raise ValueError(f"invalid source files entry in {config_path}")

        for file_name in files:
            if not isinstance(file_name, str):
                raise ValueError(f"invalid source filename in {config_path}")

            relative_path = Path(file_name)
            if relative_path.name == "all.txt":
                continue

            file_path = assets_dir / relative_path
            if not file_path.is_file():
                # Word lists are stored zstd-compressed (see assets/README.md);
                # the config still names the logical .txt so labels stay stable.
                compressed = file_path.with_name(file_path.name + ".zst")
                if not compressed.is_file():
                    raise FileNotFoundError(
                        f"configured source file not found: {file_path} (nor {compressed})"
                    )
                file_path = compressed

            source_files[relative_path.as_posix()] = file_path

    return [source_files[file_name] for file_name in sorted(source_files)]


def read_source_text(path: Path) -> str:
    """Read a word list, transparently decompressing a .zst source.

    Shells out to the zstd binary rather than taking a Python dependency: this
    script already requires zstd on PATH to write assets/all.json.zst.
    """
    if path.suffix != ".zst":
        return path.read_text(encoding="utf-8", errors="ignore")

    zstd_bin = shutil.which("zstd")
    if zstd_bin is None:
        print("zstd command not found in PATH; required to read compressed word lists", file=sys.stderr)
        raise SystemExit(1)

    result = subprocess.run(
        [zstd_bin, "-dc", str(path)], check=True, capture_output=True
    )
    return result.stdout.decode("utf-8", errors="ignore")


def build_index(txt_files: list[Path]) -> list[dict[str, object]]:
    words_to_sources: dict[str, set[str]] = defaultdict(set)

    repo_root = Path(__file__).resolve().parent.parent
    assets_dir = repo_root / "assets"

    for txt_file in txt_files:
        contents = read_source_text(txt_file)
        # Strip the .zst so the emitted source label matches the logical .txt
        # name — the generated index and its consumers must not shift.
        source_name = txt_file.relative_to(assets_dir).as_posix().removesuffix(".zst")
        for word in extract_words(contents):
            words_to_sources[word].add(source_name)

    return [
        {
            "word": word,
            "sources": sorted(words_to_sources[word]),
        }
        for word in sorted(words_to_sources)
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build compressed word index artifacts from configured source dictionaries."
    )
    parser.add_argument(
        "--include-json",
        action="store_true",
        help="also write assets/all.json",
    )
    parser.add_argument(
        "--include-gzip",
        action="store_true",
        help="also write assets/all.json.gz",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    assets_dir = repo_root / "assets"
    config_path = repo_root / "configs" / "wordgen.toml"
    output_path = assets_dir / "all.json"
    output_gzip_path = assets_dir / "all.json.gz"
    output_zstd_path = assets_dir / "all.json.zst"

    if not assets_dir.is_dir():
        print(f"assets directory not found: {assets_dir}", file=sys.stderr)
        return 1

    if not config_path.is_file():
        print(f"config file not found: {config_path}", file=sys.stderr)
        return 1

    try:
        txt_files = load_source_files(config_path, assets_dir)
        index = build_index(txt_files)
    except (FileNotFoundError, ValueError, tomllib.TOMLDecodeError) as err:
        print(err, file=sys.stderr)
        return 1

    payload = json.dumps(index, separators=(",", ":"))
    payload_bytes = (payload + "\n").encode("utf-8")

    if args.include_json:
        output_path.write_bytes(payload_bytes)
    elif output_path.exists():
        output_path.unlink()

    if args.include_gzip:
        with gzip.open(output_gzip_path, "wt", encoding="utf-8", compresslevel=6) as gzip_writer:
            gzip_writer.write(payload)
            gzip_writer.write("\n")
    elif output_gzip_path.exists():
        output_gzip_path.unlink()

    zstd_path = shutil.which("zstd")
    if zstd_path is None:
        print("zstd command not found in PATH; required to build assets/all.json.zst", file=sys.stderr)
        return 1

    subprocess.run(
        [zstd_path, "-q", "-f", "-10", "-o", str(output_zstd_path), "-"],
        input=payload_bytes,
        check=True,
    )

    outputs = [str(output_zstd_path)]
    if args.include_json:
        outputs.append(str(output_path))
    if args.include_gzip:
        outputs.append(str(output_gzip_path))

    print(f"wrote {len(index)} unique words from {len(txt_files)} files to {', '.join(outputs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
