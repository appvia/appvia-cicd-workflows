#!/usr/bin/env node
'use strict';

// Unit tests for the JavaScript extracted out of the Azure workflows. Deliberately dependency-free
// and runnable with a bare `node tests/azure/run-tests.js`, matching the shell-only style of
// tests/promotion.

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const ACTIONS = path.join(__dirname, '..', '..', '.github', 'actions');
const planReport = require(path.join(ACTIONS, 'terraform-plan-report', 'scripts', 'plan-report.js'));
const buildComment = require(path.join(ACTIONS, 'terraform-plan-comment', 'scripts', 'build-comment.js'));
const driftIssue = require(path.join(ACTIONS, 'terraform-drift-issue', 'scripts', 'drift-issue.js'));

const tests = [];
const test = (name, fn) => tests.push({ name, fn });

// --- terraform-checkov-scan ------------------------------------------------

test('Checkov scan fails when its configuration file is missing', () => {
  const action = fs.readFileSync(path.join(ACTIONS, 'terraform-checkov-scan', 'action.yml'), 'utf8');
  assert.match(action, /Checkov configuration file does not exist/);
  assert.match(action, /\[\[ ! -f "\$CONFIG_FILE" \]\]/);
  assert.ok(!action.includes('echo "{}" >"${CONFIG_FILE}"'));
  assert.ok(!action.includes('framework:'), 'frameworks must be configured in .checkov.yml');
});

test('Azure workflow exposes Checkov SARIF upload as an opt-out', () => {
  const workflow = fs.readFileSync(path.join(__dirname, '..', '..', '.github', 'workflows', 'terraform-plan-and-apply-azure.yml'), 'utf8');
  assert.match(workflow, /upload-sarif:\r?\n\s+description: "Upload Checkov SARIF results to GitHub Security"/);
  assert.match(workflow, /upload-sarif: \$\{\{ inputs\.upload-sarif \}\}/);
});

// --- plan-report ------------------------------------------------------------

const PLAN = {
  resource_changes: [
    { address: 'azurerm_resource_group.a', type: 'azurerm_resource_group', change: { actions: ['create'], after: { name: 'a' } } },
    { address: 'azurerm_resource_group.b', type: 'azurerm_resource_group', change: { actions: ['no-op'] } },
    { address: 'azurerm_storage_account.c', type: 'azurerm_storage_account', change: { actions: ['delete', 'create'] } },
    { address: 'azurerm_subnet.d', type: 'azurerm_subnet', change: { actions: ['update'] } },
    { address: 'azurerm_subnet.e', type: 'azurerm_subnet', change: { actions: ['delete'], before: { id: 'e' } } },
  ],
};

test('plan-report drops no-op resources', () => {
  assert.strictEqual(planReport.changedResources(PLAN).length, 4);
});

test('plan-report counts a delete+create as a replace, not both', () => {
  const counts = planReport.countActions(planReport.changedResources(PLAN));
  assert.deepStrictEqual(counts, { create: 1, update: 1, delete: 1, replace: 1 });
});

test('plan-report tolerates a plan with no resource_changes', () => {
  assert.deepStrictEqual(planReport.changedResources({}), []);
  assert.match(planReport.renderPlanReport({}), /No changes/);
});

test('plan-report escapes HTML in resource addresses', () => {
  const html = planReport.renderPlanReport({
    resource_changes: [{ address: '<script>x</script>', type: 't', change: { actions: ['create'], after: {} } }],
  });
  assert.ok(!html.includes('<script>x</script>'), 'raw script tag must not survive');
  assert.ok(html.includes('&lt;script&gt;'));
});

test('plan summary lists action counts and resource addresses without values', () => {
  const summary = planReport.renderPlanSummary(PLAN);
  assert.match(summary, /\| 1 \| 1 \| 1 \| 1 \|/);
  assert.match(summary, /azurerm_resource_group\.a/);
  assert.ok(!summary.includes('"name": "a"'));
});

test('plan summary reports no changes explicitly', () => {
  assert.match(planReport.renderPlanSummary({}), /No infrastructure changes are planned/);
});

