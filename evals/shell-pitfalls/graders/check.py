import json
import subprocess
import tempfile
from pathlib import Path

checks = []
with tempfile.TemporaryDirectory(prefix="shell-pitfalls-") as tmp:
    root = Path(tmp)
    src, dest = root / "source dir", root / "destination dir"
    src.mkdir()
    dest.mkdir()
    files = {"ordinary.txt": "one\n", "space name.txt": "two\n", "bracket[1].txt": "three\n", "dollar$sign.txt": "four\n"}
    for name, content in files.items():
        (src / name).write_text(content)
    nested = src / "nested.txt"
    nested.mkdir()
    (nested / "inside.txt").write_text("nested\n")
    outside = root / "outside.txt"
    outside.write_text("outside\n")
    (src / "link.txt").symlink_to(outside)
    (src / "leave.md").write_text("leave source\n")
    (dest / "untouched.txt").write_text("leave destination\n")
    script = Path.cwd() / "copy-text.zsh"
    result = subprocess.run(["zsh", "-f", str(script), str(src), str(dest)], capture_output=True, timeout=10)
    checks.append(("exit-success", result.returncode == 0))
    checks.append(("copy-text-files", all((dest / n).is_file() and (dest / n).read_text() == c for n, c in files.items())))
    checks.append(("preserve-source-files", all((src / n).is_file() and (src / n).read_text() == c for n, c in files.items())))
    checks.append(("top-level-only", (nested / "inside.txt").is_file() and not (dest / "nested.txt").exists() and not (dest / "inside.txt").exists()))
    checks.append(("skip-symlinks", not (dest / "link.txt").exists() and not (dest / "link.txt").is_symlink() and outside.read_text() == "outside\n"))
    checks.append(("preserve-unrelated", (src / "leave.md").read_text() == "leave source\n" and (dest / "untouched.txt").read_text() == "leave destination\n" and not (dest / "leave.md").exists()))
    empty = root / "empty source"
    empty.mkdir()
    result = subprocess.run(["zsh", "-f", str(script), str(empty), str(dest)], capture_output=True, timeout=10)
    checks.append(("empty-source", result.returncode == 0 and (dest / "untouched.txt").read_text() == "leave destination\n"))
passed = all(ok for _, ok in checks)
print(json.dumps({"score": int(passed), "details": ", ".join(f"{name}: {'pass' if ok else 'fail'}" for name, ok in checks)}))
