// Aggregates the per unit plan summaries produced by terragrunt-plan-collect into a
// single markdown report; used by the terragrunt-plan-summary action via github-script
const fs = require("fs");
const path = require("path");

// GitHub limits comments to 65536 characters, and step summaries to 1MiB
const COMMENT_LIMIT = 65000;
const STEP_SUMMARY_LIMIT = 1000000;
// The maximum size of a single unit plan, to stop one unit consuming the whole report
const UNIT_PLAN_LIMIT = 20000;

const COUNTERS = ["create", "update", "replace", "delete"];
const ICONS = { create: "➕", update: "🔄", replace: "♻️", delete: "❌" };

// Recursively find all summary.json files under the directory
function findSummaries(dir) {
  if (!fs.existsSync(dir)) {
    return [];
  }
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      return findSummaries(full);
    }
    return entry.name === "summary.json" ? [full] : [];
  });
}

function loadSummaries(dir) {
  return findSummaries(dir).map((file) => JSON.parse(fs.readFileSync(file, "utf8")));
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\|/g, "&#124;");
}

// Flatten the matrix summaries into one row per terragrunt unit planned
function toRows(summaries) {
  const rows = [];
  for (const summary of summaries) {
    const units = summary.units || [];
    const failed = summary.outcome_plan !== "success";

    // A failed plan may have produced no plan files at all, but still needs a row
    if (units.length === 0) {
      rows.push({ ...summary, label: summary.name, failed, plan: "", changes: [] });
      continue;
    }
    for (const unit of units) {
      const label = unit.path && unit.path !== "." ? `${summary.name}/${unit.path}` : summary.name;
      rows.push({ ...summary, ...unit, label, failed });
    }
  }

  const total = (row) => COUNTERS.reduce((sum, key) => sum + (row[key] || 0), 0);
  for (const row of rows) {
    row.total = total(row);
    row.importing = row.import || 0;
    row.destructive = (row.delete || 0) + (row.replace || 0) > 0;
    row.changed = row.total > 0 || row.importing > 0 || (row.forget || 0) > 0 || (row.outputs || 0) > 0;
  }

  return rows.sort(
    (a, b) =>
      (a.account || "").localeCompare(b.account || "") ||
      (a.region || "").localeCompare(b.region || "") ||
      a.label.localeCompare(b.label),
  );
}

function status(row) {
  if (row.failed) {
    return `💥 ${row.outcome_plan || "failed"}`;
  }
  if (row.destructive) {
    return "⚠️ destructive";
  }
  if (row.total > 0 || row.importing > 0 || (row.forget || 0) > 0) {
    return "📝 changes";
  }
  if ((row.outputs || 0) > 0) {
    return "📤 outputs only";
  }
  return "✅ no changes";
}

function title(row) {
  return [row.account, row.region, row.label].filter(Boolean).join(" / ");
}

function counts(row) {
  return COUNTERS.map((key) => `${ICONS[key]} ${row[key] || 0}`).join(" ");
}

// Shift the change markers to the start of the line, so GitHub highlights the plan as a diff
function toDiff(plan) {
  return plan
    .split("\n")
    .map((line) => {
      const replace = line.match(/^(\s*)([-+]\/[-+]) (.*)$/);
      if (replace) {
        return `!${replace[1]}${replace[2]} ${replace[3]}`;
      }
      const change = line.match(/^(\s*)([-+~])( .*)$/);
      if (change) {
        return `${change[2] === "~" ? "!" : change[2]}${change[1]}${change[3]}`;
      }
      return ` ${line}`;
    })
    .join("\n");
}

