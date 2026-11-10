// hook-command.test.mjs - tests the exact Stop hook command in plugins/code-handoff/hooks/hooks.json.
// Run with: node --test tests/handoff/hook-command.test.mjs   (Node 18+, any OS)
//
// Claude Code runs a shell-form hook with `sh -c` on macOS and Linux, Git Bash on Windows, or
// PowerShell on Windows when Git Bash isn't installed (code.claude.com/docs/en/hooks). The
// command is valid in both sh and PowerShell:
//   sh/bash:    ${env:-eval "..."} expands to `eval "..."`, which picks the script by `uname -s`
//               and then execs it or exits, so the rest of the line never runs.
//   PowerShell: ${env:-eval "..."} is a read of a missing env variable (null, silent), then
//               `; powershell.exe ... handoff.ps1` runs exactly as before.
// These tests read the command from hooks.json, so they test what ships.

import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, existsSync, mkdirSync, writeFileSync, chmodSync, copyFileSync } from 'node:fs';
import { join } from 'node:path';
import { repoRoot, fixtureDir, isWindows, newRoot, removeRoot, newHome, newProject, handoffFile } from './helpers.mjs';

const hooksJson = JSON.parse(readFileSync(join(repoRoot, 'plugins', 'code-handoff', 'hooks', 'hooks.json'), 'utf8'));
const entry = hooksJson.hooks.Stop[0].hooks[0];
const command = entry.command;
const pluginRoot = join(repoRoot, 'plugins', 'code-handoff').replace(/\\/g, '/');   // Claude Code passes C:/... on Windows

// Git Bash, as Claude Code uses it. Not `bash` from PATH: on Windows that can be WSL's bash.exe.
const gitBash = isWindows
  ? [process.env.CLAUDE_CODE_GIT_BASH_PATH, 'C:\\Program Files\\Git\\bin\\bash.exe', 'C:\\Program Files\\Git\\usr\\bin\\bash.exe'].find((p) => p && existsSync(p))
  : null;
const posixShell = '/bin/sh';
const powershellExe = isWindows ? join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe') : null;

let root;
before(() => { root = newRoot(); });
after(() => removeRoot(root));

