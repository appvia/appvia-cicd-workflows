"""Shared helpers for the tag check tests."""
import json
import sys
from pathlib import Path

ACTION_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[4]

sys.path.insert(0, str(ACTION_DIR))


def change(address, rtype, after=None, after_unknown=None, actions=("create",), mode="managed"):
    """A resource_changes entry as printed by terraform show -json."""
    return {
        "address": address,
        "mode": mode,
        "type": rtype,
        "change": {
            "actions": list(actions),
            "after": {} if after is None else after,
            "after_unknown": {} if after_unknown is None else after_unknown,
        },
    }


def plan(*changes):
    return {"format_version": "1.2", "resource_changes": list(changes)}


def write_json(path, data):
    Path(path).write_text(json.dumps(data), encoding="utf-8")
