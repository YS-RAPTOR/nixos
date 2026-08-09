#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


def load(path: str) -> Any:
    text = Path(path).read_text()
    for index, character in enumerate(text):
        if character not in "[{":
            continue
        try:
            return json.loads(text[index:])
        except json.JSONDecodeError:
            pass
    raise SystemExit(f"no JSON document in {path}")


operation, path, *arguments = sys.argv[1:]
value = load(path)
if operation == "window":
    needle = arguments[0]
    matches = [row for row in value["windows"] if needle in row.get("title", "")]
    if len(matches) != 1:
        raise SystemExit(f"expected one window containing {needle!r}, found {len(matches)}")
    print(json.dumps(matches[0], sort_keys=True))
elif operation == "element":
    label = arguments[0]
    matches = [row for row in value["elements"] if row.get("label") == label]
    if not matches:
        raise SystemExit(f"no element labelled {label!r}")
    print(json.dumps(matches[-1], sort_keys=True))
else:
    raise SystemExit(f"unknown operation: {operation}")
