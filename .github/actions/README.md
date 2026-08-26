# Composite actions

Shared building blocks for the reusable workflows in `.github/workflows`. Each directory is one
composite action, referenced from a workflow as `uses: ./.github/actions/<name>`.

## Why local `uses:` works cross-repo

Reusable workflows in this repository are invoked from other repositories via `workflow_call`.
A relative `uses: ./.github/actions/...` inside such a workflow resolves against **this**
repository at the ref the consumer pinned — not against the consumer's checkout. Local composite
actions are therefore safe to use in every reusable workflow here.

## Where scripts live

Anything longer than a few lines of shell or JavaScript belongs in a file, not inline in YAML.
Inline blocks cannot be linted properly, cannot be unit tested, and are unreviewable in a diff.

```
.github/actions/<action-name>/
  action.yml
  scripts/
    do-thing.sh
    build-comment.js
```

Scripts are addressed through `$GITHUB_ACTION_PATH`, which the runner sets to the checked-out
action directory. Invoke them through `bash` rather than directly, so the action does not depend
on the executable bit surviving checkout on every platform:

```yaml
- name: Do the thing
  shell: bash
  env:
    WORKING_DIR: ${{ inputs.working-directory }}
  run: bash "$GITHUB_ACTION_PATH/scripts/do-thing.sh"
```

Do **not** put these under the repository-root `scripts/` directory and `curl` them at runtime.
That directory is for developer-facing utilities. Fetching a script from `main` at runtime
decouples it from the workflow ref, so a change there can break a consumer pinned to a tag.

### `actions/github-script`

Inside a nested action, `$GITHUB_ACTION_PATH` refers to *that* action, so `github-script` cannot
see ours. Capture the path first:

```yaml
- name: Export action path
  shell: bash
  run: echo "COMPOSITE_ACTION_PATH=$GITHUB_ACTION_PATH" >> "$GITHUB_ENV"

- name: Post comment
  uses: actions/github-script@3a2844b7e9c422d3c10d287c895573f7108da1b3 # v9
  with:
    script: |
      const run = require(`${process.env.COMPOSITE_ACTION_PATH}/scripts/build-comment.js`);
      await run({ github, context, core });
```

Write those modules as a single exported async function so they can be unit tested against
fixtures without a runner:

```js
module.exports = async ({ github, context, core }) => { /* ... */ };
```

## Conventions

- Every `run:` step must set `shell: bash` explicitly — composite actions have no default shell.
- Pass caller-supplied values through `env:`, never by interpolating `${{ inputs.* }}` into a
  `run:` body. Interpolation splices untrusted text into the script before bash sees it, which is
  a command-injection path; `env:` makes it data.
- Start every script with `set -euo pipefail`.
- Avoid `[ -z "$X" ] && X=...` as a statement: it returns 1 when `X` is already set, which
  `set -e` treats as a failure. Use an explicit `if`.
- Build command arguments as bash **arrays**, not strings, so optional flags cannot word-split.
- Pin third-party actions to a full commit SHA with a `# vN` comment, matching the SHAs already
  used elsewhere in this repository.
- Name actions `{tool}-{operation}`. Prefix with `azure-` only when the action is genuinely
  cloud-specific; keep cloud-agnostic ones unprefixed so other engines can adopt them.

## Linting

`.github/workflows/validate.yml` runs, on every PR:

| Job | Covers |
|---|---|
| `actionlint` | workflow and action YAML, plus shellcheck over inline `run:` blocks |
| `shellcheck` | `.github/actions/**/scripts/*.sh`, with no ignored rules |
| `jscheck` | `node --check` over `.github/actions/**/scripts/*.js` |
| `yamllint` | everything under `.github` |
| `workflow-baseline` | regenerates `tests/azure/baseline` and fails if it is stale |
