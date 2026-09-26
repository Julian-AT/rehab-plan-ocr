const assert = require('node:assert/strict');
const { test } = require('node:test');
const { mkdtempSync, rmSync, writeFileSync, readFileSync, existsSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { main } = require('../ci_monitor.cjs');
const sha = 'a'.repeat(40);

test('help and malformed dispatch never contact GitHub', () => {
  const never = () => { throw new Error('Unexpected subprocess'); };
  assert.match(main(['--help'], never), /Dispatch never pushes/);
  for (const args of [['dispatch'], ['view', '1;echo'], ['runs', '--commit', 'abcd']]) {
    assert.throws(() => main(args, never), error => !error.message.includes('Unexpected subprocess'));
  }
});

test('run selection retains the full commit and passes branch text as one argument', () => {
  const calls = [];
  main(['runs', '--repo', 'owner/repo', '--branch', 'feature/$(touch-secret)', '--commit', sha],
    (binary, args) => { calls.push([binary, args]); return '[]'; });
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], 'gh');
  assert.ok(calls[0][1].includes('feature/$(touch-secret)'));
  assert.ok(calls[0][1].includes(sha));
  assert.equal(calls[0][1][0], 'run');
  assert.equal(calls[0][1][1], 'list');
});

test('only GitHub origins are used implicitly', () => {
  for (const origin of ['https://github.com/owner/repo.git', 'git@github.com:owner/repo.git']) {
    main(['runs'], (binary, args) => {
      if (binary === 'git') return origin;
      assert.ok(args.includes('owner/repo'));
      return '[]';
    });
  }
  assert.throws(() => main(['runs'], () => 'https://elsewhere.example/owner/repo'), /Origin/);
});

test('failed logs can select a completed numeric job without waiting on unrelated jobs', () => {
  const calls = [];
  main(['log-failed', '123', '--repo', 'owner/repo', '--job', '456'],
    (binary, args) => {
      calls.push(args);
      return calls.length === 1 ? JSON.stringify({run_id: 123, status: 'completed'}) : 'Failure evidence';
    });
  assert.deepEqual(calls[1], ['api', 'repos/owner/repo/actions/jobs/456/logs']);
  assert.throws(() => main(['log-failed', '123', '--job', '--secret']), /job/);
  assert.throws(() => main(['log-failed', '123', '--repo', 'owner/repo', '--job', '456'],
    () => JSON.stringify({run_id: 999, status: 'completed'})), /belong/);
});

test('dispatch rejects a stale remote identity before creating any workflow event', () => {
  const calls = [];
  assert.throws(() => main(['dispatch', '--repo', 'owner/repo', '--branch', 'candidate', '--commit', sha],
    (binary, args) => { calls.push(args); return JSON.stringify({ sha: 'b'.repeat(40) }); }), /does not match/);
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], 'api');
});

test('dispatch records the exact remote identity and leaves acceptance pending', () => {
  const calls = [];
  const report = JSON.parse(main(['dispatch', '--repo', 'owner/repo', '--branch', 'candidate/test', '--commit', sha],
    (binary, args) => { calls.push(args); return args[0] === 'api' ? JSON.stringify({ sha }) : ''; }));
  assert.equal(calls[0][1], 'repos/owner/repo/commits/candidate%2Ftest');
  assert.deepEqual(calls[1], ['workflow', 'run', 'verify.yml', '--repo', 'owner/repo', '--ref', 'candidate/test']);
  assert.equal(report.commit, sha);
  assert.equal(report.result, 'pending');
});

test('action verification checks actual pinned commits and rejects floating tags', () => {
  const run = () => JSON.stringify({ sha, html_url: 'https://github.com/actions/example/commit/' + sha });
  const read = () => ` - uses: actions/example@${sha}\n - uses: actions/example@${sha}\n`;
  const report = JSON.parse(main(['check-actions', '--repo', 'owner/repo'], run, read));
  assert.equal(report.checked.length, 1);
  assert.throws(() => main(['check-actions', '--repo', 'owner/repo'], run,
    () => ' - uses: actions/example@main'), /full action commit/);
});

