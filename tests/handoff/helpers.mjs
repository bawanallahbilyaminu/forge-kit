// helpers.mjs - shared helpers for the node:test handoff tests (handoff.test.mjs, parity.test.mjs).
// Every run is a child process with the Stop hook JSON on stdin, the way Claude Code runs the
// hook, with a temporary HOME/USERPROFILE and a temporary project. Nothing touches the real
// profile. HANDOFF_UNDER_TEST=<path> runs the Node tests against another copy of handoff.mjs.

import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const repoRoot = resolve(here, '..', '..');
export const fixtureDir = join(repoRoot, 'tests', 'fixtures', 'handoff');
export const nodeScript = process.env.HANDOFF_UNDER_TEST || join(repoRoot, 'plugins', 'code-handoff', 'scripts', 'handoff.mjs');
export const psScript = join(repoRoot, 'plugins', 'code-handoff', 'scripts', 'handoff.ps1');
export const fakePluginRoot = join(tmpdir(), 'fake-plugin-cache', 'code-handoff', '0.0.0');
export const isWindows = process.platform === 'win32';

// A temp folder for one test file. realpath: on macOS the temp dir is a symlink.
export function newRoot() { return realpathSync(mkdtempSync(join(tmpdir(), 'forge-kit-tests-'))); }
export function removeRoot(root) { if (root) rmSync(root, { recursive: true, force: true }); }

export function put(path, text) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text);
}
export function newHome(root, name) {
  const h = join(root, name);
  mkdirSync(join(h, '.claude'), { recursive: true });
  // Windows: with USERPROFILE pointing here, powershell.exe needs AppData\Local for its module cache
  mkdirSync(join(h, 'AppData', 'Local'), { recursive: true });
  return h;
}
export function newProject(root, name) {
  const p = join(root, name);
  mkdirSync(join(p, '.claude'), { recursive: true });
  return p;
}
export function hookJson(command) {
  return JSON.stringify({ hooks: { Stop: [{ hooks: [{ type: 'command', command }] }] } }, null, 2);
}
export function execHookJson(command, args) {
  return JSON.stringify({ hooks: { Stop: [{ hooks: [{ type: 'command', command, args }] }] } }, null, 2);
}
// A one-turn transcript: "test prompt <n>" and "reply <n>".
export function simpleTranscript(project, n) {
  const tp = join(project, 'transcript.jsonl');
  const u = { type: 'user', message: { role: 'user', content: `test prompt ${n}` } };
  const a = { type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: `reply ${n}` }] } };
  writeFileSync(tp, JSON.stringify(u) + '\n' + JSON.stringify(a) + '\n');
  return tp;
}

// Runs one hook. impl: 'node' (handoff.mjs) or 'ps1' (handoff.ps1, Windows only).
// pluginRoot: '' runs it as a non-plugin copy. Resolves to { code, stderr }.
export function runHook({ impl = 'node', project, transcript, reply = '', session = 'test-session', cwd, home, pluginRoot = fakePluginRoot }) {
  const env = { ...process.env };
  for (const k of ['CLAUDE_PROJECT_DIR', 'CLAUDE_PLUGIN_ROOT', 'HANDOFF_UNDER_TEST']) delete env[k];
  env.CLAUDE_PROJECT_DIR = project;
  if (pluginRoot) env.CLAUDE_PLUGIN_ROOT = pluginRoot;
  env.HOME = home;
  env.USERPROFILE = home;
  const input = JSON.stringify({ session_id: session, transcript_path: transcript, cwd: cwd ?? project, last_assistant_message: reply });
  const [cmd, args] = impl === 'ps1'
    ? [join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'), ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', psScript]]
    : [process.execPath, [nodeScript]];
  return new Promise((resolvePromise, reject) => {
    const child = spawn(cmd, args, { cwd: project, env, stdio: ['pipe', 'ignore', 'pipe'] });
    let stderr = '';
    child.stderr.on('data', (d) => { stderr += d; });
    child.on('error', reject);
    child.on('close', (code) => resolvePromise({ code, stderr }));
    child.stdin.end(input);
  });
}
export async function simpleTurn(project, n, home, opts = {}) {
  const transcript = simpleTranscript(project, n);
  return runHook({ project, transcript, reply: `reply ${n}`, home, ...opts });
}

export function handoffFile(project, name) {
  const p = join(project, '.claude', 'handoff', name);
  return existsSync(p) ? readFileSync(p, 'utf8') : null;
}
export function logLines(project) {
  const log = handoffFile(project, 'hook-error.log');
  return log ? log.split(/\r?\n/).filter((l) => l.trim()) : [];
}
export function count(lines, re) { return lines.filter((l) => re.test(l)).length; }
export function turnWritten(project, n) {
  const last = handoffFile(project, 'last.md');
  return last !== null && last.includes(`test prompt ${n}`);
}
export function turnCount(project) {
  const h = handoffFile(project, 'history.md');
  return h ? (h.match(/# Claude Code - latest turn/g) || []).length : 0;
}
export async function twoRuns(project, home) {
  const r1 = await simpleTurn(project, 1, home);
  const log1 = logLines(project);
  const turn1 = turnWritten(project, 1);
  const r2 = await simpleTurn(project, 2, home);
  return { exit1: r1.code, exit2: r2.code, turn1, turn2: turnWritten(project, 2), log1, log2: logLines(project) };
}

// last.md without what legitimately differs between runs and implementations:
// the timestamp, CRLF (handoff.ps1 on Windows) vs LF, and the order of tools with equal counts
// (handoff.ps1 sorts by count only, so ties come out in hash order).
export function normalizeLastMd(md) {
  return md.replace(/\r\n/g, '\n').split('\n').map((line) => {
    if (line.startsWith('- **When:** ')) return '- **When:** <time>';
    if (line.startsWith('- **Tools used:** ')) return '- **Tools used:** ' + line.slice('- **Tools used:** '.length).split(', ').sort().join(', ');
    return line;
  }).join('\n');
}
// The expected last.md for a fixture (LF, whatever the checkout's line endings are).
export function readExpected(fixture) {
  return readFileSync(join(fixtureDir, 'expected', `${fixture}.last.md`), 'utf8').replace(/\r\n/g, '\n');
}
// The fixture cases shared by the parity test and the expected-output test.
export const fixtureCases = JSON.parse(readFileSync(join(fixtureDir, 'cases.json'), 'utf8'));