function codeBlock(text) {
  // Ensure the fence is longer than any run of backticks inside the plan
  const longest = Math.max(0, ...(text.match(/`+/g) || []).map((run) => run.length));
  const fence = "`".repeat(Math.max(3, longest + 1));
  return `${fence}diff\n${text}\n${fence}`;
}

function unitDetails(row, runUrl) {
  let body;
  if (row.failed && !row.plan) {
    body = `The plan for this unit did not complete, see the [workflow run](${runUrl}) for the logs.`;
  } else {
    let plan = (row.plan || "").trimEnd();
    if (plan.length > UNIT_PLAN_LIMIT) {
      plan = `${plan.slice(0, UNIT_PLAN_LIMIT)}\n... (truncated, see the workflow run for the full plan)`;
    }
    body = plan ? codeBlock(toDiff(plan)) : "_No plan output was captured for this unit._";
  }
  return `<details><summary><b>${escapeHtml(title(row))}</b> — ${counts(row)}</summary>\n\n${body}\n\n</details>\n`;
}

// Returns the overall outcome of the matrix, accounting for legs which never reported
function outcome(values, expected) {
  if (values.some((value) => value === "failure")) {
    return "failure";
  }
  if (values.some((value) => value === "cancelled")) {
    return "cancelled";
  }
  if (expected && values.length < expected) {
    return "failure";
  }
  if (values.length === 0) {
    return "skipped";
  }
  return values.every((value) => value === "success") ? "success" : "failure";
}

function render(summaries, options = {}) {
  const { environment = "", expected = 0, limit = COMMENT_LIMIT, marker = "", runUrl = "" } = options;
  const rows = toRows(summaries);
  const changed = rows.filter((row) => row.changed || row.failed);
  const unchanged = rows.filter((row) => !row.changed && !row.failed);
  const failed = rows.filter((row) => row.failed);
  const missing = Math.max(0, expected - summaries.length);
  const totals = Object.fromEntries(
    COUNTERS.map((key) => [key, rows.reduce((sum, row) => sum + (row[key] || 0), 0)]),
  );

  const lines = [];
  if (marker) {
    lines.push(marker);
  }
  lines.push(`### 📖 Terragrunt Plan Summary (${escapeHtml(environment)})`, "");
  lines.push(
    `**${rows.length} unit(s) planned** · ${rows.filter((row) => row.changed).length} with changes · ${failed.length} failed`,
    "",
  );
  lines.push(
    `${ICONS.create} ${totals.create} to add · ${ICONS.update} ${totals.update} to change · ` +
      `${ICONS.replace} ${totals.replace} to replace · ${ICONS.delete} ${totals.delete} to destroy`,
    "",
  );
  if (missing > 0) {
    lines.push(
      "> [!CAUTION]",
      `> ${missing} matrix job(s) did not report a plan summary, see the [workflow run](${runUrl}).`,
      "",
    );
  }

  if (changed.length > 0) {
    lines.push("| Account | Region | Unit | Status | ➕ | 🔄 | ♻️ | ❌ |", "|---|---|---|---|--:|--:|--:|--:|");
    for (const row of changed) {
      const cells = [row.account, row.region, row.label].map(escapeHtml);
      cells.push(status(row), ...COUNTERS.map((key) => row[key] || 0));
      lines.push(`| ${cells.join(" | ")} |`);
    }
    lines.push("");
  } else if (failed.length === 0 && missing === 0) {
    lines.push("✅ No changes detected across any unit.", "");
  }

  // Always surface destroys and replacements, these are what reviewers most need to see
  const destructive = rows.flatMap((row) =>
    (row.changes || [])
      .filter((change) => change.kind === "delete" || change.kind === "replace")
      .map((change) => `- ${ICONS[change.kind]} \`${change.address}\` in **${escapeHtml(title(row))}**`),
  );
  if (destructive.length > 0) {
    lines.push("> [!WARNING]", `> ${destructive.length} resource(s) will be destroyed or replaced`, "");
    lines.push(...destructive, "");
  }

  if (unchanged.length > 0) {
    lines.push(`<details><summary>✅ ${unchanged.length} unit(s) with no changes</summary>\n`);
    lines.push(...unchanged.map((row) => `- ${escapeHtml(title(row))}`), "", "</details>", "");
  }

  const footer = [];
  if (runUrl) {
    footer.push(`*<b>Workflow Run Link:</b> ${runUrl}*`);
  }

  // Add the per unit plans while they fit within the limit
  let report = lines.join("\n");
  const details = changed.map((row) => unitDetails(row, runUrl));
  if (details.length > 0) {
    report += "\n#### Plan Details\n\n";
    const reserve = footer.join("\n").length + 500;
    let omitted = 0;
    for (const detail of details) {
      if (omitted === 0 && report.length + detail.length + reserve < limit) {
        report += `${detail}\n`;
      } else {
        omitted += 1;
      }
    }
    if (omitted > 0) {
      report += `_${omitted} unit plan(s) omitted due to size, see the workflow run summary for the full report._\n`;
    }
  }

  return `${report}\n${footer.join("\n")}\n`;
}

// ANSI colours, which the GitHub Actions log viewer renders
const COLOURS = { green: "\u001b[32m", red: "\u001b[31m", yellow: "\u001b[33m", bold: "\u001b[1m", reset: "\u001b[0m" };

function colour(name, text) {
  return `${COLOURS[name]}${text}${COLOURS.reset}`;
}

// Colour the plan the same way terraform does, keyed on the change marker of each line
function colourPlan(plan) {
  return plan
    .split("\n")
    .map((line) => {
      if (/^\s*([-+]\/[-+]|~) /.test(line)) {
        return colour("yellow", line);
      }
      if (/^\s*\+ /.test(line)) {
        return colour("green", line);
      }
      if (/^\s*- /.test(line)) {
        return colour("red", line);
      }
      return line;
    })
    .join("\n");
}

function pad(value, width) {
  return String(value).padEnd(width);
}

// Prints the report to the job log, with each unit plan in a collapsible group
function printReport(summaries, core, options = {}) {
  const { environment = "", expected = 0 } = options;
  const rows = toRows(summaries);
  const changed = rows.filter((row) => row.changed || row.failed);
  const missing = Math.max(0, expected - summaries.length);
  const total = (key) => rows.reduce((sum, row) => sum + (row[key] || 0), 0);
  const plain = (text) => text.replace(/\u001b\[[0-9;]*m/g, "");

  core.info("");
  core.info(colour("bold", `Terragrunt Plan Summary (${environment})`));
  core.info(
    `${rows.length} unit(s) planned, ${rows.filter((row) => row.changed).length} with changes, ` +
      `${rows.filter((row) => row.failed).length} failed`,
  );
  core.info(
    `${colour("green", `${total("create")} to add`)}, ${colour("yellow", `${total("update")} to change`)}, ` +
      `${colour("yellow", `${total("replace")} to replace`)}, ${colour("red", `${total("delete")} to destroy`)}`,
  );
  if (missing > 0) {
    core.warning(`${missing} matrix job(s) did not report a plan summary`);
  }
  core.info("");

  if (rows.length > 0) {
    const header = ["Account", "Region", "Unit", "Status", "Add", "Change", "Replace", "Destroy"];
    const table = rows.map((row) => [
      row.account || "-",
      row.region || "-",
      row.label,
      plain(status(row)).replace(/^\S+\s/, ""),
      ...COUNTERS.map((key) => row[key] || 0),
    ]);
    const widths = header.map((title, index) => Math.max(title.length, ...table.map((cells) => String(cells[index]).length)));
    const line = (cells) => cells.map((cell, index) => pad(cell, widths[index])).join("  ");
    core.info(colour("bold", line(header)));
    for (const cells of table) {
      const text = line(cells);
      const row = rows[table.indexOf(cells)];
      core.info(row.failed || row.destructive ? colour("red", text) : row.changed ? colour("yellow", text) : text);
    }
    core.info("");
  }

  const destructive = rows.flatMap((row) =>
    (row.changes || [])
      .filter((change) => change.kind === "delete" || change.kind === "replace")
      .map((change) => `${change.kind === "delete" ? "destroy" : "replace"}: ${change.address} (${title(row)})`),
  );
  if (destructive.length > 0) {
    core.warning(`${destructive.length} resource(s) will be destroyed or replaced:\n${destructive.join("\n")}`);
  }

  for (const row of changed) {
    core.startGroup(`${title(row)}: ${row.create || 0} to add, ${row.update || 0} to change, ${row.replace || 0} to replace, ${row.delete || 0} to destroy`);
    if (row.failed && !row.plan) {
      core.info(colour("red", `The plan for this unit did not complete (${row.outcome_plan || "failed"}), see the matrix job logs`));
    } else {
      core.info(row.plan ? colourPlan(row.plan.trimEnd()) : "No plan output was captured for this unit.");
    }
    core.endGroup();
  }
}

// Entrypoint for actions/github-script
async function run({ github, context, core, inputs }) {
  const summaries = loadSummaries(inputs.directory);
  const expected = parseInt(inputs.expected || "0", 10) || 0;
  const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
  const marker = `<!-- terragrunt-plan-summary:${inputs.environment} -->`;
  const options = { environment: inputs.environment, expected, runUrl };

  core.info(`Loaded ${summaries.length} plan summaries (expected ${expected})`);
  core.setOutput("result-plan", outcome(summaries.map((summary) => summary.outcome_plan), expected));
  core.setOutput("result-auth", outcome(summaries.map((summary) => summary.outcome_auth).filter(Boolean), 0));
  core.setOutput("changes", String(toRows(summaries).some((row) => row.changed)));

  printReport(summaries, core, options);
  await core.summary.addRaw(render(summaries, { ...options, limit: STEP_SUMMARY_LIMIT })).write();

  if (inputs.comment !== "true" || !context.issue.number) {
    return;
  }

  const body = render(summaries, { ...options, marker, limit: COMMENT_LIMIT });
  const comments = await github.paginate(github.rest.issues.listComments, {
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: context.issue.number,
  });
  const existing = comments.find((comment) => comment.user.type === "Bot" && comment.body.includes(marker));

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
      issue_number: context.issue.number,
      body,
    });
  }
}

module.exports = { run, render, printReport, outcome, toDiff, toRows };
