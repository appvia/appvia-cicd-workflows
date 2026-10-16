import tempfile
import unittest
from pathlib import Path

import support
from support import change, plan

from plan import PlanError, Resource, load_plan, resources


def only(terraform_plan, exclude=()):
    found = list(resources(terraform_plan, exclude))
    assert len(found) == 1, found
    return found[0]


class ResourcesTest(unittest.TestCase):
    def test_checks_created_and_updated_managed_resources(self):
        terraform_plan = plan(
            change("a.created", "aws_s3_bucket", {"tags_all": {"A": "1"}}),
            change("a.updated", "aws_s3_bucket", {"tags_all": {"A": "1"}}, actions=("update",)),
            change("a.replaced", "aws_s3_bucket", {"tags_all": {"A": "1"}}, actions=("delete", "create")),
        )
        self.assertEqual(
            [r.address for r in resources(terraform_plan)], ["a.created", "a.updated", "a.replaced"]
        )

    def test_skips_deleted_unchanged_and_data_sources(self):
        tags = {"tags_all": {"A": "1"}}
        terraform_plan = plan(
            change("a.deleted", "aws_s3_bucket", tags, actions=("delete",)),
            change("a.noop", "aws_s3_bucket", tags, actions=("no-op",)),
            change("a.read", "aws_s3_bucket", tags, actions=("read",)),
            change("data.a", "aws_s3_bucket", tags, mode="data"),
        )
        self.assertEqual(list(resources(terraform_plan)), [])

    def test_skips_excluded_types(self):
        terraform_plan = plan(change("a.b", "aws_s3_bucket", {"tags_all": {}}))
        self.assertEqual(list(resources(terraform_plan, {"aws_s3_bucket"})), [])

    def test_skips_resources_without_tag_attributes(self):
        self.assertEqual(list(resources(plan(change("a.b", "aws_iam_policy", {"name": "x"})))), [])

    def test_prefers_tags_all_over_tags(self):
        resource = only(plan(change("a.b", "t", {"tags": {"A": "1"}, "tags_all": {"A": "1", "B": "2"}})))
        self.assertEqual(resource.tags, {"A": "1", "B": "2"})

    def test_falls_back_to_tags(self):
        resource = only(plan(change("a.b", "t", {"tags": {"A": "1"}})))
        self.assertEqual(resource.tags, {"A": "1"})

    def test_reads_awscc_list_tags(self):
        resource = only(plan(change("a.b", "t", {"tags": [{"key": "A", "value": "1"}]})))
        self.assertEqual(resource.tags, {"A": "1"})

    def test_non_map_tags_are_skipped_with_a_reason(self):
        resource = only(plan(change("a.b", "t", {"tags": "oops"})))
        self.assertIn("not a map of tags", resource.skip_reason)
        resource = only(plan(change("a.b", "t", {"tags": [{"nope": 1}]})))
        self.assertIn("not a map of tags", resource.skip_reason)

    def test_null_after_and_null_tags(self):
        terraform_plan = plan(change("a.b", "t", {"tags_all": None}))
        self.assertEqual(only(terraform_plan).tags, {})
        terraform_plan["resource_changes"][0]["change"]["after"] = None
        terraform_plan["resource_changes"][0]["change"]["after_unknown"] = {"tags": False}
        self.assertEqual(only(terraform_plan).tags, {})

    def test_unknown_individual_tag(self):
        resource = only(
            plan(change("a.b", "t", {"tags_all": {"A": "1"}}, {"tags_all": {"Team": True}}))
        )
        self.assertTrue(resource.tag_unknown("Team"))
        self.assertFalse(resource.tag_unknown("A"))
        self.assertFalse(resource.tag_unknown("Other"))

    def test_whole_attribute_unknown_keeps_known_tags(self):
        resource = only(
            plan(change("a.b", "t", {"tags": {"A": "1"}}, {"tags_all": True}))
        )
        self.assertEqual(resource.tags, {"A": "1"})
        self.assertFalse(resource.tag_unknown("A"))
        self.assertTrue(resource.tag_unknown("Team"))


class ResourceChangesShapeTest(unittest.TestCase):
    def test_non_list_resource_changes_is_a_plan_error(self):
        for bad in ("oops", {"a": 1}, 5):
            with self.subTest(bad=bad), self.assertRaises(PlanError):
                list(resources({"resource_changes": bad}))

    def test_absent_or_null_resource_changes_yield_nothing(self):
        self.assertEqual(list(resources({})), [])
        self.assertEqual(list(resources({"resource_changes": None})), [])


class LoadPlanTest(unittest.TestCase):
    def test_errors(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad.json"
            bad.write_text("{not json", encoding="utf-8")
            with self.assertRaises(PlanError):
                load_plan(str(bad))
            listed = Path(tmp) / "list.json"
            listed.write_text("[]", encoding="utf-8")
            with self.assertRaises(PlanError):
                load_plan(str(listed))
            with self.assertRaises(PlanError):
                load_plan(str(Path(tmp) / "missing.json"))

    def test_loads_an_object(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "plan.json"
            support.write_json(path, plan())
            self.assertEqual(load_plan(str(path))["resource_changes"], [])


if __name__ == "__main__":
    unittest.main()
