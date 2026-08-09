import time
from pathlib import Path

import pytest

from agent_desktop.cleanup import cleanup
from agent_desktop.errors import AgentDesktopError
from agent_desktop.models import Config, Session, SessionState
from agent_desktop.storage import write_json
from agent_desktop.system import SessionManager


def test_destroy_rejects_tampered_ownership_paths(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    config = Config(
        runtime_root=tmp_path / "run",
        state_root=tmp_path / "state",
        portal_service_dir=tmp_path / "services",
    )
    state = Session(
        id="safe-session",
        agent_id="agent",
        unit="unrelated-user-service.service",
        state=SessionState.READY,
        created_at=time.time(),
        updated_at=time.time(),
        runtime_dir=tmp_path / "valuable-data",
    )
    write_json(config.state_path(state.id), state)
    manager = SessionManager(
        config,
        tmp_path / "config.json",
        session_command="/nix/store/agent-desktop-session",
    )

    with pytest.raises(AgentDesktopError, match="invalid ownership paths"):
        manager.destroy(state.id)


def test_state_record_identity_must_match_its_filename(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    config = Config(
        runtime_root=tmp_path / "run",
        state_root=tmp_path / "state",
        portal_service_dir=tmp_path / "services",
    )
    owner_id = "owner-session"
    owner_runtime = config.runtime_dir(owner_id)
    owner_runtime.mkdir(parents=True)
    (owner_runtime / "keep").write_text("owned")
    state = Session(
        id=owner_id,
        agent_id="agent",
        unit="agent-desktop-owner-session.service",
        state=SessionState.READY,
        created_at=time.time(),
        updated_at=time.time(),
        runtime_dir=owner_runtime,
    )
    write_json(config.state_path("alias-session"), state)
    manager = SessionManager(
        config,
        tmp_path / "config.json",
        session_command="/nix/store/agent-desktop-session",
    )

    with pytest.raises(AgentDesktopError, match="identity does not match"):
        manager.destroy("alias-session")

    assert (owner_runtime / "keep").read_text() == "owned"


def test_status_rejects_tampered_session_endpoints(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    config = Config(
        runtime_root=tmp_path / "run",
        state_root=tmp_path / "state",
        portal_service_dir=tmp_path / "services",
    )
    session_id = "safe-session"
    runtime = config.runtime_dir(session_id)
    state = Session(
        id=session_id,
        agent_id="agent",
        unit="agent-desktop-safe-session.service",
        state=SessionState.READY,
        created_at=time.time(),
        updated_at=time.time(),
        runtime_dir=runtime,
        control_socket=runtime / "control.sock",
        browser_profile=tmp_path / "valuable-browser-profile",
    )
    write_json(config.state_path(session_id), state)
    manager = SessionManager(
        config,
        tmp_path / "config.json",
        session_command="/nix/store/agent-desktop-session",
    )

    with pytest.raises(AgentDesktopError, match="invalid ownership paths"):
        manager.status(session_id)


@pytest.mark.parametrize(
    "endpoint",
    [
        {"wayland_display": "../../host-wayland"},
        {"at_spi_bus_address": "unix:path=/run/user/1000/at-spi/bus"},
    ],
)
def test_status_rejects_tampered_dynamic_endpoints(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    endpoint: dict[str, str],
) -> None:
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    config = Config(
        runtime_root=tmp_path / "run",
        state_root=tmp_path / "state",
        portal_service_dir=tmp_path / "services",
    )
    session_id = "safe-session"
    state = Session(
        id=session_id,
        agent_id="agent",
        unit="agent-desktop-safe-session.service",
        state=SessionState.READY,
        created_at=time.time(),
        updated_at=time.time(),
        runtime_dir=config.runtime_dir(session_id),
    ).model_copy(update=endpoint)
    write_json(config.state_path(session_id), state)
    manager = SessionManager(
        config,
        tmp_path / "config.json",
        session_command="/nix/store/agent-desktop-session",
    )

    with pytest.raises(AgentDesktopError, match="invalid ownership paths"):
        manager.status(session_id)


def test_overlay_cleanup_only_removes_the_derived_session_directory(
    tmp_path: Path,
) -> None:
    config = Config(
        runtime_root=tmp_path / "run",
        state_root=tmp_path / "state",
        browser_overlay_root=tmp_path / "browser-overlays",
        portal_service_dir=tmp_path / "services",
    )
    target = config.browser_overlay_dir("safe-session")
    valuable = tmp_path / "valuable-data"
    target.mkdir(parents=True)
    valuable.mkdir()
    (target / "changes").write_text("ephemeral")
    (valuable / "keep").write_text("important")

    cleanup(config, "safe-session")

    assert not target.exists()
    assert (valuable / "keep").read_text() == "important"
