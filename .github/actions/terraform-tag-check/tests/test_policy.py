import tempfile
import unittest
from pathlib import Path

import support  # noqa: F401  (puts the action directory on sys.path)

from policy import Condition, PolicyError, load_policy, parse_policy


def policy_with(*rules, **extra):
    return {"version": 1, "rules": list(rules), **extra}


def rule(*steps, name="r", **extra):
    return {"name": name, "steps": list(steps), **extra}


def assert_step(**condition):
    return {"assert": condition}


def filter_step(**condition):
    return {"filter": condition}


class ParsePolicyTest(unittest.TestCase):
    def test_parses_a_chain(self):
        policy = parse_policy(
            policy_with(
                rule(
                    filter_step(type=["aws_instance", "aws_ebs_volume"]),
                    filter_step(tag="Environment", equals="Development"),
                    assert_step(tag="Schedule", **{"in": ["UkWorkingHours", "AlwaysOn"]}),
                    name="dev-schedule",
                    description="Dev needs a schedule",
                    severity="warning",
                ),
                exclude_resource_types=["aws_x"],
            )
        )
        self.assertEqual(policy.exclude_resource_types, frozenset({"aws_x"}))
        parsed = policy.rules[0]
        self.assertEqual((parsed.name, parsed.severity), ("dev-schedule", "warning"))
        self.assertEqual(parsed.description, "Dev needs a schedule")
        self.assertEqual([s.kind for s in parsed.steps], ["filter", "filter", "assert"])
        self.assertEqual(
            parsed.steps[0].condition,
            Condition("type", (), "equals", ("aws_instance", "aws_ebs_volume")),
        )
        self.assertEqual(
            parsed.steps[1].condition, Condition("tag", ("Environment",), "equals", ("Development",))
        )
        self.assertEqual(
            parsed.steps[2].condition,
            Condition("tag", ("Schedule",), "in", ("UkWorkingHours", "AlwaysOn")),
        )

    def test_defaults(self):
        parsed = parse_policy(policy_with(rule(assert_step(tag="A", present=True)))).rules[0]
        self.assertEqual((parsed.severity, parsed.description, parsed.children), ("error", "", ()))

    def test_tag_key_list_and_not(self):
        step = parse_policy(
            policy_with(rule(assert_step(tag=["A", "B"], present=True, **{"not": True})))
        ).rules[0].steps[0]
        self.assertEqual(step.condition, Condition("tag", ("A", "B"), "present", True, True))

    def test_type_and_address_mapping_form(self):
        rules = parse_policy(
            policy_with(
                rule(
                    filter_step(type={"starts_with": "aws_s3_"}),
                    filter_step(address={"starts_with": "module.data"}, **{"not": True}),
                )
            )
        ).rules[0]
        self.assertEqual(rules.steps[0].condition, Condition("type", (), "starts_with", ("aws_s3_",)))
        self.assertEqual(
            rules.steps[1].condition, Condition("address", (), "starts_with", ("module.data",), True)
        )

    def test_nested_rules_get_path_names(self):
        policy = parse_policy(
            policy_with(
                rule(
                    filter_step(type="aws_instance"),
                    name="ec2",
                    rules=[rule(assert_step(tag="Backup", present=True), name="backup")],
                )
            )
        )
        self.assertEqual(policy.rules[0].children[0].name, "ec2/backup")

    def test_matches_parses_for_tags_and_types(self):
        parsed = parse_policy(
            policy_with(rule(filter_step(type={"matches": "^aws_s3_"}), assert_step(tag="Name", matches=["^a", "b$"])))
        ).rules[0]
        self.assertEqual(parsed.steps[0].condition, Condition("type", (), "matches", ("^aws_s3_",)))
        self.assertEqual(parsed.steps[1].condition, Condition("tag", ("Name",), "matches", ("^a", "b$")))

    def test_empty_rule_list_is_valid(self):
        self.assertEqual(parse_policy(policy_with()).rules, ())


