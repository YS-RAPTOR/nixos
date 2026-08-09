from __future__ import annotations

import json
import os
import socket
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import Literal

from pydantic import Field, field_validator, model_validator

from .errors import AgentDesktopError
from .models import LaunchResult, StrictModel

_CONTROL_MAX_BYTES = 64 * 1024
_MAX_ARGUMENT_BYTES = 32 * 1024
_MAX_ARGUMENTS = 256


class LaunchRequest(StrictModel):
    version: int = Field(strict=True)
    operation: Literal["launch"]
    arguments: tuple[str, ...]

    @field_validator("version")
    @classmethod
    def supported_version(cls, version: int) -> int:
        if version != 1:
            raise ValueError("unsupported control protocol version")
        return version

    @field_validator("arguments")
    @classmethod
    def valid_arguments(cls, arguments: tuple[str, ...]) -> tuple[str, ...]:
        if not 1 <= len(arguments) <= _MAX_ARGUMENTS:
            raise ValueError(f"arguments must contain 1-{_MAX_ARGUMENTS} strings")
        if any(not argument or "\x00" in argument for argument in arguments):
            raise ValueError("arguments must contain non-empty strings without NULs")
        return arguments

    @model_validator(mode="after")
    def bounded_arguments(self) -> LaunchRequest:
        if (
            sum(len(argument.encode()) for argument in self.arguments)
            > _MAX_ARGUMENT_BYTES
        ):
            raise ValueError("arguments are too large")
        return self

    @classmethod
    def from_arguments(cls, arguments: Sequence[str]) -> LaunchRequest:
        try:
            return cls(
                version=1,
                operation="launch",
                arguments=tuple(arguments),
            )
        except ValueError as error:
            raise AgentDesktopError(str(error), "invalid_command") from error


class LaunchSuccess(StrictModel):
    ok: bool = Field(strict=True)
    pid: int = Field(gt=0, strict=True)
    arguments: tuple[str, ...]

    @field_validator("ok")
    @classmethod
    def successful(cls, ok: bool) -> bool:
        if not ok:
            raise ValueError("expected a successful control response")
        return ok


class LaunchFailure(StrictModel):
    ok: bool = Field(strict=True)
    code: Literal["launch_failed"]
    message: str

    @field_validator("ok")
    @classmethod
    def failed(cls, ok: bool) -> bool:
        if ok:
            raise ValueError("expected a failed control response")
        return ok


class ControlClient:
    """Client for the private exact-argv launch protocol."""

    @staticmethod
    def launch(path: Path, request: LaunchRequest) -> LaunchResult:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                connection.settimeout(5)
                connection.connect(str(path))
                connection.sendall(request.model_dump_json().encode() + b"\n")
                line = _read_line(connection, "response")
        except OSError as error:
            raise AgentDesktopError(
                f"could not launch application: {error}", "control_failed"
            ) from error
        except ValueError as error:
            raise AgentDesktopError(str(error), "control_failed") from error

        try:
            document = json.loads(line)
            if isinstance(document, dict) and document.get("ok") is False:
                failure = LaunchFailure.model_validate(document)
                raise AgentDesktopError(failure.message, "launch_failed")
            success = LaunchSuccess.model_validate(document)
        except AgentDesktopError:
            raise
        except (UnicodeError, ValueError) as error:
            raise AgentDesktopError(
                f"invalid application control response: {error}", "control_failed"
            ) from error
        if success.arguments != request.arguments:
            raise AgentDesktopError(
                "application control response changed the command", "control_failed"
            )
        return LaunchResult(pid=success.pid, arguments=success.arguments)


class ControlServer:
    """Private, newline-delimited exact-argv launch protocol."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.listener: socket.socket | None = None

    @property
    def active(self) -> bool:
        return self.listener is not None

    def start(self) -> None:
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            listener.bind(str(self.path))
            os.chmod(self.path, 0o600)
            listener.listen(8)
            listener.setblocking(False)
        except OSError:
            listener.close()
            raise
        self.listener = listener

    def stop(self) -> None:
        if self.listener is not None:
            self.listener.close()
            self.listener = None
        self.path.unlink(missing_ok=True)

    def accept(self, launch: Callable[[list[str]], int]) -> None:
        if self.listener is None:
            return
        while True:
            try:
                connection, _ = self.listener.accept()
            except BlockingIOError:
                return
            except OSError as error:
                if self.listener is None:
                    return
                raise AgentDesktopError(
                    f"control socket failed: {error}", "control_failed"
                ) from error
            with connection:
                connection.settimeout(2)
                self._handle(connection, launch)

    @staticmethod
    def _handle(
        connection: socket.socket,
        launch: Callable[[list[str]], int],
    ) -> None:
        try:
            request = LaunchRequest.model_validate_json(
                _read_line(connection, "request")
            )
            response: StrictModel = LaunchSuccess(
                ok=True,
                pid=launch(list(request.arguments)),
                arguments=request.arguments,
            )
        except (OSError, ValueError, TypeError) as error:
            response = LaunchFailure(
                ok=False,
                code="launch_failed",
                message=str(error),
            )
        try:
            connection.sendall(response.model_dump_json().encode() + b"\n")
        except OSError:
            pass


def _read_line(connection: socket.socket, kind: str) -> bytes:
    payload = bytearray()
    while b"\n" not in payload:
        chunk = connection.recv(4096)
        if not chunk:
            raise ValueError(f"control {kind} ended before a newline")
        payload.extend(chunk)
        if len(payload) > _CONTROL_MAX_BYTES:
            raise ValueError(f"control {kind} is too large")
    line, remainder = bytes(payload).split(b"\n", 1)
    if remainder:
        raise ValueError(f"control {kind} contains trailing data")
    return line
