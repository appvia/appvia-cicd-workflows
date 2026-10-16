"""Loads and validates the tagging policy (config/tagging-policy.yaml)."""
import re
from dataclasses import dataclass

import yaml

VERSION = 1
FILTER = "filter"
ASSERT = "assert"
TARGETS = ("type", "address", "tag")
CASE_OPERATORS = ("is_pascal", "is_camel", "is_snake", "is_kebab", "is_lower", "is_upper")
OPERATORS = ("present", "equals", "in", "contains", "starts_with", "ends_with", "matches") + CASE_OPERATORS
BOOLEAN_OPERATORS = ("present",) + CASE_OPERATORS
SEVERITIES = ("error", "warning")


class PolicyError(Exception):
    """The policy file is unreadable or invalid."""


@dataclass(frozen=True)
class Condition:
    target: str  # type, address or tag
    keys: tuple  # the tag keys for a tag target, otherwise empty
    operator: str
    operand: object  # a bool for present, otherwise a tuple of strings (any-of)
    negate: bool = False


@dataclass(frozen=True)
class Step:
    kind: str  # filter or assert
    condition: Condition


@dataclass(frozen=True)
class Rule:
    name: str  # the full path, parent/child for nested rules
    description: str
    severity: str
    steps: tuple
    children: tuple


@dataclass(frozen=True)
class Policy:
    exclude_resource_types: frozenset
    rules: tuple


def load_policy(path):
    try:
        with open(path, encoding="utf-8") as handle:
            data = yaml.safe_load(handle)
    except (OSError, ValueError, yaml.YAMLError) as err:
        raise PolicyError(f"cannot read policy {path}: {err}") from err
    return parse_policy(data)


def parse_policy(data):
    if not isinstance(data, dict):
        raise PolicyError("policy must be a mapping")
    _only_keys(data, {"version", "exclude_resource_types", "rules"}, "policy")
    version = data.get("version")
    if type(version) is not int or version != VERSION:
        raise PolicyError(f"unsupported policy version {version!r}, expected {VERSION}")
    excluded = data.get("exclude_resource_types") or []
    if not isinstance(excluded, list) or not all(isinstance(item, str) for item in excluded):
        raise PolicyError("exclude_resource_types must be a list of strings")
    raw_rules = data.get("rules")
    if not isinstance(raw_rules, list):
        raise PolicyError("rules must be a list")
    seen = set()
    rules = tuple(_parse_rule(raw, "", seen) for raw in raw_rules)
    return Policy(frozenset(excluded), rules)


def _parse_rule(raw, parent, seen):
    if not isinstance(raw, dict):
        raise PolicyError(f"a rule under {parent or 'the policy'} must be a mapping")
    name = raw.get("name")
    if not isinstance(name, str) or not name or "/" in name:
        raise PolicyError(
            f"a rule under {parent or 'the policy'} needs a name that is a non-empty string without '/'"
        )
    path = f"{parent}/{name}" if parent else name
    where = f"rule {path}"
    if path in seen:
        raise PolicyError(f"{where}: duplicate rule name")
    seen.add(path)
    _only_keys(raw, {"name", "description", "severity", "steps", "rules"}, where)
    severity = raw.get("severity", "error")
    if severity not in SEVERITIES:
        raise PolicyError(f"{where}: severity must be one of {', '.join(SEVERITIES)}")
    description = raw.get("description", "")
    if not isinstance(description, str):
        raise PolicyError(f"{where}: description must be a string")
    raw_steps = raw.get("steps")
    if not isinstance(raw_steps, list) or not raw_steps:
        raise PolicyError(f"{where}: steps must be a non-empty list")
    steps = tuple(_parse_step(step, f"{where} step {i}") for i, step in enumerate(raw_steps, 1))
    raw_children = raw.get("rules", [])
    if not isinstance(raw_children, list):
        raise PolicyError(f"{where}: rules must be a list")
    children = tuple(_parse_rule(child, path, seen) for child in raw_children)
    return Rule(path, description, severity, steps, children)


def _parse_step(raw, where):
    if not isinstance(raw, dict):
        raise PolicyError(f"{where} must be a mapping")
    kinds = [kind for kind in (FILTER, ASSERT) if kind in raw]
    if len(raw) != 1 or len(kinds) != 1:
        raise PolicyError(f"{where} must have exactly one of 'filter' or 'assert'")
    return Step(kinds[0], _parse_condition(raw[kinds[0]], f"{where} {kinds[0]}"))


def _parse_condition(raw, where):
    if not isinstance(raw, dict):
        raise PolicyError(f"{where} must be a mapping")
    _only_keys(raw, set(TARGETS) | set(OPERATORS) | {"not"}, where)
    negate = raw.get("not", False)
    if not isinstance(negate, bool):
        raise PolicyError(f"{where}: 'not' must be true or false")
    targets = [target for target in TARGETS if target in raw]
    if len(targets) != 1:
        raise PolicyError(f"{where} must name exactly one of {', '.join(TARGETS)}")
    target = targets[0]
    operators = [operator for operator in OPERATORS if operator in raw]
    if target == "tag":
        if len(operators) != 1:
            raise PolicyError(f"{where} must have exactly one operator ({', '.join(OPERATORS)})")
        keys = _strings(raw["tag"], f"{where}: tag")
        operator = operators[0]
        return Condition("tag", keys, operator, _operand(operator, raw[operator], where), negate)
    if operators:
        raise PolicyError(
            f"{where}: write {target} as '{target}: value' or '{target}: {{operator: value}}'"
        )
    value = raw[target]
    if isinstance(value, dict):
        if len(value) != 1:
            raise PolicyError(f"{where}: {target} takes exactly one operator")
        ((operator, operand),) = value.items()
        if operator not in OPERATORS or operator == "present":
            allowed = ", ".join(op for op in OPERATORS if op != "present")
            raise PolicyError(f"{where}: {target} operator must be one of {allowed}")
        return Condition(target, (), operator, _operand(operator, operand, where), negate)
    return Condition(target, (), "equals", _strings(value, f"{where}: {target}"), negate)


def _operand(operator, value, where):
    if operator in BOOLEAN_OPERATORS:
        if not isinstance(value, bool):
            raise PolicyError(f"{where}: {operator} must be true or false")
        return value
    operands = _strings(value, f"{where}: {operator}")
    if operator == "matches":
        for pattern in operands:
            try:
                re.compile(pattern)
            except re.error as err:
                raise PolicyError(f"{where}: invalid regular expression {pattern!r}: {err}") from err
    return operands


def _strings(value, where):
    items = [value] if isinstance(value, str) else value
    if not isinstance(items, list) or not items:
        raise PolicyError(f"{where} must be a string or a non-empty list of strings")
    if not all(isinstance(item, str) and item for item in items):
        raise PolicyError(
            f"{where} must be a string or a list of strings (quote values such as yes or 1)"
        )
    return tuple(items)


def _only_keys(mapping, allowed, where):
    unknown = sorted(str(key) for key in mapping if key not in allowed)
    if unknown:
        raise PolicyError(f"{where}: unknown field(s) {', '.join(unknown)}")
