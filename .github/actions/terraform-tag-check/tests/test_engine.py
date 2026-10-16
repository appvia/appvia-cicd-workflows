import unittest

import support  # noqa: F401  (puts the action directory on sys.path)

from engine import Violation, check_resource
from plan import Resource
from policy import parse_policy


def res(tags=None, rtype="aws_s3_bucket", address="aws_s3_bucket.b", **extra):
    return Resource(address, rtype, tags or {}, **extra)


def policy(*rules):
    return parse_policy({"version": 1, "rules": list(rules)})


def rule(*steps, name="r", **extra):
    return {"name": name, "steps": list(steps), **extra}


def assert_tag(tag, **operator):
    return {"assert": {"tag": tag, **operator}}


def filter_tag(tag, **operator):
    return {"filter": {"tag": tag, **operator}}


def filter_type(value):
    return {"filter": {"type": value}}


def violations(pol, resource):
    return check_resource(pol, resource)[0]


class OperatorTest(unittest.TestCase):
    CASES = [
        # (operator, operand, tags, holds)
        ("present", True, {"T": "x"}, True),
        ("present", True, {}, False),
        ("present", True, {"T": ""}, False),
        ("present", False, {}, True),
        ("present", False, {"T": ""}, True),
        ("present", False, {"T": "x"}, False),
        ("equals", "x", {"T": "x"}, True),
        ("equals", "x", {"T": "xy"}, False),
        ("equals", "x", {}, False),
        ("equals", ["x", "y"], {"T": "y"}, True),
        ("equals", ["x", "y"], {"T": "z"}, False),
        ("in", ["a", "b"], {"T": "b"}, True),
        ("in", ["a", "b"], {"T": "B"}, False),
        ("contains", "bc", {"T": "abcd"}, True),
        ("contains", "bc", {"T": "acbd"}, False),
        ("contains", ["zz", "cd"], {"T": "abcd"}, True),
        ("contains", "a", {}, False),
        ("starts_with", "ab", {"T": "abcd"}, True),
        ("starts_with", "bc", {"T": "abcd"}, False),
        ("starts_with", ["zz", "ab"], {"T": "abcd"}, True),
        ("ends_with", "cd", {"T": "abcd"}, True),
        ("ends_with", "bc", {"T": "abcd"}, False),
        ("ends_with", ["zz", "cd"], {"T": "abcd"}, True),
        ("matches", "^ab.d$", {"T": "abcd"}, True),
        ("matches", "bc", {"T": "abcd"}, True),
        ("matches", "^bc", {"T": "abcd"}, False),
        ("matches", ["^zz", "d$"], {"T": "abcd"}, True),
        ("matches", "a", {}, False),
        ("is_pascal", True, {"T": "CostCentre"}, True),
        ("is_pascal", True, {"T": "Production"}, True),
        ("is_pascal", True, {"T": "Team2Name"}, True),
        ("is_pascal", True, {"T": "costCentre"}, False),
        ("is_pascal", True, {"T": "cost-centre"}, False),
        ("is_pascal", True, {"T": "Cost_Centre"}, False),
        ("is_pascal", True, {"T": "AWSAccount"}, False),
        ("is_pascal", True, {"T": "2Cost"}, False),
        ("is_pascal", True, {"T": 123}, False),
        ("is_pascal", True, {}, False),
        ("is_camel", True, {"T": "costCentre"}, True),
        ("is_camel", True, {"T": "cost"}, True),
        ("is_camel", True, {"T": "CostCentre"}, False),
        ("is_snake", True, {"T": "cost_centre"}, True),
        ("is_snake", True, {"T": "cost"}, True),
        ("is_snake", True, {"T": "cost__centre"}, False),
        ("is_snake", True, {"T": "Cost_centre"}, False),
        ("is_snake", True, {"T": "cost-centre"}, False),
        ("is_kebab", True, {"T": "cost-centre"}, True),
        ("is_kebab", True, {"T": "cost_centre"}, False),
        ("is_kebab", True, {"T": "cost-"}, False),
        ("is_lower", True, {"T": "prod1"}, True),
        ("is_lower", True, {"T": "Prod"}, False),
        ("is_lower", True, {"T": "pro-d"}, False),
        ("is_upper", True, {"T": "PROD1"}, True),
        ("is_upper", True, {"T": "Prod"}, False),
        ("is_upper", False, {"T": "Prod"}, True),
        ("is_pascal", False, {"T": "cost-centre"}, True),
        ("is_pascal", False, {"T": "CostCentre"}, False),
    ]

    def test_assert_operators(self):
        for operator, operand, tags, holds in self.CASES:
            with self.subTest(operator=operator, operand=operand, tags=tags):
                found = violations(policy(rule(assert_tag("T", **{operator: operand}))), res(tags))
                self.assertEqual(bool(found), not holds)

    def test_not_inverts_including_absent_targets(self):
        pol = policy(rule(assert_tag("Environment", equals="Production", **{"not": True})))
        self.assertEqual(violations(pol, res({})), [])
        self.assertEqual(violations(pol, res({"Environment": "Development"})), [])
        self.assertEqual(len(violations(pol, res({"Environment": "Production"}))), 1)

    def test_non_string_values_do_not_raise(self):
        for operator in ("contains", "starts_with", "ends_with", "matches"):
            with self.subTest(operator=operator):
                pol = policy(rule(assert_tag("T", **{operator: "1"})))
                self.assertEqual(len(violations(pol, res({"T": 123}))), 1)

    def test_environment_must_not_equal_the_application_name(self):
        pol = policy(rule(assert_tag("Environment", equals="APPLICATION_NAME", **{"not": True})))
        self.assertEqual(violations(pol, res({"Environment": "Production"})), [])
        found = violations(pol, res({"Environment": "APPLICATION_NAME"}))
        self.assertEqual(
            [v.message for v in found],
            ["tag Environment must not be APPLICATION_NAME, found APPLICATION_NAME"],
        )

    def test_multiple_tag_keys_each_must_hold(self):
        pol = policy(rule(assert_tag(["A", "B", "C"], present=True)))
        found = violations(pol, res({"A": "1"}))
        self.assertEqual([v.message for v in found], [
            "tag B must be present",
            "tag C must be present",
        ])


