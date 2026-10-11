import re
import unittest

import support
from support import change, plan

from engine import check_resource
from plan import resources
from policy import load_policy

POLICY_FILE = support.REPO_ROOT / "config" / "tagging-policy.yaml"
BASE = {"Environment": "Production", "Product": "a", "GitRepo": "https://github.com/org/repo"}


def messages(policy, rtype, tags):
    resource = next(resources(plan(change(f"{rtype}.x", rtype, {"tags_all": tags}))))
    return [v.message for v in check_resource(policy, resource)[0]]


class ShippedPolicyTest(unittest.TestCase):
    def setUp(self):
        self.policy = load_policy(str(POLICY_FILE))

    def test_policy_loads(self):
        self.assertGreater(len(self.policy.rules), 0)

    def test_baseline_tags_and_environment_values(self):
        self.assertEqual(messages(self.policy, "aws_sqs_queue", BASE), [])
        self.assertEqual(
            messages(self.policy, "aws_sqs_queue", {**BASE, "Environment": "prod"}),
            ["tag Environment must be one of Production, Staging, Uat, Testing, Development, Sandbox, found prod"],
        )
        self.assertEqual(
            messages(self.policy, "aws_sqs_queue", {"Environment": "Production"}),
            ["tag Product must be present", "tag GitRepo must be present"],
        )

    def test_s3_buckets_need_a_data_classification(self):
        self.assertEqual(messages(self.policy, "aws_s3_bucket", BASE), ["tag DataClassification must be present"])
        self.assertEqual(messages(self.policy, "aws_s3_bucket", {**BASE, "DataClassification": "Internal"}), [])

    def test_development_instances_need_a_schedule(self):
        dev = {**BASE, "Environment": "Development"}
        self.assertEqual(
            messages(self.policy, "aws_instance", dev),
            ["tag Schedule must be one of AlwaysOn, UkWorkingHours, UkExtendedHours, WeekendsOnly, PlatformValidation"],
        )
        self.assertEqual(messages(self.policy, "aws_instance", {**dev, "Schedule": "AlwaysOn"}), [])
        self.assertEqual(messages(self.policy, "aws_instance", BASE), [])

    def test_git_repo_must_be_a_github_url(self):
        self.assertEqual(
            messages(self.policy, "aws_sqs_queue", {**BASE, "GitRepo": "r"}),
            ["tag GitRepo must start with https://github.com/, found r"],
        )

    def test_default_placeholder_values_are_rejected(self):
        self.assertEqual(
            messages(self.policy, "aws_sqs_queue", {**BASE, "Product": "PRODUCT_NAME"}),
            ["tag Product must not be PRODUCT_NAME, found PRODUCT_NAME"],
        )
        self.assertEqual(
            messages(self.policy, "aws_sqs_queue", {**BASE, "Tenant": "TENANT_NAME"}),
            ["tag Tenant must not be TENANT_NAME, found TENANT_NAME"],
        )

    def test_backup_tiers(self):
        for good in ("Bronze1d", "Silver4w", "Gold12m"):
            self.assertEqual(messages(self.policy, "aws_sqs_queue", {**BASE, "BackupTiers": good}), [], good)
        for bad in ("Gold1|", "Gold1y", "Platinum1d", "bronze1d"):
            self.assertEqual(len(messages(self.policy, "aws_sqs_queue", {**BASE, "BackupTiers": bad})), 1, bad)

    def test_sandbox_requires_disable_nuke(self):
        sandbox = {**BASE, "Environment": "Sandbox"}
        self.assertEqual(len(messages(self.policy, "aws_sqs_queue", sandbox)), 1)
        self.assertEqual(messages(self.policy, "aws_sqs_queue", {**sandbox, "DisableNuke": "true"}), [])


class TflintSyncTest(unittest.TestCase):
    def test_tflint_required_tags_match_the_policy(self):
        policy = load_policy(str(POLICY_FILE))
        required = next(rule for rule in policy.rules if rule.name == "required-tags")
        keys = required.steps[0].condition.keys

        hcl = (support.REPO_ROOT / "config" / ".tflint.hcl").read_text(encoding="utf-8")
        match = re.search(r'^rule "aws_resource_missing_tags" \{(.*?)\n\}', hcl, re.S | re.M)
        if match is None:
            self.skipTest("aws_resource_missing_tags is not enabled in config/.tflint.hcl")
        block = match.group(1)
        tags = re.findall(r'"([^"]+)"', re.search(r"tags\s*=\s*\[(.*?)\]", block, re.S).group(1))
        exclude = re.findall(r'"([^"]+)"', re.search(r"exclude\s*=\s*\[(.*?)\]", block, re.S).group(1))

        self.assertEqual(sorted(tags), sorted(keys))
        self.assertEqual(set(exclude), set(policy.exclude_resource_types))


if __name__ == "__main__":
    unittest.main()
