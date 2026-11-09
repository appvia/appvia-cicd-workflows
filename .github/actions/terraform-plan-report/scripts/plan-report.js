'use strict';

// Renders a Terraform plan JSON document as a self-contained HTML report. Kept dependency-free so
// it runs on the runner's node without an install step.

const fs = require('fs');

const NO_OP = 'no-op';

const escapeHtml = (value) =>
  String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

const escapeMarkdownTableCell = (value) =>
  String(value).replace(/\\/g, '\\\\').replace(/`/g, '\\`').replace(/\|/g, '\\|');

function changedResources(plan) {
  return (plan.resource_changes || []).filter((resource) => {
    const actions = resource.change?.actions || [];
    return !(actions.length === 1 && actions[0] === NO_OP);
  });
}

function countActions(changes) {
  const counts = { create: 0, update: 0, delete: 0, replace: 0 };
  for (const resource of changes) {
    const actions = resource.change.actions;
    if (actions.includes('create') && actions.includes('delete')) counts.replace += 1;
    else if (actions.includes('create')) counts.create += 1;
    else if (actions.includes('delete')) counts.delete += 1;
    else if (actions.includes('update')) counts.update += 1;
  }
  return counts;
}

function actionLabel(actions) {
  if (actions.includes('create') && actions.includes('delete')) {
    return '<span style="color:#c00">&#8644; replace</span>';
  }
  if (actions.includes('create')) return '<span style="color:#080">+ create</span>';
  if (actions.includes('delete')) return '<span style="color:#c00">&minus; destroy</span>';
  if (actions.includes('update')) return '<span style="color:#a60">~ update</span>';
  return escapeHtml(actions.join(', '));
}

function badge(count, label, colour) {
  if (count <= 0) return '';
  return `<span style="background:${colour};color:#fff;padding:2px 8px;border-radius:4px;margin-right:4px">${count} ${label}</span>`;
}

function renderRow(resource) {
  const body = escapeHtml(
    JSON.stringify(resource.change.after ?? resource.change.before ?? {}, null, 2)
  );
  return `
    <details>
      <summary><code>${escapeHtml(resource.address)}</code> (${escapeHtml(resource.type)}) &mdash; ${actionLabel(resource.change.actions)}</summary>
      <pre style="background:#f6f8fa;padding:12px;overflow:auto;border-radius:4px">${body}</pre>
    </details>`;
}

function renderPlanReport(plan) {
  const changes = changedResources(plan);
  const counts = countActions(changes);
  const rows = changes.map(renderRow).join('\n');

  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<title>Terraform Plan Report</title>
<style>
  body{font-family:system-ui,sans-serif;max-width:960px;margin:32px auto;padding:0 16px;color:#1f2328}
  h1{margin-bottom:8px}
  details>summary{cursor:pointer;padding:6px 4px;border-radius:4px}
  details>summary:hover{background:#f0f0f0}
  details[open]>summary{font-weight:600}
  pre{font-size:13px}
</style>
</head><body>
<h1>&#127758; Terraform Plan Report</h1>
<p>
  ${badge(counts.create, 'to add', '#2a7')}
  ${badge(counts.update, 'to change', '#b70')}
  ${badge(counts.delete, 'to destroy', '#c33')}
  ${badge(counts.replace, 'to replace', '#c33')}
</p>
<p>${changes.length} resource(s) with planned changes.</p>
${rows || '<p>&#10003; No changes.</p>'}
</body></html>`;
}

function renderPlanSummary(plan, title = 'Terraform Plan Summary') {
  const changes = changedResources(plan);
  const counts = countActions(changes);
  const resources = changes.map((resource) =>
    `| \`${escapeMarkdownTableCell(resource.address)}\` | ${escapeMarkdownTableCell(resource.type)} | ${escapeMarkdownTableCell(resource.change.actions.join(', '))} |`
  );

  return [
    `## ${title}`,
    '',
    `| Add | Change | Destroy | Replace |`,
    `| ---: | ---: | ---: | ---: |`,
    `| ${counts.create} | ${counts.update} | ${counts.delete} | ${counts.replace} |`,
    '',
    changes.length === 0
      ? 'No infrastructure changes are planned.'
      : `<details><summary>${changes.length} resource(s) with planned changes</summary>\n\n| Resource | Type | Action |\n| --- | --- | --- |\n${resources.join('\n')}\n\n</details>`,
    '',
  ].join('\n');
}

module.exports = { renderPlanReport, renderPlanSummary, changedResources, countActions, escapeHtml };

if (require.main === module) {
  const [, , source, destination] = process.argv;
  if (!source || !destination) {
    console.error('usage: plan-report.js <plan.json> <report.html>');
    process.exit(1);
  }
  const plan = JSON.parse(fs.readFileSync(source, 'utf8'));
  fs.writeFileSync(destination, renderPlanReport(plan));
  console.log(`Wrote ${destination}`);
}
