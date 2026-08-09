#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
rows: list[dict[str, object]] = []
for path in sorted(root.rglob("*"), key=lambda item: os.fsencode(str(item.relative_to(root)))):
    relative = str(path.relative_to(root))
    metadata = path.lstat()
    mode = stat.S_IMODE(metadata.st_mode)
    if path.is_symlink():
        rows.append({"mode": mode, "path": relative, "target": os.readlink(path), "type": "symlink"})
    elif path.is_file():
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        rows.append(
            {
                "mode": mode,
                "path": relative,
                "sha256": digest.hexdigest(),
                "size": metadata.st_size,
                "type": "file",
            }
        )
    elif path.is_dir():
        rows.append({"mode": mode, "path": relative, "type": "directory"})
    else:
        rows.append({"mode": mode, "path": relative, "type": "other"})

json.dump(rows, sys.stdout, separators=(",", ":"), sort_keys=True)
sys.stdout.write("\n")
