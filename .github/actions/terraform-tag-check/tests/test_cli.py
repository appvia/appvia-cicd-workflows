import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import support
from support import change, plan, write_json

CHECK_SH = support.ACTION_DIR / "check.sh"

POLICY = """\
version: 1
rules:
  - name: required-tags
    steps:
      - assert: {tag: [Environment, Team], present: true}
  - name: s3-data-classification
    steps:
      - filter: {type: aws_s3_bucket}
      - assert: {tag: DataClassification, present: true}
  - name: advisory
    severity: warning
    steps:
      - assert: {tag: Owner, present: true}
"""

GOOD = {"Environment": "Production", "Team": "x", "DataClassification": "Public", "Owner": "me"}


class CliTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.policy = self.tmp / "policy.yaml"
        self.policy.write_text(POLICY, encoding="utf-8")

    def run_check(self, plan_json, policy=None):
        summary, output = self.tmp / "summary.md", self.tmp / "output.txt"
        summary.write_text("", encoding="utf-8")
        output.write_text("", encoding="utf-8")
        env = {
            **os.environ,
            "PLAN_JSON": str(plan_json),
            "POLICY_FILE": str(policy or self.policy),
            "GITHUB_STEP_SUMMARY": str(summary),
            "GITHUB_OUTPUT": str(output),
        }
        done = subprocess.run(["bash", str(CHECK_SH)], env=env, capture_output=True, text=True, cwd=self.tmp)
        return done, summary.read_text(encoding="utf-8"), output.read_text(encoding="utf-8")

    def write_plan(self, *changes, name="plan.json"):
        path = self.tmp / name
        write_json(path, plan(*changes))
        return path

    def test_compliant_plan_passes(self):
        path = self.write_plan(change("aws_s3_bucket.b", "aws_s3_bucket", {"tags_all": GOOD}))
        done, summary, output = self.run_check(path)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("violations=0", output)
        self.assertIn("meet the tagging policy", summary)

    def test_violations_fail_with_annotations_summary_and_output(self):
        bad = {"Environment": "Production", "Team": "x", "Owner": "me"}
        path = self.write_plan(
            change("aws_s3_bucket.b", "aws_s3_bucket", {"tags_all": bad}),
            change("aws_sqs_queue.q", "aws_sqs_queue", {"tags_all": {"Owner": "me"}}),
        )
        done, summary, output = self.run_check(path)
        self.assertEqual(done.returncode, 1)
        self.assertIn("violations=2", output)
        self.assertIn(
            "::error title=Tag Policy::aws_s3_bucket.b (", done.stdout
        )
        self.assertIn("s3-data-classification: tag DataClassification must be present", done.stdout)
        self.assertIn("required-tags: tag Environment must be present", done.stdout)
        self.assertIn("| Rule |", summary)

    def test_warning_severity_rules_do_not_fail_the_job(self):
        tags = {"Environment": "Production", "Team": "x", "DataClassification": "Public"}
        path = self.write_plan(change("aws_s3_bucket.b", "aws_s3_bucket", {"tags_all": tags}))
        done, summary, output = self.run_check(path)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("::warning title=Tag Policy::aws_s3_bucket.b", done.stdout)
        self.assertIn("violations=0", output)

    def test_unknown_values_warn_without_failing(self):
        path = self.write_plan(
            change(
                "aws_s3_bucket.b",
                "aws_s3_bucket",
                {"tags_all": {"Environment": "Production", "DataClassification": "x", "Owner": "me"}},
                {"tags_all": {"Team": True}},
            )
        )
        done, summary, output = self.run_check(path)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("Team is unknown until apply", done.stdout)
        self.assertIn("Not verifiable at plan time", summary)

    def test_directory_of_plans_is_searched_recursively(self):
        folder = self.tmp / "plans" / "nested"
        folder.mkdir(parents=True)
        write_json(folder / "one.json", plan(change("a.b", "aws_sqs_queue", {"tags_all": {}})))
        done, _, output = self.run_check(self.tmp / "plans")
        self.assertEqual(done.returncode, 1)
        self.assertIn("one.json", done.stdout)
        self.assertIn("violations=1", output)

    def test_empty_directory_passes_with_warning(self):
        (self.tmp / "empty").mkdir()
        done, _, output = self.run_check(self.tmp / "empty")
        self.assertEqual(done.returncode, 0)
        self.assertIn("::warning title=Tag Policy::no plan json files found", done.stdout)
        self.assertIn("violations=0", output)

    def test_usage_errors_exit_2(self):
        path = self.write_plan()
        cases = {
            "missing plan": (self.tmp / "nope.json", self.policy),
            "missing policy": (path, self.tmp / "nope.yaml"),
        }
        for label, (plan_json, policy) in cases.items():
            with self.subTest(label):
                done, _, _ = self.run_check(plan_json, policy)
                self.assertEqual(done.returncode, 2)
                self.assertIn("::error title=Tag Policy::", done.stdout)

    def test_invalid_policy_and_invalid_plan_exit_2(self):
        bad_policy = self.tmp / "bad.yaml"
        bad_policy.write_text("version: 1\nrules:\n  - name: r\n    steps: []\n", encoding="utf-8")
        done, _, _ = self.run_check(self.write_plan(), bad_policy)
        self.assertEqual(done.returncode, 2)
        self.assertIn("rule r", done.stdout)

        broken = self.tmp / "broken.json"
        broken.write_text("{nope", encoding="utf-8")
        done, _, _ = self.run_check(broken)
        self.assertEqual(done.returncode, 2)

    def test_required_environment_variables(self):
        env = {k: v for k, v in os.environ.items() if k not in ("PLAN_JSON", "POLICY_FILE")}
        done = subprocess.run(["bash", str(CHECK_SH)], env=env, capture_output=True, text=True)
        self.assertEqual(done.returncode, 2)
        self.assertIn("PLAN_JSON must be set", done.stdout)

    def test_non_plan_resource_changes_exits_2(self):
        path = self.tmp / "oops.json"
        write_json(path, {"resource_changes": "oops"})
        done, _, _ = self.run_check(path)
        self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
        self.assertIn("::error title=Tag Policy::", done.stdout)

    def test_unexpected_exception_exits_2(self):
        path = self.write_plan(change("aws_s3_bucket.b", "aws_s3_bucket", {"tags_all": GOOD}))
        env = {
            **os.environ,
            "PLAN_JSON": str(path),
            "POLICY_FILE": str(self.policy),
            "GITHUB_STEP_SUMMARY": str(self.tmp / "nonexistent" / "x"),
        }
        done = subprocess.run(["bash", str(CHECK_SH)], env=env, capture_output=True, text=True, cwd=self.tmp)
        self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
        self.assertIn("::error title=Tag Policy::", done.stdout)
        self.assertIn("Traceback", done.stderr)


if __name__ == "__main__":
    unittest.main()
