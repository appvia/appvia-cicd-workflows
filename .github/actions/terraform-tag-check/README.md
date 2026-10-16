# terraform-tag-check

Checks the resources a Terraform plan will **create or update** against a tagging policy written as YAML rules. Adding or changing a rule is a configuration change: no code is involved.

- [How it runs](#how-it-runs)
- [Policy file](#policy-file)
- [Rules and steps](#rules-and-steps)
- [Conditions](#conditions)
  - [Targets](#targets)
  - [Operators](#operators)
  - [Inverting with `not`](#inverting-with-not)
- [Filters and asserts](#filters-and-asserts)
- [Nested rules](#nested-rules)
- [Severity](#severity)
- [Values unknown until apply](#values-unknown-until-apply)
- [Recipes](#recipes)
- [Editing the shipped policy](#editing-the-shipped-policy)
- [Errors in the policy file](#errors-in-the-policy-file)
- [Output](#output)
- [Developing](#developing)

## How it runs

The action reads one plan (`terraform show -json`), or every `*.json` file under a directory, and applies each rule to each resource in it.

A resource is checked when it is a managed resource (not a data source) with a `create` or `update` action, its type is not in `exclude_resource_types`, and it has a `tags_all` or `tags` attribute. `tags_all` wins when both exist, because it includes the provider's `default_tags`. Tags may be a map, or the list of `{key, value}` objects some providers (such as awscc) use. Anything else is reported as not checkable.

```yaml
- uses: appvia/appvia-cicd-workflows/.github/actions/terraform-tag-check@main
  with:
    mode: enforce                     # or audit: report violations as warnings, never fail
    plan-json: tfplan.json            # a file, or a directory searched recursively
    working-directory: .              # plan-json is relative to this
    policy-file: ""                   # defaults to config/tagging-policy.yaml in this repository
```

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `mode` | no | `enforce` | `enforce` fails on a violation; `audit` annotates every finding, and any error running the check, as a warning and exits `0` |
| `plan-json` | yes | | A plan JSON file, or a directory searched recursively for `*.json` plan files |
| `policy-file` | no | `config/tagging-policy.yaml` | The tagging policy |
| `working-directory` | no | `.` | The directory `plan-json` is relative to |

| Output | Description |
| ------ | ----------- |
| `result` | `success`, `failure`, or `warning` when the check would have failed in audit mode |
| `violations` | The number of resources with at least one `error`-severity violation |

Exit codes: `0` compliant (always `0` in audit mode), `1` policy violations, `2` usage or policy error (an unreadable plan, an invalid policy, a crash). Requires Python 3 and PyYAML; PyYAML is installed if it is missing.

## Policy file

The shipped policy is [config/tagging-policy.yaml](../../../config/tagging-policy.yaml).

```yaml
version: 1                        # required, must be 1
exclude_resource_types: []        # resource types that are never checked
rules:                            # required, may be empty
  - name: required-tags
    steps:
      - assert: {tag: [Environment, Product, GitRepo], present: true}
```

Only `version`, `exclude_resource_types` and `rules` are allowed at the top level.

## Rules and steps

A rule is an ordered **chain of steps**. Every resource is run through every rule.

| Field | Required | Meaning |
| ----- | -------- | ------- |
| `name` | yes | Shown in annotations and the summary. A non-empty string without `/`, unique across the file (nested rules by full path) |
| `steps` | yes | A non-empty list of [steps](#filters-and-asserts) |
| `description` | no | Shown in the job summary |
| `severity` | no | `error` (default) or `warning`; see [Severity](#severity) |
| `rules` | no | [Nested rules](#nested-rules) |

## Conditions

Every step holds one condition. A condition names a **target** (what to look at) and, for tags, an **operator** (how to compare it).

```yaml
- assert: {tag: Schedule, in: [UkWorkingHours, AlwaysOn]}
#                ^ target        ^ operator and operand
```

### Targets

| Target | Looks at | Form |
| ------ | -------- | ---- |
| `tag` | The value of a tag | `tag: Key` or `tag: [KeyA, KeyB]`, plus exactly one [operator](#operators) |
| `type` | The resource type, such as `aws_s3_bucket` | `type: value`, `type: [a, b]`, or `type: {operator: value}` |
| `address` | The resource address, such as `module.app.aws_s3_bucket.logs[0]` | The same forms as `type` |

For `type` and `address` the value is the operand, and the comparison is `equals`. Use the mapping form for any other operator:

```yaml
- filter: {type: aws_s3_bucket}                      # equals
- filter: {type: [aws_instance, aws_ebs_volume]}     # equals any of
- filter: {type: {starts_with: aws_s3_}}             # another operator
- filter: {address: {matches: '^module\.legacy\.'}}
```

`present` is not available for `type` or `address`, and operators cannot be written beside them (`{type: x, equals: y}` is an error).

With a **list of tag keys**, the condition is evaluated for each key on its own. In a `filter` every key must satisfy it. In an `assert` each key that fails produces its own violation.

### Operators

| Operator | Operand | Holds when |
| -------- | ------- | ---------- |
| `present` | `true` or `false` | `true`: the tag exists with a non-empty value. `false`: the tag is absent or empty |
| `equals` | string or list | The value equals the operand, or any item of a list |
| `in` | string or list | Identical to `equals`; use whichever reads better |
| `contains` | string or list | The value contains the operand as a substring, or any item of a list |
| `starts_with` | string or list | The value starts with the operand, or any item of a list |
| `ends_with` | string or list | The value ends with the operand, or any item of a list |
| `matches` | string or list | A regular expression matches **anywhere** in the value, or any pattern of a list |
| `is_pascal` | `true` or `false` | `true`: PascalCase, one or more words that each start with an uppercase letter followed by at least one lowercase letter or digit (`CostCentre`, `Team2`; `AWSAccount` fails). `false`: it is not |
| `is_camel` | `true` or `false` | camelCase: `costCentre`, `cost` |
| `is_snake` | `true` or `false` | snake_case: lowercase letters and digits, words joined by single underscores (`cost_centre`) |
| `is_kebab` | `true` or `false` | kebab-case: lowercase letters and digits, words joined by single hyphens (`cost-centre`) |
| `is_lower` | `true` or `false` | Lowercase letters and digits only (`prod1`) |
| `is_upper` | `true` or `false` | Uppercase letters and digits only (`PROD1`) |

How they behave:

- **A list operand means "any of"**, for every operator except `present` and the `is_*` case operators.
- **Comparison is case-sensitive.** `Production` does not equal `production`.
- **An empty tag value counts as absent**, so `present: true` fails for a tag set to `""`.
- **A missing tag fails every operator** except `present: false`. This is checked before `not` is applied.
- **A tag whose value is not a string** (a number, say) never satisfies `contains`, `starts_with`, `ends_with` or `matches`; it fails them without raising an error. The `is_*` operators with `true` fail for them too.
- **`matches` uses Python regular expression syntax** and `re.search`, so the pattern is not anchored. Write `^` and `$` for a whole-value match: `'^[a-z]+$'` rather than `'[a-z]+'`. Patterns are compiled when the policy loads, so an invalid one is a policy error, not a surprise mid-pipeline.
- **Operands must be strings.** YAML reads `yes`, `no`, `on`, `off`, `true`, and bare numbers as booleans or numbers, which is an error. Quote them: `equals: "yes"`, `equals: "1"`. Prefer single quotes for regular expressions so backslashes are literal.

### Inverting with `not`

Add `not: true` to any condition, in a `filter` or an `assert`, to invert it.

```yaml
# Environment must not be Production
- assert: {tag: Environment, equals: Production, not: true}

# Environment must not equal the literal PRODUCT_NAME placeholder
- assert: {tag: Environment, equals: PRODUCT_NAME, not: true}

# Skip anything under module.legacy
- filter: {address: {starts_with: module.legacy}, not: true}

# The tag must be absent
- assert: {tag: DeprecatedOwner, present: false}
```

Because a missing tag fails every operator before `not` is applied, `not: true` **holds** for a missing tag. `{tag: Environment, equals: Production, not: true}` passes for a resource with no `Environment` at all. Pair it with a `present: true` assert if a missing tag should fail too.

## Filters and asserts

Each step is a mapping with exactly one key, `filter` or `assert`, whose value is a condition.

| Step | If the condition holds | If it does not hold |
| ---- | ---------------------- | ------------------- |
| `filter` | The chain continues | The chain stops for this resource, **silently**. The rule does not apply to it |
| `assert` | The chain continues | A **violation** is recorded and the chain **continues**, so every failing assert is reported |

Steps run in order. A rule with no `filter` applies to every resource. A `filter` partway through a chain gates only the steps after it.

```yaml
- name: dev-ec2-schedule
  description: Development EC2 instances declare when they run
  steps:
    - filter: {type: aws_instance}                      # only EC2 instances
    - filter: {tag: Environment, equals: Development}   # ...in Development
    - assert: {tag: Schedule, in: [UkWorkingHours, AlwaysOn]}
```

Violations read like `tag Schedule must be one of UkWorkingHours, AlwaysOn, found Weekdays` or `tag DataClassification must be present`, and carry the rule name and resource address.

## Nested rules

A rule may contain child `rules:`. Children **inherit the parent's `filter` steps** (and only those), so a shared filter is written once. The parent's own `assert` steps apply to the parent only, and a child's filters apply to that child only.

```yaml
- name: ec2
  steps:
    - filter: {type: aws_instance}
  rules:
    - name: backup
      steps:
        - assert: {tag: Backup, in: [Daily, Weekly]}
    - name: schedule
      steps:
        - filter: {tag: Environment, equals: Development}
        - assert: {tag: Schedule, in: [UkWorkingHours, AlwaysOn]}
```

Children are reported as `parent/child` (`ec2/backup`, `ec2/schedule`). Names only need to be unique among siblings, and nesting can go as deep as you like.

## Severity

`severity: error` (the default) fails the job. `severity: warning` reports the violation as a warning annotation and in the summary but does not fail the job and is not counted in the `violations` output, which suits rolling out a new rule before enforcing it.

```yaml
- name: owner-email
  severity: warning
  steps:
    - assert: {tag: Owner, matches: '^[^@\s]+@example\.com$'}
```

## Values unknown until apply

Some tag values only exist after apply. A value Terraform cannot know yet is never a violation:

- An `assert` on an unknown tag produces a warning: `Team is unknown until apply`.
- A `filter` on an unknown tag cannot be decided, so the rule is skipped for that resource with a warning: `Environment is unknown until apply, so the rule was not evaluated`.
- When the whole tags attribute is unknown, tags in the known `tags` attribute are still checked and any other key is treated as unknown.
- A resource whose tags are not a map (or a list of `{key, value}` objects) is reported as not checked.

Warnings are annotated and listed under "Not verifiable at plan time" in the summary, and never fail the job.

## Recipes

```yaml
rules:
  # Production resources carry a four-digit cost centre
  - name: prod-cost-centre
    steps:
      - filter: {tag: Environment, equals: Production}
      - assert: {tag: CostCentre, matches: '^[0-9]{4}$'}

  # S3 buckets: a data classification, from a fixed list
  - name: s3-data-classification
    steps:
      - filter: {type: aws_s3_bucket}
      - assert: {tag: DataClassification, in: [Public, Internal, Confidential, Restricted]}

  # Anything S3-related (buckets, policies, ...) carries a Team
  - name: s3-team
    steps:
      - filter: {type: {starts_with: aws_s3_}}
      - assert: {tag: Team, present: true}

  # Resource names follow a convention
  - name: name-convention
    steps:
      - assert: {tag: Name, matches: '^[a-z][a-z0-9-]*$'}

  # No tag may use the literal placeholder
  - name: no-placeholder-application
    steps:
      - assert: {tag: [Product, Team], equals: CHANGE_ME, not: true}

  # GitRepo points at the organisation
  - name: git-repo-org
    steps:
      - assert: {tag: GitRepo, starts_with: appvia/}

  # Everything except legacy modules needs a Backup tag
  - name: backup
    steps:
      - filter: {address: {starts_with: module.legacy}, not: true}
      - assert: {tag: Backup, present: true}
```

## Editing the shipped policy

The shipped policy is [config/tagging-policy.yaml](../../../config/tagging-policy.yaml). Its tests (`tests/test_config.py`) pin the exact messages each rule produces, and require the `required-tags` rule to list the same keys as the tflint `aws_resource_missing_tags` rule in [config/.tflint.hcl](../../../config/.tflint.hcl). After changing it, run the tests and update whichever of those no longer match.

## Errors in the policy file

The policy is validated before any plan is read. A problem exits with code 2 and an `::error` annotation that names the rule. Examples of what is rejected: an unsupported `version`, an unknown field, a duplicate or `/`-containing rule name, empty `steps`, a step with both or neither of `filter` and `assert`, a condition with no target or more than one, a `tag` condition without exactly one operator, an operator beside a `type` or `address` target, an unknown operator, an operand of the wrong type (including unquoted `yes` or `1`), an invalid `severity`, and a `matches` pattern that is not a valid regular expression.

## Output

- **Annotations:** one `::error` (or `::warning` for warning-severity rules and unverifiable values) per finding, naming the resource, plan file, rule and message.
- **Job summary:** a table of violations (file, address, rule, message), the list of values not verifiable at plan time, and the policy's rules and descriptions.
- **Step outputs:** `violations`, the count of resources with an `error`-severity violation, and `result`.
- **Audit mode:** every annotation is a `::warning` and the job summary is headed with an audit notice.

## Developing

| File | Responsibility |
| ---- | -------------- |
| `check.sh` | Entry point run by `action.yml`; makes sure PyYAML is available, runs `check.py`, and applies the mode to the exit code and `result` output |
| `check.py` | Reads the environment, runs every plan file, writes output and the exit code |
| `plan.py` | Turns a plan into the resources to check |
| `policy.py` | Loads and validates the YAML policy |
| `engine.py` | The operators and the rule-chain evaluator |
| `report.py` | Annotations and the job summary |

Run the tests from the repository root (`make test-tag-check` runs the same thing):

```shell
bash .github/actions/terraform-tag-check/tests/run.sh
```

To add an operator, add its name to `OPERATORS` in `policy.py` and a comparison function to `COMPARISONS` in `engine.py`, with a test case in `tests/test_engine.py`.
