"""Private atomic publication; the caller must choose replace or no-clobber."""
from contextlib import contextmanager
import os
from pathlib import Path
import tempfile

def private_directory(target):
    """Create a private directory without following a final symlink."""
    target = Path(target)
    if target.is_symlink():
        raise OSError(f"refusing symlinked capture directory: {target}")
    target.mkdir(mode=0o700, parents=True, exist_ok=True)
    target.chmod(0o700)


@contextmanager
def atomic_output(target, *, replace):
    """Yield a seekable binary stream and publish only after successful validation."""
    target = Path(target).expanduser().absolute()
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w+b", dir=target.parent,
                                         prefix="." + target.name + ".", delete=False) as output:
            temporary = output.name
            os.fchmod(output.fileno(), 0o600)
            yield output
            output.flush()
            os.fsync(output.fileno())
        if replace:
            os.replace(temporary, target)
        else:
            os.link(temporary, target)
            os.unlink(temporary)
        temporary = None
    finally:
        if temporary is not None:
            os.unlink(temporary)

def atomic_write(target, data, *, replace):
    """Publish bytes, preserving any previous target when writing fails."""
    with atomic_output(target, replace=replace) as output:
        output.write(data)