test('plan summary escapes Markdown table characters in resource metadata', () => {
  const summary = planReport.renderPlanSummary({
    resource_changes: [{ address: 'module.x["a|b`c"]', type: 'type|name', change: { actions: ['create'] } }],
  });
  assert.match(summary, /a\\\|b\\`c/);
  assert.match(summary, /type\\\|name/);
});

// --- build-comment ----------------------------------------------------------

test('truncate leaves short text alone and strips ANSI', () => {
  const result = buildComment.truncate('\u001b[31mred\u001b[0m', 100);
  assert.deepStrictEqual(result, { content: 'red', truncated: false });
});

test('truncate marks long text as truncated', () => {
  const result = buildComment.truncate('x'.repeat(50), 10);
  assert.strictEqual(result.truncated, true);
  assert.ok(result.content.endsWith('Output truncated...'));
});

test('formatOpaOutput summarises failures and warnings', () => {
  const raw = JSON.stringify([
    { namespace: 'main', failures: [{ msg: 'no tags' }], warnings: [{ msg: 'large sku' }] },
  ]);
  const output = buildComment.formatOpaOutput(raw);
  assert.match(output, /Policy failures:/);
  assert.match(output, /no tags/);
  assert.match(output, /Policy warnings:/);
  assert.match(output, /large sku/);
});

test('formatOpaOutput reports a clean run', () => {
  assert.match(buildComment.formatOpaOutput('[]'), /No policy violations/);
});

test('formatOpaOutput falls back to raw text when the output is not JSON', () => {
  assert.strictEqual(buildComment.formatOpaOutput('conftest exploded'), 'conftest exploded');
  assert.strictEqual(buildComment.formatOpaOutput(''), 'No output');
});

test('detailSection uses the skipped message rather than the text', () => {
  const section = buildComment.detailSection('x', 'Title', 'ignored', 'skipped', 100, 'url', '_nope_');
  assert.match(section, /_nope_/);
  assert.ok(!section.includes('ignored'));
});

const OUTCOMES = {
  environment: 'dev',
  commitlint: 'success',
  pre_commit: 'success',
  fmt_check: 'success',
  tflint: 'success',
  init: 'success',
  validate: 'success',
  plan: 'success',
  plan_json: 'success',
  plan_exit: '2',
  checkov: 'success',
  opa_local: 'success',
  infracost: 'skipped',
};

const commentOptions = (overrides = {}) => ({
  artifactUrl: 'https://example.test/artifact',
  runUrl: 'https://example.test/run',
  actor: 'octocat',
  eventName: 'pull_request',
  readFile: () => '',
  ...overrides,
});

test('buildBody marks a clean run with changes as overall OK', () => {
  const body = buildComment.buildBody(OUTCOMES, commentOptions());
  assert.match(body, /Validate and Plan Results - Dev ✅/);
  assert.match(body, /Changes detected/);
});

test('buildBody fails overall when a gated check failed', () => {
  const body = buildComment.buildBody({ ...OUTCOMES, checkov: 'failure' }, commentOptions());
  assert.match(body, /Validate and Plan Results - Dev ❌/);
});

test('buildBody fails overall when pre-commit failed', () => {
  const body = buildComment.buildBody({ ...OUTCOMES, pre_commit: 'failure' }, commentOptions());
  assert.match(body, /Validate and Plan Results - Dev ❌/);
});

test('buildBody fails overall when the plan errored', () => {
  const body = buildComment.buildBody({ ...OUTCOMES, plan_exit: '1' }, commentOptions());
  assert.match(body, /Validate and Plan Results - Dev ❌/);
  assert.match(body, /`Error`/);
});

test('buildBody includes an environment-scoped marker', () => {
  const body = buildComment.buildBody(OUTCOMES, commentOptions());
  assert.ok(body.startsWith(buildComment.markerFor('dev')));
  assert.notStrictEqual(buildComment.markerFor('dev'), buildComment.markerFor('prd'));
});

test('buildBody renders a pre-commit row', () => {
  const body = buildComment.buildBody(OUTCOMES, commentOptions());
  assert.match(body, /\*\*Pre-commit\*\*/);
});

test('enforceLimit keeps the footer when it truncates', () => {
  // Exercised directly: the per-section budgets in buildBody mean a real body cannot reach the
  // overall comment limit, so this guard only ever fires on unexpected input.
  const footer = '\n*🧑 **Pusher:** @octocat, **Action:** `pull_request`*\n*🔗 **Workflow Run:** [u](u)*';
  const body = 'x'.repeat(buildComment.MAX_COMMENT_LENGTH + 5000) + footer;
  const limited = buildComment.enforceLimit(body, 'https://example.test/run');
  assert.ok(limited.length <= buildComment.MAX_COMMENT_LENGTH, `length was ${limited.length}`);
  assert.match(limited, /comment truncated/);
  assert.ok(limited.endsWith(footer), 'footer must survive truncation');
});

test('enforceLimit leaves a short body untouched', () => {
  const body = buildComment.buildBody(OUTCOMES, commentOptions());
  assert.strictEqual(buildComment.enforceLimit(body, 'https://example.test/run'), body);
});

// --- drift-issue ------------------------------------------------------------

test('drift issue body carries an environment-scoped marker', () => {
  const body = driftIssue.buildIssueBody({ environment: 'prd', planOutput: 'changes', runUrl: 'u' });
  assert.ok(body.startsWith('<!-- drift-prd -->'));
  assert.match(body, /changes/);
});

test('drift issue truncates a very long plan', () => {
  const body = driftIssue.buildIssueBody({
    environment: 'dev',
    planOutput: 'z'.repeat(200),
    runUrl: 'u',
    maxPlanLength: 50,
  });
  assert.match(body, /\(truncated\)/);
});

// --- runner -----------------------------------------------------------------

let failed = 0;
for (const { name, fn } of tests) {
  try {
    fn();
    console.log(`ok   ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`FAIL ${name}`);
    console.error(`     ${error.message}`);
  }
}

console.log(`\n${tests.length - failed}/${tests.length} passed`);
process.exit(failed === 0 ? 0 : 1);
