#!/usr/bin/env python3
"""Render a deterministic snapshot of the jobs and steps in a GitHub workflow.

The snapshot is the diff target for refactoring work: extracting inline shell
into composite actions should change the `uses:` of a step but not the ordered
set of step names, ids, conditions or error handling. Any other movement shows
up as a baseline diff and has to be acknowledged deliberately.

Usage:
    python scripts/render-workflow-steps.py --output-dir tests/azure/baseline \\
        .github/workflows/terraform-plan-and-apply-azure.yml
"""

from __future__ import annotations

import argparse
import pathlib
import sys

import yaml

PLACEHOLDER = "-"


def _fmt(value: object) -> str:
    """Collapse a scalar to a single line so the snapshot stays greppable."""
    if value is None:
        return PLACEHOLDER
    if isinstance(value, bool):
        return "true" if value else "false"
    text = " ".join(str(value).split())
    return text if text else PLACEHOLDER


def _matrix_keys(job: dict) -> str:
    matrix = job.get("strategy", {}).get("matrix")
    if not isinstance(matrix, dict):
        return _fmt(matrix)
    return ", ".join(matrix.keys()) or PLACEHOLDER


def _needs(job: dict) -> str:
    needs = job.get("needs")
    if isinstance(needs, list):
        return ", ".join(str(n) for n in needs)
    return _fmt(needs)


def _render_step(index: int, step: dict) -> list[str]:
    label = step.get("name") or step.get("uses") or step.get("run", "").splitlines()[:1]
    if isinstance(label, list):
        label = label[0] if label else "(anonymous run step)"
    return [
        f"  {index:>3}. {_fmt(label)}",
        f"       id:                {_fmt(step.get('id'))}",
        f"       uses:              {_fmt(step.get('uses'))}",
        f"       if:                {_fmt(step.get('if'))}",
        f"       continue-on-error: {_fmt(step.get('continue-on-error'))}",
    ]


def _render_job(job_id: str, job: dict) -> list[str]:
    lines = [
        "",
        f"job: {job_id}",
        f"  name:        {_fmt(job.get('name'))}",
        f"  if:          {_fmt(job.get('if'))}",
        f"  needs:       {_needs(job)}",
        f"  environment: {_fmt(job.get('environment'))}",
        f"  matrix:      {_matrix_keys(job)}",
        f"  outputs:     {', '.join(job.get('outputs', {})) or PLACEHOLDER}",
        "  steps:",
    ]
    steps = job.get("steps")
    if not steps:
        # A job that only calls a reusable workflow has no steps of its own.
        lines.append(f"    (no steps; uses: {_fmt(job.get('uses'))})")
        return lines
    for index, step in enumerate(steps, start=1):
        lines.extend(_render_step(index, step))
    return lines


def render(path: pathlib.Path) -> str:
    workflow = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(workflow, dict):
        raise ValueError(f"{path} did not parse to a mapping")

    posix_path = path.as_posix()
    lines = [
        f"workflow: {_fmt(workflow.get('name'))}",
        f"file:     {posix_path}",
    ]
    for job_id, job in (workflow.get("jobs") or {}).items():
        lines.extend(_render_job(job_id, job))
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workflows", nargs="+", type=pathlib.Path)
    parser.add_argument("--output-dir", type=pathlib.Path, required=True)
    args = parser.parse_args(argv)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for workflow in args.workflows:
        destination = args.output_dir / f"{workflow.stem}.txt"
        destination.write_text(render(workflow), encoding="utf-8", newline="\n")
        print(f"wrote {destination.as_posix()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
