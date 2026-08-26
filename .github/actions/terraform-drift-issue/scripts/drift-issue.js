'use strict';

// Opens or updates a single drift issue per environment. The marker comment is what makes this an
// upsert: without it a scheduled workflow would file a new issue on every run.

const fs = require('fs');

const DEFAULT_MAX_PLAN_LENGTH = 55000;

function readPlanOutput(path) {
  try {
    return fs.readFileSync(path, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') return '';
    throw error;
  }
}

function markerFor(environment) {
  return `<!-- drift-${environment} -->`;
}

function buildIssueBody({ environment, planOutput, runUrl, maxPlanLength = DEFAULT_MAX_PLAN_LENGTH }) {
  let plan = planOutput || '';
  if (plan.length > maxPlanLength) {
    plan = `${plan.slice(0, maxPlanLength)}\n... (truncated)`;
  }
  return (
    `${markerFor(environment)}\n### ⚠️ Infrastructure drift detected — \`${environment}\`\n\n` +
    '`terraform plan` reported changes against the deployed state.\n\n' +
    `<details><summary>Plan output</summary>\n\n\`\`\`\n${plan}\n\`\`\`\n\n</details>\n\n` +
    `🔗 [Workflow run](${runUrl})`
  );
}

module.exports = async ({ github, context }) => {
  const environment = process.env.ENVIRONMENT;
  const planOutputFile = process.env.PLAN_OUTPUT_FILE;
  const labels = (process.env.ISSUE_LABELS || 'drift')
    .split(',')
    .map((label) => label.trim())
    .filter(Boolean);

  const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
  const body = buildIssueBody({
    environment,
    planOutput: readPlanOutput(planOutputFile),
    runUrl,
  });

  const { data: issues } = await github.rest.issues.listForRepo({
    owner: context.repo.owner,
    repo: context.repo.repo,
    state: 'open',
    per_page: 100,
  });

  const marker = markerFor(environment);
  const existing = issues.find((issue) => issue.body && issue.body.includes(marker));

  if (existing) {
    await github.rest.issues.update({
      owner: context.repo.owner,
      repo: context.repo.repo,
      issue_number: existing.number,
      body,
    });
    return;
  }

  await github.rest.issues.create({
    owner: context.repo.owner,
    repo: context.repo.repo,
    title: `Terraform drift detected: ${environment}`,
    body,
    labels,
  });
};

module.exports.buildIssueBody = buildIssueBody;
module.exports.markerFor = markerFor;
