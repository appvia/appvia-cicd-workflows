'use strict';

// Builds the per-environment "Validate and Plan" pull-request comment from the outcome JSON and
// log files produced by the plan job. Upserted by a hidden marker so repeated pushes update one
// comment per environment rather than appending, and so callers that fan out over environments
// with strategy.matrix get one comment per leg.

const fs = require('fs');
const path = require('path');

const MAX_COMMENT_LENGTH = 65500;

// Per-section budgets, so one enormous plan cannot crowd out every other section.
const LIMITS = {
  commitlint: 1500,
  pre_commit: 3000,
  fmt_check: 1500,
  tflint: 2000,
  init: 3000,
  checkov: 3000,
  opa_local: 2000,
  infracost: 2000,
  plan: 40000,
};

const ANSI_PATTERN = /\x1b\[[0-9;]*m/g;

function makeReader(directory) {
  return (file) => {
    try {
      return fs.readFileSync(path.join(directory, file), 'utf8');
    } catch (error) {
      if (error.code === 'ENOENT') return '';
      throw error;
    }
  };
}

const statusEmoji = (outcome) => {
  if (outcome === 'success') return '✅';
  if (outcome === 'failure') return '❌';
  if (outcome === 'skipped') return '⏭️';
  return '⚪';
};

const label = (outcome) => {
  if (outcome === 'success') return 'Pass';
  if (outcome === 'failure') return 'Fail';
  if (outcome === 'skipped') return 'Skipped';
  return '—';
};

function truncate(text, max) {
  if (!text) return { content: 'No output', truncated: false };
  const clean = text.replace(ANSI_PATTERN, '');
  if (clean.length <= max) return { content: clean, truncated: false };
  return { content: `${clean.slice(0, max)}\n\nOutput truncated...`, truncated: true };
}

function detailSection(emoji, title, text, outcome, max, runUrl, skippedMessage = '_Step was skipped_') {
  let content;
  let truncated = false;

  if (outcome === 'skipped') {
    content = skippedMessage;
  } else if (!text || !text.trim()) {
    content = 'No output';
  } else {
    ({ content, truncated } = truncate(text, max));
  }

  let section = `<details><summary>${emoji} <b>${title}</b></summary>\n\n\`\`\`\n${content}\n\`\`\`\n\n`;
  if (truncated) section += `🔗 [View full output in raw logs](${runUrl})\n\n`;
  return `${section}</details>\n\n`;
}

function formatOpaOutput(rawText) {
  let results;
  try {
    results = JSON.parse(rawText);
  } catch {
    return rawText && rawText.trim() ? rawText : 'No output';
  }

  if (!Array.isArray(results) || results.length === 0) return '✅ No policy violations detected.';

  const failures = results.flatMap((r) => (r.failures || []).map((f) => `[${r.namespace}] ${f.msg}`));
  const warnings = results.flatMap((r) => (r.warnings || []).map((w) => `[${r.namespace}] ${w.msg}`));
  if (!failures.length && !warnings.length) return '✅ No policy violations detected.';

  let output = '';
  if (failures.length) output += `Policy failures:\n${failures.map((m) => `  ✗ ${m}`).join('\n')}`;
  if (warnings.length) {
    if (output) output += '\n\n';
    output += `Policy warnings:\n${warnings.map((m) => `  ⚠ ${m}`).join('\n')}`;
  }
  return output;
}

const markerFor = (environment) => `<!-- terraform-plan-${environment} -->`;

const GATE_KEYS = [
  'pre_commit',
  'fmt_check',
  'tflint',
  'init',
  'validate',
  'plan_json',
  'checkov',
  'opa_local',
];

function buildBody(env, { artifactUrl, runUrl, actor, eventName, readFile }) {
  const environment = env.environment;
  const overallOk =
    GATE_KEYS.every((key) => env[key] === 'success' || env[key] === 'skipped') && env.plan_exit !== '1';

  const title = environment.charAt(0).toUpperCase() + environment.slice(1);
  const planExit = env.plan_exit != null ? String(env.plan_exit) : '';
  const planIcon = planExit === '0' ? '✅' : planExit === '2' ? '⚠️' : '❌';
  const planLabel =
    planExit === '0'
      ? 'No changes'
      : planExit === '2'
        ? 'Changes detected'
        : planExit === '1'
          ? 'Error'
          : label(env.plan);
  const infracostIcon = env.infracost === 'success' ? 'ℹ️' : statusEmoji(env.infracost);
  const infracostLabel = env.infracost === 'success' ? 'Review estimate' : label(env.infracost);

  let body = `${markerFor(environment)}\n# 🌍 Validate and Plan Results - ${title} ${overallOk ? '✅' : '❌'}\n\n`;
  body += '| Check | Result |\n|---|---|\n';
  body += `| 📝 **Commitlint** | ${statusEmoji(env.commitlint)} \`${label(env.commitlint)}\` |\n`;
  body += `| 🪝 **Pre-commit** | ${statusEmoji(env.pre_commit)} \`${label(env.pre_commit)}\` |\n`;
  body += `| 📐 **Terraform Format** | ${statusEmoji(env.fmt_check)} \`${label(env.fmt_check)}\` |\n`;
  body += `| 🔧 **TFLint** | ${statusEmoji(env.tflint)} \`${label(env.tflint)}\` |\n`;
  body += `| ⚙️ **Terraform Init** | ${statusEmoji(env.init)} \`${label(env.init)}\` |\n`;
  body += `| 🤖 **Terraform Validate** | ${statusEmoji(env.validate)} \`${label(env.validate)}\` |\n`;
  body += `| 📖 **Terraform Plan** | ${planIcon} \`${planLabel}\` |\n`;
  body += `| 🔒 **Checkov** | ${statusEmoji(env.checkov)} \`${label(env.checkov)}\` |\n`;
  body += `| 🔍 **OPA** | ${statusEmoji(env.opa_local)} \`${label(env.opa_local)}\` |\n`;
  body += `| 💰 **Infracost** | ${infracostIcon} \`${infracostLabel}\` |\n\n`;

  body += detailSection('📝', 'Commitlint', readFile(`commitlint_output_${environment}.txt`), env.commitlint, LIMITS.commitlint, runUrl);
  body += detailSection('🪝', 'Pre-commit', readFile(`pre_commit_output_${environment}.txt`), env.pre_commit, LIMITS.pre_commit, runUrl);
  body += detailSection('📐', 'Terraform Format', readFile(`fmt_check_output_${environment}.txt`), env.fmt_check, LIMITS.fmt_check, runUrl);
  body += detailSection('🔧', 'TFLint', readFile(`tflint_output_${environment}.txt`), env.tflint, LIMITS.tflint, runUrl);
  body += detailSection('⚙️', 'Terraform Init', readFile(`init_output_${environment}.txt`), env.init, LIMITS.init, runUrl);

  const planClean = (readFile(`plan_output_${environment}.txt`) || '').replace(ANSI_PATTERN, '');
  body += '<details><summary>📖 <b>Terraform Plan</b></summary>\n\n';
  if (artifactUrl) body += `📊 **[Download results ZIP (human-readable HTML plan)](${artifactUrl})**\n\n`;
  if (!planClean) {
    body += 'No output\n\n';
  } else if (planClean.length > LIMITS.plan) {
    body += `\`\`\`\nOutput truncated...\n\`\`\`\n\n🔗 [View full output in raw logs](${runUrl})\n\n`;
  } else {
    body += `\`\`\`\n${planClean}\n\`\`\`\n\n`;
  }
  body += '</details>\n\n';

  body += detailSection('🔒', 'Checkov', readFile(`checkov_output_${environment}.txt`), env.checkov, LIMITS.checkov, runUrl);

  const opaLocal = env.opa_local !== 'skipped' ? formatOpaOutput(readFile(`opa_local_output_${environment}.txt`)) : '';
  body += detailSection('🔍', 'OPA', opaLocal, env.opa_local, LIMITS.opa_local, runUrl, '_No local policies found_');

  body += detailSection('💰', 'Infracost', readFile(`infracost_${environment}.txt`), env.infracost, LIMITS.infracost, runUrl);

  body += `*🧑 **Pusher:** @${actor}, **Action:** \`${eventName}\`*\n`;
  body += `*🔗 **Workflow Run:** [${runUrl}](${runUrl})*`;
  return body;
}

function enforceLimit(body, runUrl) {
  if (body.length <= MAX_COMMENT_LENGTH) return body;
  const footerIndex = body.lastIndexOf('\n*🧑');
  const footer = footerIndex !== -1 ? body.slice(footerIndex) : '';
  const allowance = MAX_COMMENT_LENGTH - footer.length - 80;
  return `${body.slice(0, allowance)}\n\n_(comment truncated — [view full logs](${runUrl}))_${footer}`;
}

function loadEnvironments(directory) {
  return fs
    .readdirSync(directory)
    .filter((file) => file.startsWith('outcomes_') && file.endsWith('.json'))
    .map((file) => {
      try {
        return JSON.parse(fs.readFileSync(path.join(directory, file), 'utf8'));
      } catch {
        return null;
      }
    })
    .filter(Boolean)
    .sort((a, b) => a.environment.localeCompare(b.environment));
}

module.exports = async ({ github, context }) => {
  const directory = process.env.ARTIFACTS_DIR || '.';
  const readFile = makeReader(directory);
  const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;

  const {
    data: { artifacts },
  } = await github.rest.actions.listWorkflowRunArtifacts({
    owner: context.repo.owner,
    repo: context.repo.repo,
    run_id: context.runId,
  });

  const artifactUrlFor = (environment) => {
    const artifact = artifacts.find((candidate) => candidate.name === `plan-${environment}`);
    return artifact
      ? `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}/artifacts/${artifact.id}`
      : null;
  };

  const { data: comments } = await github.rest.issues.listComments({
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: context.payload.pull_request.number,
    per_page: 100,
  });

  for (const env of loadEnvironments(directory)) {
    const body = enforceLimit(
      buildBody(env, {
        artifactUrl: artifactUrlFor(env.environment),
        runUrl,
        actor: context.actor,
        eventName: context.eventName,
        readFile,
      }),
      runUrl
    );

    const marker = markerFor(env.environment);
    const existing = comments.find((comment) => comment.body && comment.body.includes(marker));

    if (existing) {
      await github.rest.issues.updateComment({
        owner: context.repo.owner,
        repo: context.repo.repo,
        comment_id: existing.id,
        body,
      });
    } else {
      await github.rest.issues.createComment({
        owner: context.repo.owner,
        repo: context.repo.repo,
        issue_number: context.payload.pull_request.number,
        body,
      });
    }
  }
};

Object.assign(module.exports, {
  LIMITS,
  MAX_COMMENT_LENGTH,
  buildBody,
  detailSection,
  enforceLimit,
  formatOpaOutput,
  label,
  loadEnvironments,
  makeReader,
  markerFor,
  statusEmoji,
  truncate,
});
