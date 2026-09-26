const assert = require('node:assert/strict');
const { test } = require('node:test');
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