class InvalidPolicyTest(unittest.TestCase):
    def assertInvalid(self, data, fragment):
        with self.assertRaises(PolicyError) as raised:
            parse_policy(data)
        self.assertIn(fragment, str(raised.exception))

    def test_top_level(self):
        self.assertInvalid(None, "mapping")
        self.assertInvalid({"rules": []}, "version")
        self.assertInvalid({"version": 2, "rules": []}, "version")
        self.assertInvalid({"version": True, "rules": []}, "version")
        self.assertInvalid({"version": 1}, "rules must be a list")
        self.assertInvalid(policy_with(extra=1), "unknown field")
        self.assertInvalid(policy_with(exclude_resource_types="aws_x"), "exclude_resource_types")

    def test_rule_shape(self):
        ok = assert_step(tag="A", present=True)
        self.assertInvalid(policy_with("nope"), "mapping")
        self.assertInvalid(policy_with({"steps": [ok]}), "name")
        self.assertInvalid(policy_with(rule(ok, name="a/b")), "name")
        self.assertInvalid(policy_with(rule(ok, name="a"), rule(ok, name="a")), "duplicate rule name")
        self.assertInvalid(policy_with(rule(ok, bogus=1)), "rule r: unknown field")
        self.assertInvalid(policy_with(rule(ok, severity="fatal")), "severity")
        self.assertInvalid(policy_with(rule(ok, description=3)), "description")
        self.assertInvalid(policy_with(rule()), "rule r: steps must be a non-empty list")
        self.assertInvalid(policy_with({"name": "r"}), "steps")
        self.assertInvalid(policy_with(rule(ok, rules="x")), "rules")

    def test_nested_duplicate_names_are_scoped_to_the_parent(self):
        ok = assert_step(tag="A", present=True)
        parsed = parse_policy(
            policy_with(
                rule(ok, name="a", rules=[rule(ok, name="x")]),
                rule(ok, name="b", rules=[rule(ok, name="x")]),
            )
        )
        self.assertEqual([c.name for r in parsed.rules for c in r.children], ["a/x", "b/x"])
        self.assertInvalid(
            policy_with(rule(ok, name="a", rules=[rule(ok, name="x"), rule(ok, name="x")])),
            "duplicate rule name",
        )

    def test_step_shape(self):
        ok = {"tag": "A", "present": True}
        self.assertInvalid(policy_with(rule("nope")), "mapping")
        self.assertInvalid(policy_with(rule({})), "exactly one of 'filter' or 'assert'")
        self.assertInvalid(policy_with(rule({"filter": ok, "assert": ok})), "exactly one")
        self.assertInvalid(policy_with(rule({"filter": ok, "extra": 1})), "exactly one")

    def test_condition_shape(self):
        self.assertInvalid(policy_with(rule(assert_step())), "exactly one of type, address, tag")
        self.assertInvalid(
            policy_with(rule(assert_step(tag="A", type="x", present=True))), "exactly one of type"
        )
        self.assertInvalid(policy_with(rule(assert_step(tag="A"))), "exactly one operator")
        self.assertInvalid(
            policy_with(rule(assert_step(tag="A", present=True, equals="x"))), "exactly one operator"
        )
        self.assertInvalid(policy_with(rule(assert_step(tag="A", bogus="x"))), "unknown field")
        self.assertInvalid(
            policy_with(rule(assert_step(tag="A", present=True, **{"not": "yes"}))), "'not'"
        )
        self.assertInvalid(policy_with(rule(assert_step(type="x", equals="y"))), "type: value")
        self.assertInvalid(policy_with(rule(assert_step(type={"bogus": "x"}))), "operator")
        self.assertInvalid(policy_with(rule(assert_step(type={"present": True}))), "operator")
        self.assertInvalid(
            policy_with(rule(assert_step(type={"equals": "x", "contains": "y"}))), "operator"
        )

    def test_operand_types(self):
        self.assertInvalid(policy_with(rule(assert_step(tag="A", present="yes"))), "present")
        self.assertInvalid(policy_with(rule(assert_step(tag="A", equals=[]))), "non-empty list")
        self.assertInvalid(policy_with(rule(assert_step(tag="A", equals=[1]))), "list of strings")
        self.assertInvalid(policy_with(rule(assert_step(tag="A", equals=""))), "string")
        self.assertInvalid(policy_with(rule(assert_step(tag=[], present=True))), "tag")
        self.assertInvalid(policy_with(rule(assert_step(type=3))), "type")

    def test_invalid_regular_expression_is_rejected(self):
        self.assertInvalid(policy_with(rule(assert_step(tag="A", matches="("))), "invalid regular expression")
        self.assertInvalid(policy_with(rule(assert_step(tag="A", matches=["ok", "["]))), "invalid regular expression")
        self.assertInvalid(policy_with(rule(filter_step(type={"matches": "*"}))), "invalid regular expression")

    def test_unquoted_scalar_operand_is_rejected(self):
        # YAML parses yes/no/on/off as booleans and 1 as an integer
        self.assertInvalid(policy_with(rule(assert_step(tag="A", equals=True))), "equals")
        self.assertInvalid(policy_with(rule(assert_step(tag="A", equals=1))), "equals")


class LoadPolicyTest(unittest.TestCase):
    def write(self, text):
        handle = tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False, encoding="utf-8")
        handle.write(text)
        handle.close()
        self.addCleanup(Path(handle.name).unlink)
        return handle.name

    def test_loads_yaml(self):
        path = self.write(
            "version: 1\nrules:\n  - name: r\n    steps:\n      - assert: {tag: A, present: true}\n"
        )
        self.assertEqual(load_policy(path).rules[0].name, "r")

    def test_non_utf8_file_is_a_policy_error(self):
        handle = tempfile.NamedTemporaryFile("wb", suffix=".yaml", delete=False)
        handle.write(b"\xff\xfe\x00")
        handle.close()
        self.addCleanup(Path(handle.name).unlink)
        with self.assertRaises(PolicyError):
            load_policy(handle.name)

    def test_unreadable_and_malformed_files(self):
        with self.assertRaises(PolicyError):
            load_policy("/nonexistent/policy.yaml")
        with self.assertRaises(PolicyError):
            load_policy(self.write("version: [1\n"))
        with self.assertRaises(PolicyError):
            load_policy(self.write(""))


if __name__ == "__main__":
    unittest.main()