class TargetTest(unittest.TestCase):
    def test_type_shorthand_and_list(self):
        pol = policy(rule(filter_type(["aws_instance", "aws_s3_bucket"]), assert_tag("T", present=True)))
        self.assertEqual(len(violations(pol, res(rtype="aws_s3_bucket"))), 1)
        self.assertEqual(violations(pol, res(rtype="aws_iam_role")), [])

    def test_type_operator_mapping(self):
        pol = policy(rule(filter_type({"starts_with": "aws_s3_"}), assert_tag("T", present=True)))
        self.assertEqual(len(violations(pol, res(rtype="aws_s3_bucket_policy"))), 1)
        self.assertEqual(violations(pol, res(rtype="aws_instance")), [])

    def test_address_with_not(self):
        step = {"filter": {"address": {"starts_with": "module.legacy"}, "not": True}}
        pol = policy(rule(step, assert_tag("T", present=True)))
        self.assertEqual(violations(pol, res(address="module.legacy.aws_s3_bucket.b")), [])
        self.assertEqual(len(violations(pol, res(address="module.new.aws_s3_bucket.b"))), 1)

    def test_rule_without_filter_applies_to_everything(self):
        pol = policy(rule(assert_tag("T", present=True)))
        self.assertEqual(len(violations(pol, res(rtype="aws_anything"))), 1)


class ChainTest(unittest.TestCase):
    def dev_schedule(self):
        return policy(
            rule(
                filter_type("aws_instance"),
                filter_tag("Environment", equals="Development"),
                assert_tag("Schedule", **{"in": ["UkWorkingHours", "AlwaysOn"]}),
                name="dev-schedule",
            )
        )

    def test_chain_applies_only_when_every_filter_matches(self):
        pol = self.dev_schedule()
        instance = dict(rtype="aws_instance", address="aws_instance.i")
        self.assertEqual(violations(pol, res({"Environment": "Production"}, **instance)), [])
        self.assertEqual(violations(pol, res({"Environment": "Development"}, rtype="aws_s3_bucket")), [])
        self.assertEqual(
            violations(pol, res({"Environment": "Development", "Schedule": "AlwaysOn"}, **instance)), []
        )

    def test_violation_details_and_messages(self):
        pol = self.dev_schedule()
        instance = dict(rtype="aws_instance", address="aws_instance.i")
        missing = violations(pol, res({"Environment": "Development"}, **instance))
        self.assertEqual(
            missing,
            [
                Violation(
                    "dev-schedule",
                    "error",
                    "aws_instance.i",
                    "tag Schedule must be one of UkWorkingHours, AlwaysOn",
                )
            ],
        )
        wrong = violations(pol, res({"Environment": "Development", "Schedule": "Weekdays"}, **instance))
        self.assertEqual(
            wrong[0].message, "tag Schedule must be one of UkWorkingHours, AlwaysOn, found Weekdays"
        )

    def test_message_phrasing(self):
        cases = [
            (assert_tag("T", present=True), {}, "tag T must be present"),
            (assert_tag("T", present=False), {"T": "x"}, "tag T must be absent, found x"),
            (assert_tag("T", equals="a"), {"T": "b"}, "tag T must be a, found b"),
            (assert_tag("T", contains="a"), {"T": "b"}, "tag T must contain a, found b"),
            (assert_tag("T", starts_with=["a", "b"]), {"T": "c"}, "tag T must start with one of a, b, found c"),
            (assert_tag("T", ends_with="a", **{"not": True}), {"T": "xa"}, "tag T must not end with a, found xa"),
            (assert_tag("T", matches="^a"), {"T": "b"}, "tag T must match ^a, found b"),
        ]
        for step, tags, expected in cases:
            with self.subTest(expected=expected):
                self.assertEqual(violations(policy(rule(step)), res(tags))[0].message, expected)

    def test_every_failing_assert_is_reported(self):
        pol = policy(
            rule(assert_tag("A", present=True), assert_tag("B", present=True), name="both")
        )
        self.assertEqual([v.message for v in violations(pol, res({}))], [
            "tag A must be present",
            "tag B must be present",
        ])

    def test_filter_after_assert_still_gates_later_steps(self):
        pol = policy(
            rule(
                assert_tag("A", present=True),
                filter_tag("Environment", equals="Development"),
                assert_tag("B", present=True),
            )
        )
        self.assertEqual([v.message for v in violations(pol, res({"Environment": "Prod"}))],
                         ["tag A must be present"])
        self.assertEqual(
            [v.message for v in violations(pol, res({"Environment": "Development"}))],
            ["tag A must be present", "tag B must be present"],
        )

    def test_severity_is_carried_from_the_rule(self):
        pol = policy(rule(assert_tag("A", present=True), severity="warning"))
        self.assertEqual(violations(pol, res({}))[0].severity, "warning")


