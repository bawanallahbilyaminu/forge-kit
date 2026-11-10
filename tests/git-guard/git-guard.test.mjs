// git-guard.test.mjs - node:test tests for the macOS/Linux git guard,
// plugins/idea-forge/skills/idea-code-setup/templates/git-guard.mjs.
// Run with: node --test tests/git-guard/git-guard.test.mjs   (Node 18+, nothing to install)
//
// The cases and expected behaviour are the same as tests/git-guard/git-guard.Tests.ps1 (Pester,
// Windows): see the table at the top of that file. Keep the two in step.
// Repos are temporary, their remote is a local bare repo (no network), the git identity is set
// in each repo's own config, and the user's global and system git config are ignored.
// GIT_GUARD_UNDER_TEST=<path> runs the tests against another copy of the script.

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const script = process.env.GIT_GUARD_UNDER_TEST ||
  resolve(here, '..', '..', 'plugins', 'idea-forge', 'skills', 'idea-code-setup', 'templates', 'git-guard.mjs');
const advice = 'If this turn made a meaningful change, commit it now with a Conventional Commit message';

let root;
let gitEnv;

before(() => {
  // realpath: on macOS the temp dir is a symlink (/var -> /private/var), and git compares real paths
  root = realpathSync(mkdtempSync(join(tmpdir(), 'forge-kit-tests-')));
  writeFileSync(join(root, 'empty.gitconfig'), '');
  gitEnv = { ...process.env };
  for (const k of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'CLAUDE_PROJECT_DIR']) delete gitEnv[k];
  gitEnv.GIT_CONFIG_GLOBAL = join(root, 'empty.gitconfig');
  gitEnv.GIT_CONFIG_NOSYSTEM = '1';
  gitEnv.GIT_CEILING_DIRECTORIES = root;
});
after(() => {
  if (root) rmSync(root, { recursive: true, force: true });
});

