import unittest

import support  # noqa: F401  (puts the action directory on sys.path)

from engine import Unverified, Violation
from policy import parse_policy
from report import FileResult, annotations, failing_resources, summary

POLICY = parse_policy(
    {
        "version": 1,
        "rules": [
            {
                "name": "required",
                "description": "Baseline tags",
                "steps": [{"assert": {"tag": "A", "present": True}}],
                "rules": [{"name": "child", "steps": [{"assert": {"tag": "B", "present": True}}]}],
            }
        ],
    }
)


def violation(address="a.b", rule="required", severity="error", message="tag A must be present"):
    return Violation(rule, severity, address, message)


class ReportTest(unittest.TestCase):
    def test_failing_resources_counts_distinct_error_resources_only(self):
        results = [
            FileResult("p1.json", [violation("a.b"), violation("a.b", rule="other"), violation("a.c", severity="warning")], []),
            FileResult("p2.json", [violation("a.b")], []),
        ]
        self.assertEqual(failing_resources(results), {("p1.json", "a.b"), ("p2.json", "a.b")})

    def test_annotations(self):
        results = [
            FileResult(
                "p.json",
                [violation(), violation("a.w", rule="soft", severity="warning", message="tag B must be present")],
                [Unverified("required", "a.u", "Team is unknown until apply"), Unverified("", "a.s", "tags is not a map of tags, so it was not checked")],
            )
        ]
        self.assertEqual(
            annotations(results),
            [
                "::error title=Tag Policy::a.b (p.json) required: tag A must be present",
                "::warning title=Tag Policy::a.w (p.json) soft: tag B must be present",
                "::warning title=Tag Policy::a.u (p.json) required: Team is unknown until apply",
                "::warning title=Tag Policy::a.s (p.json) tags is not a map of tags, so it was not checked",
            ],
        )

    def test_annotation_escapes_workflow_command_characters(self):
        results = [FileResult("p.json", [violation(message="tag A must be x, found 100%\nnext")], [])]
        (line,) = annotations(results)
        self.assertNotIn("\n", line)
        self.assertIn("100%25%0Anext", line)

    def test_summary_when_compliant(self):
        text = summary([FileResult("p.json", [], [])], POLICY)
        self.assertIn("All resources being created or updated meet the tagging policy (checked against 2 rules).", text)
        self.assertNotIn("| File |", text)
        self.assertTrue(text.endswith("\n"))

    def test_summary_with_violations_table_and_rules(self):
        results = [FileResult("p.json", [violation(), violation("a.w", rule="soft", severity="warning")], [])]
        text = summary(results, POLICY)
        self.assertIn("1 resource(s) do not meet the tagging policy.", text)
        self.assertIn("| File | Address | Rule | Message |", text)
        self.assertIn("| `p.json` | `a.b` | `required` | tag A must be present |", text)
        self.assertIn("| `p.json` | `a.w` | `soft` (warning) | tag A must be present |", text)
        self.assertIn("- `required`: Baseline tags", text)
        self.assertIn("- `required/child`", text)

    def test_summary_with_only_warnings(self):
        results = [FileResult("p.json", [], [Unverified("required", "a.u", "Team is unknown until apply")])]
        text = summary(results, POLICY)
        self.assertIn("No resources violate the tagging policy, but some", text)
        self.assertIn("**Not verifiable at plan time:**", text)
        self.assertIn("- `a.u` (required): Team is unknown until apply", text)

    def test_summary_escapes_table_cells(self):
        results = [FileResult("p.json", [violation(message="tag A must be x, found a|b\nc")], [])]
        row = [line for line in summary(results, POLICY).splitlines() if "`a.b`" in line][0]
        self.assertIn("found a\\|b c |", row)


if __name__ == "__main__":
    unittest.main()
