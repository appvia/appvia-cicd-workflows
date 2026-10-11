"""Evaluates tagging policy rules against planned resources."""
import re
from dataclasses import dataclass

from policy import ASSERT, FILTER

PASS = "pass"
FAIL = "fail"
UNKNOWN = "unknown"

_UNKNOWN_VALUE = object()


@dataclass(frozen=True)
class Violation:
    rule: str
    severity: str
    address: str
    message: str


@dataclass(frozen=True)
class Unverified:
    rule: str  # empty when the whole resource was skipped
    address: str
    message: str


def _equals(value, operands):
    return value in operands


def _contains(value, operands):
    return isinstance(value, str) and any(operand in value for operand in operands)


def _starts_with(value, operands):
    return isinstance(value, str) and value.startswith(operands)


def _ends_with(value, operands):
    return isinstance(value, str) and value.endswith(operands)


def _matches(value, operands):
    return isinstance(value, str) and any(re.search(operand, value) for operand in operands)


# Whole-value patterns for the is_<case> operators
_CASES = {
    "is_pascal": r"(?:[A-Z][a-z0-9]+)+",
    "is_camel": r"[a-z][a-z0-9]*(?:[A-Z][a-z0-9]+)*",
    "is_snake": r"[a-z][a-z0-9]*(?:_[a-z0-9]+)*",
    "is_kebab": r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*",
    "is_lower": r"[a-z0-9]+",
    "is_upper": r"[A-Z0-9]+",
}


def _case_check(pattern):
    compiled = re.compile(pattern)

    def check(value, operand):
        return (isinstance(value, str) and compiled.fullmatch(value) is not None) == operand

    return check


# Operand lists are any-of for every comparison
COMPARISONS = {
    "equals": _equals,
    "in": _equals,
    "contains": _contains,
    "starts_with": _starts_with,
    "ends_with": _ends_with,
    "matches": _matches,
}
COMPARISONS.update({name: _case_check(pattern) for name, pattern in _CASES.items()})


_STYLES = {
    "is_pascal": "PascalCase",
    "is_camel": "camelCase",
    "is_snake": "snake_case",
    "is_kebab": "kebab-case",
    "is_lower": "lowercase",
    "is_upper": "UPPERCASE",
}


def _inspected(condition, resource):
    """The (key, value) pairs a condition looks at; absent or empty values are None."""
    if condition.target == "type":
        return [(None, resource.type)]
    if condition.target == "address":
        return [(None, resource.address)]
    pairs = []
    for key in condition.keys:
        if resource.tag_unknown(key):
            pairs.append((key, _UNKNOWN_VALUE))
        else:
            value = resource.tags.get(key)
            pairs.append((key, None if value in (None, "") else value))
    return pairs


def evaluate(condition, resource):
    """Returns (key, state, value) for each key the condition inspects."""
    results = []
    for key, value in _inspected(condition, resource):
        if value is _UNKNOWN_VALUE:
            results.append((key, UNKNOWN, None))
            continue
        if condition.operator == "present":
            holds = (value is not None) == condition.operand
        else:
            holds = value is not None and COMPARISONS[condition.operator](value, condition.operand)
        if condition.negate:
            holds = not holds
        results.append((key, PASS if holds else FAIL, value))
    return results


def check_resource(policy, resource):
    """Runs every rule against one resource; returns (violations, unverified)."""
    violations, unverified = [], []
    if resource.skip_reason:
        unverified.append(Unverified("", resource.address, resource.skip_reason))
        return violations, unverified
    for rule in policy.rules:
        _run(rule, resource, violations, unverified)
    return violations, unverified


def _run(rule, resource, violations, unverified):
    for step in rule.steps:
        results = evaluate(step.condition, resource)
        if step.kind == FILTER:
            if any(state == FAIL for _, state, _ in results):
                return
            unknown = [key for key, state, _ in results if state == UNKNOWN]
            if unknown:
                message = f"{unknown[0]} is unknown until apply, so the rule was not evaluated"
                unverified.append(Unverified(rule.name, resource.address, message))
                return
        elif step.kind == ASSERT:
            for key, state, value in results:
                if state == FAIL:
                    message = _message(step.condition, key, value)
                    violations.append(Violation(rule.name, rule.severity, resource.address, message))
                elif state == UNKNOWN:
                    message = f"{key} is unknown until apply"
                    unverified.append(Unverified(rule.name, resource.address, message))
    # Reached only when every filter in the chain matched, which children inherit
    for child in rule.children:
        _run(child, resource, violations, unverified)


def _message(condition, key, value):
    subject = f"tag {key}" if condition.target == "tag" else condition.target
    negation = "not " if condition.negate else ""
    found = "" if value is None else f", found {value}"
    return f"{subject} must {negation}{_phrase(condition)}{found}"


def _phrase(condition):
    operator, operand = condition.operator, condition.operand
    if operator == "present":
        return "be present" if operand else "be absent"
    if operator in _CASES:
        style = _STYLES[operator]
        return f"be {style}" if operand else f"not be {style}"
    listed = ", ".join(operand)
    many = len(operand) > 1
    if operator in ("equals", "in"):
        return f"be one of {listed}" if many else f"be {listed}"
    verb = {
        "contains": "contain",
        "starts_with": "start with",
        "ends_with": "end with",
        "matches": "match",
    }[operator]
    return f"{verb} one of {listed}" if many else f"{verb} {listed}"
