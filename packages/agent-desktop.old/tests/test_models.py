from pathlib import Path

import pytest
from pydantic import ValidationError

from agent_desktop.models import Config, Session, SessionState


def config(tmp_path: Path) -> Config:
    return Config(
        runtime_root=tmp_path / "run",
        state_root=tmp_path / "state",
        portal_service_dir=tmp_path / "services",
    )


@pytest.mark.parametrize(
    ("runtime_root", "state_root"),
    [
        ("shared", "shared"),
        ("shared", "shared/state"),
        ("shared/runtime", "shared"),
    ],
)
def test_config_requires_disjoint_runtime_and_state_roots(
    tmp_path: Path, runtime_root: str, state_root: str
) -> None:
    with pytest.raises(ValidationError, match="must be separate trees"):
        Config(
            runtime_root=tmp_path / runtime_root,
            state_root=tmp_path / state_root,
            portal_service_dir=tmp_path / "services",
        )


def test_session_rejects_unsafe_ids(tmp_path: Path) -> None:
    with pytest.raises(ValidationError):
        Session(
            id="../../primary",
            agent_id="agent",
            unit="agent-desktop-invalid.service",
            state=SessionState.STARTING,
            created_at=1,
            updated_at=1,
            runtime_dir=tmp_path,
        )
