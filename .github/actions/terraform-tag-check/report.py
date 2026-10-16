"""Renders tag policy findings as GitHub annotations and a job summary."""
from dataclasses import dataclass


@dataclass(frozen=True)
class FileResult:
    file: str
    violations: list
    unverified: list


def failing_resources(results):
    """The distinct (file, address) pairs with at least one error-severity violation."""
    return {
        (result.file, violation.address)
        for result in results
        for violation in result.violations
        if violation.severity == "error"
    }


def annotations(results, audit=False):
    """In audit mode every violation is annotated as a warning."""
    lines = []
    for result in results:
        for violation in result.violations:
            level = "error" if violation.severity == "error" and not audit else "warning"
            text = f"{violation.address} ({result.file}) {violation.rule}: {violation.message}"
            lines.append(f"::{level} title=Tag Policy::{_annotation(text)}")
        for item in result.unverified:
            prefix = f"{item.rule}: " if item.rule else ""
            text = f"{item.address} ({result.file}) {prefix}{item.message}"
            lines.append(f"::warning title=Tag Policy::{_annotation(text)}")
    return lines


def summary(results, policy, audit=False):
    failing = len(failing_resources(results))
    violations = [(r.file, v) for r in results for v in r.violations]
    unverified = [(r.file, u) for r in results for u in r.unverified]
    lines = ["### 🏷️ Tag Policy", ""]
    if audit:
        lines += ["> [!WARNING]", "> Audit mode: violations are reported but do not fail the job.", ""]
    if failing:
        lines.append(f"{failing} resource(s) do not meet the tagging policy.")
    elif violations or unverified:
        lines.append(
            "No resources violate the tagging policy, but some have warnings or could not be fully verified."
        )
    else:
        lines.append(f"{passed_message(policy)}.")
    if violations:
        lines += ["", "| File | Address | Rule | Message |", "|------|---------|------|---------|"]
        for file, violation in violations:
            rule = f"`{violation.rule}`" + ("" if violation.severity == "error" else " (warning)")
            lines.append(
                f"| `{file}` | `{violation.address}` | {rule} | {_cell(violation.message)} |"
            )
    if unverified:
        lines += ["", "**Not verifiable at plan time:**", ""]
        for _, item in unverified:
            rule = f" ({item.rule})" if item.rule else ""
            lines.append(f"- `{item.address}`{rule}: {_cell(item.message)}")
    lines += ["", "Rules:", ""]
    for rule in _flatten(policy.rules):
        description = f": {rule.description}" if rule.description else ""
        lines.append(f"- `{rule.name}`{description}")
    return "\n".join(lines) + "\n"


def rule_count(policy):
    return sum(1 for _ in _flatten(policy.rules))


def passed_message(policy):
    count = rule_count(policy)
    noun = "rule" if count == 1 else "rules"
    return f"All resources being created or updated meet the tagging policy (checked against {count} {noun})"


def _flatten(rules):
    for rule in rules:
        yield rule
        yield from _flatten(rule.children)


# Workflow commands end at a newline and treat % as an escape character
def _annotation(text):
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def _cell(text):
    return str(text).replace("|", "\\|").replace("\r", " ").replace("\n", " ")