function run(shell, args, { project, home, env = {}, input }) {
  const e = { ...process.env, ...env };
  for (const k of ['CLAUDE_PROJECT_DIR', 'CLAUDE_PLUGIN_ROOT']) delete e[k];
  Object.assign(e, { CLAUDE_PROJECT_DIR: project, CLAUDE_PLUGIN_ROOT: pluginRoot, HOME: home, USERPROFILE: home }, env);
  return new Promise((resolve, reject) => {
    const child = spawn(shell, args, { cwd: project, env: e, stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = ''; let stderr = '';
    child.stdout.on('data', (d) => { stdout += d; });
    child.stderr.on('data', (d) => { stderr += d; });
    child.on('error', reject);
    child.on('close', (code) => resolve({ code, stdout, stderr }));
    child.stdin.end(input);
  });
}
// A project with the normal-turn fixture and the Stop hook JSON for it.
function turnSetup(name) {
  const home = newHome(root, `home-${name}`);
  const project = newProject(root, name);
  const transcript = join(project, 'transcript.jsonl');
  copyFileSync(join(fixtureDir, 'normal-turn.jsonl'), transcript);
  const input = JSON.stringify({ session_id: 'hook-command-test', transcript_path: transcript, cwd: project, last_assistant_message: 'Added the greeting line to the README.', stop_hook_active: false, hook_event_name: 'Stop' });
  return { home, project, input };
}

test('hooks.json has one async Stop hook with a 60 s timeout', () => {
  assert.equal(hooksJson.hooks.Stop.length, 1);
  assert.equal(hooksJson.hooks.Stop[0].hooks.length, 1);
  assert.equal(entry.type, 'command');
  assert.equal(entry.async, true);
  assert.equal(entry.timeout, 60, 'must cover the 30 s lock wait plus the 2 s transcript wait');
  assert.equal(entry.args, undefined, 'shell form: no args');
  assert.equal(entry.shell, undefined, 'no shell field: Claude Code picks sh, Git Bash or PowerShell');
});

describe('Windows', { skip: !isWindows && 'Windows only' }, () => {
  test('Git Bash: runs handoff.ps1, which writes the turn', { skip: !gitBash && 'Git Bash not found' }, async () => {
    const { home, project, input } = turnSetup('win-git-bash');
    const r = await run(gitBash, ['-c', command], { project, home, input });
    assert.equal(r.code, 0, r.stderr);
    const last = handoffFile(project, 'last.md');
    assert.ok(last, 'last.md written');
    assert.match(last, /Add a greeting line to the README\./);
    assert.match(last, /\r\n/, 'CRLF: written by handoff.ps1, not handoff.mjs');
    assert.equal(r.stderr.trim(), '');
  });

  test('PowerShell (Windows without Git Bash): runs handoff.ps1, which writes the turn', async () => {
    const { home, project, input } = turnSetup('win-powershell');
    const r = await run(powershellExe, ['-NoProfile', '-Command', command], { project, home, input });
    assert.equal(r.code, 0, r.stderr);
    const last = handoffFile(project, 'last.md');
    assert.ok(last, 'last.md written');
    assert.match(last, /Add a greeting line to the README\./);
    assert.match(last, /\r\n/, 'CRLF: written by handoff.ps1');
    assert.equal(r.stderr.trim(), '', 'no PowerShell errors from the sh part');
  });

  const pwsh = isWindows ? spawnSync('where', ['pwsh'], { encoding: 'utf8' }) : null;
  test('pwsh, if installed: runs handoff.ps1 too', { skip: (!pwsh || pwsh.status !== 0) && 'pwsh not installed' }, async () => {
    const { home, project, input } = turnSetup('win-pwsh');
    const r = await run('pwsh', ['-NoProfile', '-Command', command], { project, home, input });
    assert.equal(r.code, 0, r.stderr);
    assert.match(handoffFile(project, 'last.md') || '', /\r\n/);
  });
});

describe('macOS and Linux', { skip: isWindows && 'macOS and Linux only' }, () => {
  test('sh -c: runs handoff.mjs, which writes the turn', async () => {
    const { home, project, input } = turnSetup('posix-node');
    const r = await run(posixShell, ['-c', command], { project, home, input });
    assert.equal(r.code, 0, r.stderr);
    const last = handoffFile(project, 'last.md');
    assert.ok(last, 'last.md written');
    assert.match(last, /Add a greeting line to the README\./);
    assert.doesNotMatch(last, /\r\n/, 'LF: written by handoff.mjs');
    assert.equal(r.stderr.trim(), '');
  });

  test('sh -c with node not on PATH: exit 0, nothing written, no output', async (t) => {
    const path = '/usr/bin:/bin';
    const probe = spawnSync(posixShell, ['-c', 'command -v node'], { env: { PATH: path }, encoding: 'utf8' });
    if (probe.status === 0) { t.skip(`node is in ${path} on this machine`); return; }
    const { home, project, input } = turnSetup('posix-no-node');
    const r = await run(posixShell, ['-c', command], { project, home, input, env: { PATH: path } });
    assert.equal(r.code, 0);
    assert.equal(r.stdout + r.stderr, '');
    assert.equal(existsSync(join(project, '.claude', 'handoff')), false);
  });
});

// The uname branch, with fake uname, powershell.exe and node that only print what was picked.
const shellForBranch = isWindows ? gitBash : posixShell;
describe('the uname branch', { skip: !shellForBranch && 'no sh available' }, () => {
  const cases = [
    ['Linux', 'handoff.mjs'],
    ['Darwin', 'handoff.mjs'],
    ['MINGW64_NT-10.0-26100', 'handoff.ps1'],
    ['MINGW32_NT-10.0', 'handoff.ps1'],
    ['MSYS_NT-10.0-26100', 'handoff.ps1'],
    ['CYGWIN_NT-10.0', 'handoff.ps1'],
  ];
  for (const [unameS, picked] of cases) {
    test(`uname -s = ${unameS} picks ${picked}`, async () => {
      const bin = join(root, `bin-${unameS}`);
      mkdirSync(bin, { recursive: true });
      const fake = (name, body) => { writeFileSync(join(bin, name), `#!/bin/sh\n${body}\n`); chmodSync(join(bin, name), 0o755); };
      fake('uname', `echo "${unameS}"`);
      fake('powershell.exe', 'echo "picked: $*"');
      fake('node', 'echo "picked: $*"');
      const home = newHome(root, `home-uname-${unameS}`);
      const project = newProject(root, `uname-${unameS}`);
      const PATH = isWindows ? `${bin.replace(/^([A-Za-z]):/, (m, d) => '/' + d.toLowerCase()).replace(/\\/g, '/')}:/usr/bin:/bin` : `${bin}:/usr/bin:/bin`;
      const r = await run(shellForBranch, ['-c', `PATH="${PATH}"; export PATH; ${command}`], { project, home, input: '{}' });
      assert.equal(r.code, 0, r.stderr);
      assert.match(r.stdout.trim(), new RegExp(`^picked: .*scripts/${picked.replace('.', '\\.')}$`));
      if (picked === 'handoff.ps1') assert.match(r.stdout, /-NoProfile -ExecutionPolicy Bypass -File /);
    });
  }
});