function evidenceFixture(mutate = () => {}) {
  const workflow = { id: 123, head_sha: sha, run_attempt: 2, status: 'completed', conclusion: 'failure' };
  const artifact = { id: 456, name: `native-checks-${sha}-2`, expired: false,
    workflow_run: { id: 123, head_sha: sha }, digest: 'sha256:reported-by-service' };
  mutate(workflow, artifact);
  const calls = [];
  const run = (binary, args) => {
    calls.push(args);
    if (args[0] === 'api') return JSON.stringify(args[1].includes('/artifacts?')
      ? { total_count: 1, artifacts: [artifact] } : workflow);
    writeFileSync(join(args.at(-1), 'device-bundle-verification.json'), '{"checked":true}\n');
    return '';
  };
  return { calls, run };
}

test('artifact listing is read-only and retains failed run identity', () => {
  const fixture = evidenceFixture();
  const result = JSON.parse(main(['artifacts', '123', '--repo', 'owner/repo'], fixture.run));
  assert.equal(result.commit, sha);
  assert.equal(result.conclusion, 'failure');
  assert.equal(fixture.calls.length, 2);
  assert.ok(fixture.calls.every(args => args[0] === 'api'));
});

test('evidence download validates the exact attempt and records local file hashes', () => {
  const directory = mkdtempSync(join(tmpdir(), 'reha-ci-evidence-'));
  try {
    const fixture = evidenceFixture();
    const output = join(directory, 'new');
    const args = ['evidence', '123', '--repo', 'owner/repo', '--commit', sha, '--output', output];
    const result = JSON.parse(main(args, fixture.run));
    assert.equal(result.status, 'downloaded');
    assert.equal(result.archiveDigestVerified, false);
    assert.equal(result.attempt, 2);
    assert.match(result.files['device-bundle-verification.json'].sha256, /^[a-f0-9]{64}$/);
    assert.deepEqual(fixture.calls[2], ['run', 'download', '123', '--repo', 'owner/repo',
      '--name', `native-checks-${sha}-2`, '--dir', join(output, 'contents')]);
    assert.equal(JSON.parse(readFileSync(join(output, 'receipt.json'))).status, 'downloaded');
    assert.throws(() => main(args, fixture.run), /EEXIST/);
  } finally { rmSync(directory, { recursive: true }); }
});

test('stale commits, pending runs, expired artifacts and wrong attempts cannot download', () => {
  const directory = mkdtempSync(join(tmpdir(), 'reha-ci-rejection-'));
  try {
    for (const mutate of [
      workflow => { workflow.head_sha = 'b'.repeat(40); },
      workflow => { workflow.status = 'in_progress'; },
      (_, artifact) => { artifact.expired = true; },
      (_, artifact) => { artifact.name = `native-checks-${sha}-1`; },
      (_, artifact) => { artifact.workflow_run.id = 789; },
    ]) {
      const fixture = evidenceFixture(mutate);
      const output = join(directory, 'rejected');
      assert.throws(() => main(['evidence', '123', '--repo', 'owner/repo', '--commit', sha,
        '--output', output], fixture.run));
      assert.ok(fixture.calls.every(args => args[0] === 'api'));
      assert.equal(existsSync(output), false);
    }
  } finally { rmSync(directory, { recursive: true }); }
});

test('failed downloads retain an explicitly incomplete receipt', () => {
  const directory = mkdtempSync(join(tmpdir(), 'reha-ci-interrupted-'));
  try {
    const fixture = evidenceFixture();
    const output = join(directory, 'partial');
    assert.throws(() => main(['evidence', '123', '--repo', 'owner/repo', '--commit', sha,
      '--output', output], (binary, args) => {
      if (args[0] === 'run') throw new Error('Download interrupted');
      return fixture.run(binary, args);
    }), /interrupted/);
    assert.equal(JSON.parse(readFileSync(join(output, 'receipt.json'))).status, 'download-started');
  } finally { rmSync(directory, { recursive: true }); }
});
