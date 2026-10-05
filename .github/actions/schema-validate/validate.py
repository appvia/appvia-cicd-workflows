#!/usr/bin/env python3
"""Validates YAML or JSON files against a JSON Schema (Draft 2020-12).

Required environment variables:
  SCHEMA_FILE - the JSON Schema file
  FILES       - newline-separated file paths or globs, relative to the working directory
Optional environment variables (set by the runner):
  GITHUB_OUTPUT       - receives errors=<count>
  GITHUB_STEP_SUMMARY - receives a markdown report

Exit codes: 0 all valid, 1 schema violations, 2 usage error
"""
from __future__ import annotations

import glob
import json
import os
import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator
from jsonschema.exceptions import SchemaError
from referencing.exceptions import Unresolvable


class UsageError(Exception):
    pass


def escape_data(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def escape_property(value: str) -> str:
    return escape_data(value).replace(":", "%3A").replace(",", "%2C")


def load_schema(path: str) -> dict:
    schema_file = Path(path)
    if not schema_file.is_file():
        raise UsageError(f"schema file not found: {path}")
    try:
        schema = json.loads(schema_file.read_text())
    except json.JSONDecodeError as error:
        raise UsageError(f"schema file is not valid JSON: {path}: {error}") from error
    try:
        Draft202012Validator.check_schema(schema)
    except SchemaError as error:
        raise UsageError(f"invalid schema: {path}: {error.message}") from error
    return schema


def expand(patterns: str) -> list[str]:
    files: list[str] = []
    for pattern in (line.strip() for line in patterns.splitlines()):
        if not pattern:
            continue
        matched = [m for m in sorted(glob.glob(pattern, recursive=True)) if os.path.isfile(m)]
        if not matched:
            raise UsageError(f"no files match: {pattern}")
        files += [m for m in matched if m not in files]
    if not files:
        raise UsageError("FILES must list at least one path or glob")
    return files


def load_document(path: str):
    try:
        text = Path(path).read_text()
        if path.endswith(".json"):
            return json.loads(text)
        document = yaml.safe_load(text)
    except (OSError, ValueError, yaml.YAMLError) as error:
        raise UsageError(f"{path}: cannot parse: {' '.join(str(error).split())}") from error
    return {} if document is None else document


def violations(validator: Draft202012Validator, document, path: str) -> list[tuple[str, str, str]]:
    try:
        errors = sorted(validator.iter_errors(document), key=lambda e: [str(p) for p in e.absolute_path])
    except Unresolvable as error:
        raise UsageError(f"{path}: cannot resolve a schema reference: {error}") from error
    return [(path, "/".join(str(p) for p in e.absolute_path) or "<root>", e.message) for e in errors]


def annotation_path(path: str) -> str:
    """GitHub resolves annotation paths against the repository root, not the working directory."""
    workspace = os.environ.get("GITHUB_WORKSPACE") or "."
    return os.path.relpath(os.path.abspath(path), os.path.abspath(workspace))


def append(env_var: str, text: str) -> None:
    target = os.environ.get(env_var)
    if target:
        with open(target, "a") as handle:
            handle.write(text)


def report(files: list[str], found: list[tuple[str, str, str]]) -> None:
    if not found:
        append("GITHUB_STEP_SUMMARY", f"### Schema Validation\n\nAll {len(files)} file(s) are valid\n")
        return
    rows = "".join(
        f"| {path} | {key} | {message.replace('|', chr(92) + '|').replace(chr(10), ' ')} |\n"
        for path, key, message in found
    )
    append(
        "GITHUB_STEP_SUMMARY",
        f"### Schema Validation\n\n{len(found)} violation(s) in {len(files)} file(s)\n\n"
        f"| File | Path | Violation |\n| ---- | ---- | --------- |\n{rows}",
    )


def main() -> int:
    try:
        schema_file = os.environ.get("SCHEMA_FILE", "")
        if not schema_file:
            raise UsageError("SCHEMA_FILE must be set")
        validator = Draft202012Validator(load_schema(schema_file))
        files = expand(os.environ.get("FILES", ""))
        found: list[tuple[str, str, str]] = []
        for path in files:
            found += violations(validator, load_document(path), path)
    except UsageError as error:
        print(f"::error title=Schema Validate::{escape_data(str(error))}")
        print(f"error: {error}")
        return 2

    for path, key, message in found:
        print(f"::error file={escape_property(annotation_path(path))},title=Schema Validate::{escape_data(f'{key}: {message}')}")
        print(f"{path}: {key}: {message}")
    report(files, found)
    append("GITHUB_OUTPUT", f"errors={len(found)}\n")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
