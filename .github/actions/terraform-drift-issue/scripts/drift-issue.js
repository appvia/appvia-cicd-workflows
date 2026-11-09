'use strict';

// Opens, updates, or closes a single drift issue per environment. The marker comment is what
// makes the open/update path an upsert: without it a scheduled workflow would file a new issue on
// every run. A closed issue is never reopened — if drift recurs later, a brand-new issue is
// opened instead, since the marker lookup only ever considers currently-open issues.

const fs = require('fs');

const DEFAULT_MAX_PLAN_LENGTH = 55000;

// Pin the REST API version explicitly on every request. Without this, GitHub silently defaults to
// the 2022-11-28 version, which itself is scheduled for retirement (10 Mar 2028) and triggers an
// "is deprecated" notice on each call — pinning to that same default would just restate the
// soon-to-close-down version and keep the warning firing. 2026-03-10 is the current, not-yet-
// deprecated version; its documented breaking changes (rate-limit `rate` removal, team-creation
// `permission` removal, repo-content submodule typing, SARIF content-type fix,
// `use_squash_pr_title_as_default` removal) don't affect any field/parameter used here. Revisit
// this pin periodically as GitHub ships newer versions.
const API_HEADERS = { 'X-GitHub-Api-Version': '2026-03-10' };

const ANSI_PATTERN = /\x1b\[[0-9;]*m/g;

// Terraform's refresh/read chatter is always an unindented "<address>: <phrase>" line, optionally
// followed by a bracketed "[id=...]" / elapsed-time annotation; every line that's part of the
// actual diff/drift output is either indented or doesn't match that shape, so this reliably
// strips noise without touching drifted state or planned changes.
const PLAN_NOISE_LINE =
  /^\S.*: (?:Refreshing state\.\.\.|Still refreshing state\.\.\.|Reading\.\.\.|Read complete after .*?)(?: \[.*\])?$/;

function stripPlanNoise(text) {
  if (!text) return text;
  const kept = text
    .split('\n')
    .filter((line) => !PLAN_NOISE_LINE.test(line))
    .join('\n');
  // Collapse the blank-line runs left behind by removed lines.
  return kept.replace(/\n{3,}/g, '\n\n');
}

function readPlanOutput(path) {
  try {
    return stripPlanNoise(fs.readFileSync(path, 'utf8').replace(ANSI_PATTERN, ''));
  } catch (error) {
    if (error.code === 'ENOENT') return '';
    throw error;
  }
}

function markerFor(environment, root) {
  return root ? `<!-- drift-${root}-${environment} -->` : `<!-- drift-${environment} -->`;
}

// Capitalizes each hyphen/underscore-separated word, so compound names read naturally, e.g.
// "base-prd" -> "Base Prd" and, combined with a root, "base" + "prd" -> "Base Prd".
const titleCase = (value) =>
  value
    .split(/[-_]/)
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');

function buildIssueBody({ environment, root, planOutput, runUrl, maxPlanLength = DEFAULT_MAX_PLAN_LENGTH }) {
  let plan = planOutput || '';
  if (plan.length > maxPlanLength) {
    plan = `${plan.slice(0, maxPlanLength)}\n... (truncated)`;
  }
  const title = root ? `${titleCase(root)} ${titleCase(environment)}` : titleCase(environment);
  return (
    `${markerFor(environment, root)}\n### ⚠️ Infrastructure drift detected — \`${title}\`\n\n` +
    '`terraform plan` reported changes against the deployed state.\n\n' +
    `<details><summary>Plan output</summary>\n\n\`\`\`\n${plan}\n\`\`\`\n\n</details>\n\n` +
    `🔗 [Workflow run](${runUrl})`
  );
}

function buildResolvedComment({ runUrl }) {
  return (
    '✅ Drift has been resolved — a subsequent `terraform plan` found no outstanding changes ' +
    `(excluding any addresses covered by \`drift-exclusions-file\`).\n\n🔗 [Workflow run](${runUrl})`
  );
}

module.exports = async ({ github, context }) => {
  const environment = process.env.ENVIRONMENT;
  const root = process.env.ROOT || '';
  const hasDrift = process.env.HAS_DRIFT === 'true';
  const planOutputFile = process.env.PLAN_OUTPUT_FILE;
  const labels = (process.env.ISSUE_LABELS || 'drift')
    .split(',')
    .map((label) => label.trim())
    .filter(Boolean);

  const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
  const marker = markerFor(environment, root);

  const { data: issues } = await github.rest.issues.listForRepo({
    owner: context.repo.owner,
    repo: context.repo.repo,
    state: 'open',
    per_page: 100,
    headers: API_HEADERS,
  });

  const existing = issues.find((issue) => issue.body && issue.body.includes(marker));

  if (!hasDrift) {
    // No non-excluded drift this run. Close a previously-open issue with a resolution comment;
    // otherwise there's nothing to do. A closed issue is deliberately never reopened here — if
    // drift recurs later, a brand-new issue is opened instead (listForRepo only sees open issues).
    if (existing) {
      await github.rest.issues.createComment({
        owner: context.repo.owner,
        repo: context.repo.repo,
        issue_number: existing.number,
        body: buildResolvedComment({ runUrl }),
        headers: API_HEADERS,
      });
      await github.rest.issues.update({
        owner: context.repo.owner,
        repo: context.repo.repo,
        issue_number: existing.number,
        state: 'closed',
        state_reason: 'completed',
        headers: API_HEADERS,
      });
    }
    return;
  }

  const body = buildIssueBody({
    environment,
    root,
    planOutput: readPlanOutput(planOutputFile),
    runUrl,
  });
  // Computed once so the update path keeps an existing issue's title in sync with the same
  // title-casing used when the issue is first created.
  const title = `Terraform drift detected: ${root ? `${titleCase(root)} ${titleCase(environment)}` : titleCase(environment)}`;

  if (existing) {
    await github.rest.issues.update({
      owner: context.repo.owner,
      repo: context.repo.repo,
      issue_number: existing.number,
      title,
      body,
      headers: API_HEADERS,
    });
    return;
  }

  await github.rest.issues.create({
    owner: context.repo.owner,
    repo: context.repo.repo,
    title,
    body,
    labels,
    headers: API_HEADERS,
  });
};

module.exports.buildIssueBody = buildIssueBody;
module.exports.buildResolvedComment = buildResolvedComment;
module.exports.markerFor = markerFor;
module.exports.stripPlanNoise = stripPlanNoise;
module.exports.titleCase = titleCase;
