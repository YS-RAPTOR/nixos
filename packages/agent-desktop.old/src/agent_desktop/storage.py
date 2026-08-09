from __future__ import annotations

import fcntl
import json
import os
import tempfile
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any, TypeVar

from pydantic import BaseModel

from .errors import AgentDesktopError

M = TypeVar("M", bound=BaseModel)


def read_model(path: Path, model: type[M]) -> M:
    try:
        data = path.read_bytes()
    except FileNotFoundError:
        raise AgentDesktopError(
            f"session state is unavailable: {path.stem}", "session_not_found"
        ) from None
    except OSError as error:
        raise AgentDesktopError(
            f"cannot read state {path}: {error}", "state_error"
        ) from error
    if len(data) > 1024 * 1024:
        raise AgentDesktopError(f"state file is too large: {path}", "state_error")
    try:
        return model.model_validate_json(data)
    except ValueError as error:
        raise AgentDesktopError(
            f"invalid state {path}: {error}", "state_error"
        ) from error


def write_json(path: Path, value: BaseModel | dict[str, Any] | list[Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    payload = value.model_dump(mode="json") if isinstance(value, BaseModel) else value
    data = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode() + b"\n"
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


@contextmanager
def state_lock(state_root: Path) -> Iterator[None]:
    state_root.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(state_root, 0o700)
    descriptor = os.open(state_root / ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)