function git(dir, ...args) {
  const r = spawnSync('git', ['-C', dir, ...args], { env: gitEnv, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} failed in ${dir}: ${r.stderr}`);
  return r.stdout;
}
function put(path, text) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text);
}
function identity(repo) {
  git(repo, 'config', 'user.name', 'Test User');
  git(repo, 'config', 'user.email', 'test@example.invalid');
  git(repo, 'config', 'commit.gpgsign', 'false');
}
// A repo on branch main with one commit, no remote.
function newRepo(name) {
  const repo = join(root, name);
  mkdirSync(repo, { recursive: true });
  git(repo, 'init', '-q', '-b', 'main');
  identity(repo);
  put(join(repo, 'README.md'), 'test repo\n');
  git(repo, 'add', 'README.md');
  git(repo, 'commit', '-q', '-m', 'initial commit');
  return repo;
}
// Like newRepo, pushed to a local bare remote, with main tracking origin/main.
function newRepoWithRemote(name) {
  const bare = join(root, `${name}-remote.git`);
  mkdirSync(bare, { recursive: true });
  git(bare, 'init', '-q', '--bare', '-b', 'main');
  const repo = newRepo(name);
  git(repo, 'remote', 'add', 'origin', bare);
  git(repo, 'push', '-q', '-u', 'origin', 'main');
  return repo;
}
function commit(repo, file, message) {
  put(join(repo, file), `${message}\n`);
  git(repo, 'add', file);
  git(repo, 'commit', '-q', '-m', message);
}

// Runs the hook once, the way Claude Code does: Stop hook JSON on stdin, project dir in env.
function guard(dir, { stopHookActive = false, noProjectDir = false, rawInput = null } = {}) {
  const env = { ...gitEnv };
  if (!noProjectDir) env.CLAUDE_PROJECT_DIR = dir;
  const input = rawInput !== null ? rawInput
    : JSON.stringify({ session_id: 'test-session', stop_hook_active: stopHookActive, cwd: dir, hook_event_name: 'Stop' });
  const r = spawnSync(process.execPath, [script], { cwd: dir, env, input, encoding: 'utf8' });
  return { code: r.status, stderr: (r.stderr || '').trim() };
}

test('clean repo in sync with its upstream: exit 0, no message', () => {
  const r = guard(newRepoWithRemote('clean'));
  assert.equal(r.code, 0);
  assert.equal(r.stderr, '');
});

test('modified tracked file: blocks with exit 2 and counts 1 uncommitted change', () => {
  const repo = newRepoWithRemote('modified');
  put(join(repo, 'README.md'), 'changed\n');
  const r = guard(repo);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /^Git guard: this repo has 1 uncommitted file change\(s\)\. /);
  assert.doesNotMatch(r.stderr, /unpushed/);
  assert.ok(r.stderr.includes(advice));
});

test('untracked file: blocks with exit 2 and counts 1 uncommitted change', () => {
  const repo = newRepoWithRemote('untracked');
  put(join(repo, 'notes.txt'), 'new\n');
  const r = guard(repo);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /^Git guard: this repo has 1 uncommitted file change\(s\)\. /);
  assert.doesNotMatch(r.stderr, /unpushed/);
});

test('counts every changed path: 2 modified and 1 untracked is 3', () => {
  const repo = newRepoWithRemote('three-changes');
  commit(repo, 'b.txt', 'add b');
  git(repo, 'push', '-q');
  put(join(repo, 'README.md'), 'changed\n');
  put(join(repo, 'b.txt'), 'changed\n');
  put(join(repo, 'c.txt'), 'new\n');
  const r = guard(repo);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /has 3 uncommitted file change\(s\)\./);
});

test('unpushed commits: blocks with exit 2 and reports unpushed commits only', () => {
  const repo = newRepoWithRemote('ahead');
  commit(repo, 'feature.txt', 'add feature');
  commit(repo, 'feature2.txt', 'add feature 2');
  const r = guard(repo);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /^Git guard: this repo has unpushed commit\(s\)\. /);
  assert.doesNotMatch(r.stderr, /uncommitted file change/);
  assert.doesNotMatch(r.stderr, /no upstream/);
});

test('uncommitted changes and unpushed commits: reports both', () => {
  const repo = newRepoWithRemote('both');
  commit(repo, 'feature.txt', 'add feature');
  put(join(repo, 'README.md'), 'changed\n');
  const r = guard(repo);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /^Git guard: this repo has 1 uncommitted file change\(s\) and unpushed commit\(s\)\. /);
});

test('branch with no upstream (remote exists): blocks and says to push with -u', () => {
  const repo = newRepoWithRemote('no-upstream');
  git(repo, 'checkout', '-q', '-b', 'feature/x');
  commit(repo, 'x.txt', 'add x');
  const r = guard(repo);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /unpushed commit\(s\) \(current branch has no upstream yet - push with -u\)\. /);
});

test('branch with no upstream and no new commits still blocks (it counts as unpushed)', () => {
  const repo = newRepoWithRemote('no-upstream-empty');
  git(repo, 'checkout', '-q', '-b', 'feature/y');
  const r = guard(repo);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /no upstream yet - push with -u/);
});

test('behind its upstream but not ahead: exit 0', () => {
  const repo = newRepoWithRemote('behind');
  const other = join(root, 'behind-other');
  git(root, 'clone', '-q', join(root, 'behind-remote.git'), other);
  identity(other);
  commit(other, 'upstream.txt', 'upstream change');
  git(other, 'push', '-q');
  git(repo, 'fetch', '-q');
  const r = guard(repo);
  assert.equal(r.code, 0);
  assert.equal(r.stderr, '');
});

test('no remote: clean repo passes, and only uncommitted changes count', () => {
  const repo = newRepo('no-remote');
  commit(repo, 'local.txt', 'local only');
  assert.equal(guard(repo).code, 0);
  put(join(repo, 'README.md'), 'changed\n');
  const r = guard(repo);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /has 1 uncommitted file change\(s\)\./);
  assert.doesNotMatch(r.stderr, /unpushed/);
});

test('repo with a remote but no commits yet: only uncommitted changes count', () => {
  const repo = join(root, 'no-commits');
  mkdirSync(repo, { recursive: true });
  git(repo, 'init', '-q', '-b', 'main');
  git(repo, 'remote', 'add', 'origin', join(root, 'clean-remote.git'));
  assert.equal(guard(repo).code, 0);
  put(join(repo, 'first.txt'), 'new\n');
  const r = guard(repo);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /has 1 uncommitted file change\(s\)\./);
  assert.doesNotMatch(r.stderr, /unpushed/);
});

test('a folder that is not a git repo: exit 0, no message', () => {
  const dir = join(root, 'not-a-repo');
  put(join(dir, 'file.txt'), 'content\n');
  const r = guard(dir);
  assert.equal(r.code, 0);
  assert.equal(r.stderr, '');
});

test('stop_hook_active false on a dirty, unpushed repo: blocks (baseline for the next test)', () => {
  const repo = newRepoWithRemote('active-false');
  commit(repo, 'feature.txt', 'add feature');
  put(join(repo, 'README.md'), 'changed\n');
  assert.equal(guard(repo, { stopHookActive: false }).code, 2);
});

test('stop_hook_active true on the same kind of repo: exit 0, does not block again', () => {
  const repo = newRepoWithRemote('active-true');
  commit(repo, 'feature.txt', 'add feature');
  put(join(repo, 'README.md'), 'changed\n');
  const r = guard(repo, { stopHookActive: true });
  assert.equal(r.code, 0);
  assert.equal(r.stderr, '');
});

test('without CLAUDE_PROJECT_DIR it uses cwd from the hook input', () => {
  const repo = newRepoWithRemote('cwd-fallback');
  put(join(repo, 'README.md'), 'changed\n');
  const r = guard(repo, { noProjectDir: true });
  assert.equal(r.code, 2);
  assert.match(r.stderr, /has 1 uncommitted file change\(s\)\./);
});

test('invalid JSON on stdin: exit 0', () => {
  const repo = newRepoWithRemote('bad-json');
  put(join(repo, 'README.md'), 'changed\n');
  assert.equal(guard(repo, { rawInput: '{ not json' }).code, 0);
});

// ---- The settings templates and the hook command ----

const templates = resolve(here, '..', '..', 'plugins', 'idea-forge', 'skills', 'idea-code-setup', 'templates');
const readJson = (f) => JSON.parse(readFileSync(join(templates, f), 'utf8'));
const stopCommand = (j) => j.hooks.Stop[0].hooks[0].command;

test('settings.posix.json.template matches settings.json.template except the Stop hook command', () => {
  const win = readJson('settings.json.template');
  const posix = readJson('settings.posix.json.template');
  assert.match(stopCommand(win), /git-guard\.ps1/);
  assert.match(stopCommand(posix), /git-guard\.mjs/);
  win.hooks.Stop[0].hooks[0].command = 'X';
  posix.hooks.Stop[0].hooks[0].command = 'X';
  assert.deepEqual(posix, win);
});

const onWindows = process.platform === 'win32';

test('the POSIX hook command passes exit 2 through to Claude Code', { skip: onWindows && 'needs sh' }, () => {
  const repo = newRepoWithRemote('hook-command');
  put(join(repo, '.claude', 'hooks', 'git-guard.mjs'), readFileSync(script, 'utf8'));
  put(join(repo, 'README.md'), 'changed\n');
  const input = JSON.stringify({ session_id: 'test-session', stop_hook_active: false, cwd: repo });
  const r = spawnSync('sh', ['-c', stopCommand(readJson('settings.posix.json.template'))],
    { cwd: repo, env: { ...gitEnv, CLAUDE_PROJECT_DIR: repo }, input, encoding: 'utf8' });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /^Git guard: this repo has 2 uncommitted file change\(s\)\. /);
});

test('the POSIX hook command exits 0 when node is not on PATH', { skip: onWindows && 'needs sh' }, (t) => {
  const path = '/usr/bin:/bin';
  const probe = spawnSync('sh', ['-c', 'command -v node'], { env: { ...gitEnv, PATH: path }, encoding: 'utf8' });
  if (probe.status === 0) { t.skip(`node is in ${path} on this machine`); return; }
  const repo = newRepoWithRemote('hook-command-no-node');
  put(join(repo, '.claude', 'hooks', 'git-guard.mjs'), readFileSync(script, 'utf8'));
  put(join(repo, 'README.md'), 'changed\n');
  const r = spawnSync('/bin/sh', ['-c', stopCommand(readJson('settings.posix.json.template'))],
    { cwd: repo, env: { ...gitEnv, PATH: path, CLAUDE_PROJECT_DIR: repo }, input: '{}', encoding: 'utf8' });
  assert.equal(r.status, 0);
  assert.equal((r.stderr || '').trim(), '');
});
