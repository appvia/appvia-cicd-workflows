#!/usr/bin/env python3
"""Checks terraform plan JSON files against the tagging policy.

Run by check.sh with:
  PLAN_JSON   - a plan JSON file, or a directory searched recursively for *.json files
  POLICY_FILE - the tagging policy (YAML)
and, when set by the runner, GITHUB_OUTPUT (receives violations=<count>) and
GITHUB_STEP_SUMMARY (receives a markdown report).

Exit codes: 0 compliant, 1 policy violations, 2 usage error
"""
import os
import sys
import traceback
from pathlib import Path

import engine
import report
from plan import PlanError, load_plan, resources
from policy import PolicyError, load_policy

EXIT_OK = 0
EXIT_VIOLATIONS = 1
EXIT_USAGE = 2


def usage_error(message):
    print(f"::error title=Tag Policy::{message}")
    return EXIT_USAGE


def plan_files(location):
    path = Path(location)
    if path.is_dir():
        return sorted(str(found) for found in path.rglob("*.json") if found.is_file())
    if path.is_file():
        return [str(path)]
    return None


def check_file(policy, file):
    terraform_plan = load_plan(file)
    violations, unverified = [], []
    try:
        for resource in resources(terraform_plan, policy.exclude_resource_types):
            found, unchecked = engine.check_resource(policy, resource)
            violations += found
            unverified += unchecked
    except (AttributeError, TypeError) as err:
        raise PlanError(f"failed to evaluate {file}, is it a terraform plan? {err}") from err
    return report.FileResult(file, violations, unverified)


def main(env=os.environ):
    plan_json = env.get("PLAN_JSON", "")
    policy_file = env.get("POLICY_FILE", "")
    if not plan_json:
        return usage_error("PLAN_JSON must be set")
    if not policy_file:
        return usage_error("POLICY_FILE must be set")
    try:
        policy = load_policy(policy_file)
    except PolicyError as err:
        return usage_error(f"invalid policy file {policy_file}: {err}")
    files = plan_files(plan_json)
    if files is None:
        return usage_error(f"plan json not found: {plan_json}")
    if not files:
        print(f"::warning title=Tag Policy::no plan json files found in {plan_json}")

    try:
        results = [check_file(policy, file) for file in files]
    except PlanError as err:
        return usage_error(str(err))

    failing = len(report.failing_resources(results))
    for line in report.annotations(results):
        print(line)
    if env.get("GITHUB_STEP_SUMMARY"):
        with open(env["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as handle:
            handle.write(report.summary(results, policy))
    if env.get("GITHUB_OUTPUT"):
        with open(env["GITHUB_OUTPUT"], "a", encoding="utf-8") as handle:
            handle.write(f"violations={failing}\n")

    if failing:
        print(f"Found {failing} resource(s) violating the tagging policy")
        return EXIT_VIOLATIONS
    print(report.passed_message(policy))
    return EXIT_OK


def run():
    try:
        return main()
    except Exception as err:  # exit 1 means policy violations, so never let a crash look like one
        traceback.print_exc()
        return usage_error(f"unexpected error: {err}")


if __name__ == "__main__":
    sys.exit(run())
