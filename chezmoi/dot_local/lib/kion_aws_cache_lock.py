import contextlib
import fcntl
import os
import pathlib
import stat


class CacheLockError(Exception):
    pass


class CacheLockBusyError(CacheLockError):
    pass


def cache_lock_path(cache_dir: pathlib.Path) -> pathlib.Path:
    return cache_dir.parent / f".{cache_dir.name}.lock"


@contextlib.contextmanager
def cache_lock(cache_dir: pathlib.Path):
    lock_path = cache_lock_path(cache_dir)
    flags = (
        os.O_RDWR
        | os.O_CREAT
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    descriptor: int | None = None
    try:
        descriptor = os.open(lock_path, flags, 0o600)
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise CacheLockError("credential cache lock is not a regular file")
        os.fchmod(descriptor, 0o600)
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        if descriptor is not None:
            os.close(descriptor)
        raise CacheLockBusyError("credential cache lock is already held") from error
    except OSError as error:
        if descriptor is not None:
            os.close(descriptor)
        raise CacheLockError("credential cache lock could not be acquired") from error
    except CacheLockError:
        if descriptor is not None:
            os.close(descriptor)
        raise

    try:
        yield
    finally:
        os.close(descriptor)