class NestingTest(unittest.TestCase):
    def ec2(self):
        return policy(
            rule(
                filter_type("aws_instance"),
                assert_tag("Own", present=True),
                name="ec2",
                rules=[
                    rule(assert_tag("Backup", present=True), name="backup"),
                    rule(
                        filter_tag("Environment", equals="Development"),
                        assert_tag("Schedule", present=True),
                        name="schedule",
                    ),
                ],
            )
        )

    def test_children_inherit_parent_filters(self):
        pol = self.ec2()
        self.assertEqual(violations(pol, res({}, rtype="aws_s3_bucket")), [])
        found = violations(pol, res({"Own": "1"}, rtype="aws_instance"))
        self.assertEqual([(v.rule, v.message) for v in found], [("ec2/backup", "tag Backup must be present")])

    def test_child_filters_apply_only_to_that_child(self):
        found = violations(
            self.ec2(), res({"Own": "1", "Backup": "1", "Environment": "Development"}, rtype="aws_instance")
        )
        self.assertEqual([v.rule for v in found], ["ec2/schedule"])

    def test_parent_asserts_run_for_the_parent_only(self):
        found = violations(self.ec2(), res({"Backup": "1"}, rtype="aws_instance"))
        self.assertEqual([v.rule for v in found], ["ec2"])


class UnknownValueTest(unittest.TestCase):
    def test_assert_on_unknown_tag_warns_instead_of_failing(self):
        pol = policy(rule(assert_tag("Team", present=True), name="needs-team"))
        found, unverified = check_resource(pol, res({}, unknown_tags=frozenset({"Team"})))
        self.assertEqual(found, [])
        self.assertEqual(
            [(u.rule, u.address, u.message) for u in unverified],
            [("needs-team", "aws_s3_bucket.b", "Team is unknown until apply")],
        )

    def test_whole_attribute_unknown(self):
        pol = policy(rule(assert_tag(["A", "B"], present=True)))
        found, unverified = check_resource(pol, res({"A": "1"}, all_unknown=True))
        self.assertEqual(found, [])
        self.assertEqual([u.message for u in unverified], ["B is unknown until apply"])

    def test_known_tags_are_still_checked_when_others_are_unknown(self):
        pol = policy(rule(assert_tag("Environment", **{"in": ["Production"]})))
        found, unverified = check_resource(
            pol, res({"Environment": "Nope"}, unknown_tags=frozenset({"Team"}))
        )
        self.assertEqual(len(found), 1)
        self.assertEqual(unverified, [])

    def test_filter_on_unknown_tag_skips_the_rule_with_a_warning(self):
        pol = policy(
            rule(filter_tag("Environment", equals="Development"), assert_tag("Schedule", present=True), name="r")
        )
        found, unverified = check_resource(pol, res({}, unknown_tags=frozenset({"Environment"})))
        self.assertEqual(found, [])
        self.assertEqual(
            [(u.rule, u.message) for u in unverified],
            [("r", "Environment is unknown until apply, so the rule was not evaluated")],
        )

    def test_filter_that_fails_on_a_known_key_wins_over_an_unknown_key(self):
        pol = policy(rule(filter_tag(["A", "B"], equals="x"), assert_tag("C", present=True)))
        found, unverified = check_resource(
            pol, res({"A": "nope"}, unknown_tags=frozenset({"B"}))
        )
        self.assertEqual((found, unverified), ([], []))

    def test_skip_reason_is_reported_and_nothing_is_checked(self):
        pol = policy(rule(assert_tag("A", present=True)))
        found, unverified = check_resource(pol, res({}, skip_reason="tags is not a map of tags, so it was not checked"))
        self.assertEqual(found, [])
        self.assertEqual(
            [(u.rule, u.message) for u in unverified],
            [("", "tags is not a map of tags, so it was not checked")],
        )


if __name__ == "__main__":
    unittest.main()
