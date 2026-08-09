#!/usr/bin/env bash
set -u

value=$("$AGENT_DESKTOP_E2E_ZENITY" \
  --entry \
  --title="$E2E_FIXTURE_TITLE" \
  --text='Behaviour value' \
  --ok-label='Record exact value' \
  --cancel-label='Cancel' \
  --width=760 \
  --height=420)
status=$?

python3 - "$E2E_FIXTURE_OUT" "$E2E_FIXTURE_TITLE" "$value" "$status" <<'PY'
import json
import sys
from pathlib import Path

path, title, value, status = sys.argv[1:]
Path(path).write_text(
    json.dumps(
        {"source": "zenity", "status": int(status), "title": title, "value": value},
        sort_keys=True,
    )
    + "\n"
)
PY
