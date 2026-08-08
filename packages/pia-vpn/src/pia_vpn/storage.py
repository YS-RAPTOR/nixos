from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any, TypeVar

from pydantic import BaseModel

from .errors import PiaVpnError

M = TypeVar("M", bound=BaseModel)


def read_model(path: Path, model: type[M], default: M | None = None) -> M:
    try:
        data = path.read_bytes()
    except FileNotFoundError:
        if default is not None:
            return default
        raise PiaVpnError(
            f"required state is unavailable: {path}", "state_unavailable"
        ) from None
    except OSError as error:
        raise PiaVpnError(
            f"cannot read state {path}: {error}", "state_error"
        ) from error
    if len(data) > 8 * 1024 * 1024:
        raise PiaVpnError(f"state file is too large: {path}", "state_error")
    try:
        return model.model_validate_json(data)
    except ValueError as error:
        raise PiaVpnError(f"invalid state {path}: {error}", "state_error") from error


def write_json(path: Path, value: BaseModel | dict[str, Any] | list[Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
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
