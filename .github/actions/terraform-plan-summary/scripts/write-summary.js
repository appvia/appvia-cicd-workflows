'use strict';

const fs = require('fs');
const path = require('path');
const { renderPlanSummary } = require(path.join(
  __dirname,
  '..',
  '..',
  'terraform-plan-report',
  'scripts',
  'plan-report.js'
));

const [, , planPath, summaryPath, title] = process.argv;
if (!planPath || !summaryPath || !title) {
  console.error('usage: write-summary.js <plan.json> <summary.md> <title>');
  process.exit(1);
}

const plan = JSON.parse(fs.readFileSync(planPath, 'utf8'));
fs.appendFileSync(summaryPath, `${renderPlanSummary(plan, title)}\n`);