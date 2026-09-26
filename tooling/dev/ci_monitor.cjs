#!/usr/bin/env node
// GitHub operations use explicit arguments and never evaluate a shell command.
const { execFileSync } = require('node:child_process');
const { readFileSync } = require('node:fs');
const { parseArgs } = require('node:util');

const HELP = `Usage: node tooling/dev/ci_monitor.cjs <command> [options]

Commands:
  runs                 List recent runs, optionally for --branch / --commit
  view <run-id>        Show run identity, conclusion, jobs and steps
  log-failed <run-id>  Print failed-step logs
  check-actions       Verify commits pinned in --file (default verify.yml)
  dispatch            Run verify.yml at --branch, only if remote --commit matches

Options:
  --repo OWNER/REPO    Default: the configured GitHub origin
  --branch NAME       Explicit remote branch (required for dispatch)
  --commit SHA        Full commit identity (required for dispatch)
  --file PATH         Workflow for read-only action-pin verification
  --job ID            Download this completed job's full log while other jobs run
  --help              Show this help without invoking GitHub

Requires Node.js 22+ and an authenticated GitHub CLI. Read commands never dispatch
or cancel workflows. Dispatch never pushes commits or changes the remote branch.
`;

function execute(binary, args) {
  return execFileSync(binary, args, {
    encoding: 'utf8', timeout: 60000, maxBuffer: 32 * 1024 * 1024,
    env: { ...process.env, GH_PROMPT_DISABLED: '1', GH_PAGER: 'cat' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function repository(value, run) {
  if (!value) {
    const origin = run('git', ['remote', 'get-url', 'origin']).trim();
    const match = /^(?:https:\/\/github\.com\/|git@github\.com:)([^/]+\/[^/]+?)\/?$/.exec(origin);
    if (!match) throw new Error('Origin must identify one GitHub repository.');
    value = match[1].replace(/\.git$/, '');
  }
  if (!/^[\w.-]+\/[\w.-]+$/.test(value)) throw new Error('Expected OWNER/REPO.');
  return value;
}

function main(args, run = execute, read = readFileSync) {
  const { values, positionals } = parseArgs({
    args, allowPositionals: true,
    options: {
      help: { type: 'boolean' }, repo: { type: 'string' }, branch: { type: 'string' },
      commit: { type: 'string' }, file: { type: 'string' }, job: { type: 'string' },
    },
  });
  if (values.help || positionals.length === 0) return HELP;
  const [command, id] = positionals;
  const commands = ['runs', 'view', 'log-failed', 'check-actions', 'dispatch'];
  if (!commands.includes(command)) throw new Error('Unknown command; use --help.');
  const needsID = ['view', 'log-failed'].includes(command);
  if (positionals.length !== (needsID ? 2 : 1) || (needsID && !/^\d+$/.test(id))) {
    throw new Error('Unexpected arguments or invalid run ID.');
  }
  if (values.commit && !/^[a-f0-9]{40}$/.test(values.commit)) {
    throw new Error('Commit must be a full lowercase SHA-1.');
  }
  if (values.job && (command !== 'log-failed' || !/^\d+$/.test(values.job))) {
    throw new Error('A numeric --job is supported only by log-failed.');
  }
  if (values.branch && (values.branch.startsWith('-') || /[\s\x00-\x1f]/.test(values.branch))) {
    throw new Error('Invalid branch name.');
  }
  if (command === 'dispatch' && (!values.branch || !values.commit)) {
    throw new Error('Dispatch requires --branch and --commit.');
  }
  const repo = repository(values.repo, run);
  const gh = (...argv) => run('gh', argv);
  if (command === 'runs') {
    const filter = [];
    if (values.branch) filter.push('--branch', values.branch);
    if (values.commit) filter.push('--commit', values.commit);
    return gh('run', 'list', '--repo', repo, '--limit', '20', ...filter,
      '--json', 'databaseId,headSha,headBranch,event,status,conclusion,workflowName,url');
  }
  if (command === 'view') {
    return gh('run', 'view', id, '--repo', repo,
      '--json', 'databaseId,headSha,headBranch,event,status,conclusion,workflowName,url,jobs');
  }
  if (command === 'log-failed') {
    if (!values.job) return gh('run', 'view', id, '--repo', repo, '--log-failed');
    const endpoint = `repos/${repo}/actions/jobs/${values.job}`;
    const job = JSON.parse(gh('api', endpoint));
    if (String(job.run_id) !== id || job.status !== 'completed') {
      throw new Error('Job must be completed and belong to the requested run.');
    }
    return gh('api', `${endpoint}/logs`);
  }
  if (command === 'check-actions') {
    const workflow = values.file || '.github/workflows/verify.yml';
    const uses = [...read(workflow, 'utf8').matchAll(/^\s*-?\s*uses:\s*([^\s#]+).*$/gm)];
    if (!uses.length) throw new Error('No action pins found.');
    const checked = [];
    for (const entry of new Set(uses.map(match => match[1]))) {
      const match = /^([\w.-]+\/[\w.-]+)@([a-f0-9]{40})$/.exec(entry);
      if (!match) throw new Error(`Expected a full action commit: ${entry}`);
      const resolved = JSON.parse(gh('api', `repos/${match[1]}/commits/${match[2]}`));
      if (resolved.sha !== match[2]) throw new Error(`Action commit mismatch: ${entry}`);
      checked.push({ action: match[1], sha: resolved.sha, url: resolved.html_url });
    }
    return JSON.stringify({ workflow, checked }, null, 2);
  }
  const remote = JSON.parse(gh('api', `repos/${repo}/commits/${encodeURIComponent(values.branch)}`));
  if (remote.sha !== values.commit) throw new Error('Remote branch does not match the requested commit.');
  const dispatched = gh('workflow', 'run', 'verify.yml', '--repo', repo, '--ref', values.branch);
  return JSON.stringify({ repository: repo, branch: values.branch, commit: remote.sha,
    dispatched: true, response: dispatched.trim(), result: 'pending' }, null, 2);
}

if (require.main === module) {
  try { process.stdout.write(main(process.argv.slice(2)) + '\n'); }
  catch (error) {
    // CLI diagnostics contain no environment or authentication-token dump.
    process.stderr.write(String(error.stderr || error.message).trim() + '\n');
    process.exitCode = 1;
  }
}

module.exports = { main };
