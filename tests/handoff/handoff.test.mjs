// handoff.test.mjs - node:test tests for plugins/code-handoff/scripts/handoff.mjs (macOS/Linux hook).
// Run with: node --test tests/handoff/handoff.test.mjs   (Node 18+, nothing to install; any OS)
// Mirrors tests/handoff/handoff.Tests.ps1 (Pester) for the cases that apply outside Windows.
// Each test uses its own temp HOME and project, so the tests run concurrently. Every hook run
// waits 2 seconds by design and the lock-timeout test waits 30.

import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, readFileSync, existsSync, mkdirSync, rmSync, utimesSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  newRoot, removeRoot, newHome, newProject, put, hookJson, execHookJson, simpleTranscript, runHook,
  simpleTurn, handoffFile, logLines, count, turnWritten, turnCount, twoRuns, normalizeLastMd,
  fixtureCases, fixtureDir, isWindows, nodeScript, readExpected,
} from './helpers.mjs';

const SKIP = /installed twice/;
const STALE = /doesn't exist/;
const sep = isWindows ? '\\\\' : '/';            // as it appears in a regex
const settingsJsonRe = new RegExp(`this project's \\.claude${sep}settings\\.json`);
const settingsLocalRe = new RegExp(`\\.claude${sep}settings\\.local\\.json`);
const userSettingsRe = isWindows ? /%USERPROFILE%\\\.claude\\settings\.json/ : /~\/\.claude\/settings\.json/;

let root;
before(() => { root = newRoot(); });
after(() => removeRoot(root));

let n = 0;
function fresh(name) {   // a new home and project for one test
  n++;
  return { home: newHome(root, `home-${n}`), project: newProject(root, `${name}-${n}`) };
}
function assertSkipped(r, fileRe) {
  assert.equal(r.exit1, 0); assert.equal(r.exit2, 0);
  assert.equal(r.turn1, false, 'turn 1 should not be written');
  assert.equal(r.turn2, false, 'turn 2 should not be written');
  assert.equal(count(r.log1, SKIP), 1);
  assert.equal(count(r.log2, SKIP), 1, 'the skip note is written once');
  assert.equal(count(r.log1.filter((l) => SKIP.test(l)), fileRe), 1, 'the note names the settings file');
  assert.equal(r.log2.length, r.log1.length);
}
function assertStale(r, fileRe) {
  assert.equal(r.exit1, 0); assert.equal(r.exit2, 0);
  assert.equal(r.turn1, true, 'turn 1 should be written');
  assert.equal(r.turn2, true, 'turn 2 should be written');
  assert.equal(count(r.log1, STALE), 1);
  assert.equal(count(r.log2, STALE), 1, 'the stale note is written once');
  assert.equal(count(r.log1.filter((l) => STALE.test(l)), fileRe), 1, 'the note names the settings file');
  assert.equal(r.log2.length, r.log1.length);
}

describe('transcript parser', { concurrency: true }, () => {
  for (const c of fixtureCases.cases) {
    test(`${c.fixture}: last.md matches expected/${c.fixture}.last.md (handoff.ps1's output)`, async () => {
      const { home, project } = fresh(c.fixture);
      const transcript = join(project, 'transcript.jsonl');
      copyFileSync(join(fixtureDir, `${c.fixture}.jsonl`), transcript);
      const r = await runHook({ project, transcript, reply: c.reply, session: fixtureCases.session, cwd: fixtureCases.cwd, home });
      assert.equal(r.code, 0);
      assert.equal(normalizeLastMd(handoffFile(project, 'last.md')), readExpected(c.fixture));
    });
  }

  test('normal turn: history, transcript copy and .gitignore are written, no hook-error.log', async () => {
    const { home, project } = fresh('normal-extra');
    const transcript = join(project, 'transcript.jsonl');
    copyFileSync(join(fixtureDir, 'normal-turn.jsonl'), transcript);
    await runHook({ project, transcript, reply: 'Added the greeting line to the README.', home });
    assert.match(handoffFile(project, 'history.md'), /Add a greeting line/);
    assert.match(handoffFile(project, 'transcript.jsonl'), /Add a greeting line/);
    assert.equal(handoffFile(project, '.gitignore').trim(), '*');
    assert.equal(handoffFile(project, 'hook-error.log'), null);
    assert.doesNotMatch(handoffFile(project, 'last.md'), /\r\n/, 'LF line endings');
  });

  test('lagging transcript: a transcript that does not exist yet still writes the turn', async () => {
    const { home, project } = fresh('no-transcript');
    const r = await runHook({ project, transcript: join(project, 'not-written-yet.jsonl'), reply: 'Reply from the hook input.', home });
    assert.equal(r.code, 0);
    const last = handoffFile(project, 'last.md');
    assert.match(last, /\(not found in transcript\)/);
    assert.match(last, /## Final reply\n\nReply from the hook input\./);
  });

  test('skips the home folder', async () => {
    const { home } = fresh('home-skip');
    const r = await simpleTurn(home, 1, home);
    assert.equal(r.code, 0);
    assert.equal(existsSync(join(home, '.claude', 'handoff')), false);
  });

  test('bad JSON on stdin: exit 0, nothing written', async () => {
    const { home, project } = fresh('bad-json');
    const res = spawnSync(process.execPath, [nodeScript],
      { input: '{ not json', env: { ...process.env, CLAUDE_PROJECT_DIR: project, HOME: home, USERPROFILE: home }, encoding: 'utf8' });
    assert.equal(res.status, 0);
    assert.equal(existsSync(join(project, '.claude', 'handoff')), false);
  });
});

describe('duplicate runs and locking', { concurrency: true }, () => {
  test('a second run for the same turn is skipped (.last-turn)', async () => {
    const { home, project } = fresh('dup-sequential');
    const transcript = simpleTranscript(project, 1);
    assert.equal((await runHook({ project, transcript, reply: 'reply 1', home })).code, 0);
    assert.equal((await runHook({ project, transcript, reply: 'reply 1', home })).code, 0);
    assert.equal(turnCount(project), 1);
    assert.ok(handoffFile(project, '.last-turn'));
  });

  test('a new turn after that is written', async () => {
    const { home, project } = fresh('dup-then-new');
    await simpleTurn(project, 1, home);
    await simpleTurn(project, 2, home);
    assert.equal(turnCount(project), 2);
    assert.equal(turnWritten(project, 2), true);
  });

  test('two runs at the same time write the turn once (lock plus .last-turn)', async () => {
    const { home, project } = fresh('dup-concurrent');
    put(join(project, '.claude', 'handoff', '.gitignore'), '*\n');
    const transcript = simpleTranscript(project, 1);
    const [a, b] = await Promise.all([
      runHook({ project, transcript, reply: 'reply 1', home }),
      runHook({ project, transcript, reply: 'reply 1', home }),
    ]);
    assert.equal(a.code, 0); assert.equal(b.code, 0);
    assert.equal(turnCount(project), 1);
    assert.equal(count(logLines(project), /timed out|Error|EEXIST|ENOENT/), 0);
  });

  test('two simultaneous first runs in a new project log no error (.gitignore race)', async () => {
    const { home, project } = fresh('dup-concurrent-first');
    const transcript = simpleTranscript(project, 1);
    await Promise.all([
      runHook({ project, transcript, reply: 'reply 1', home }),
      runHook({ project, transcript, reply: 'reply 1', home }),
    ]);
    assert.equal(turnCount(project), 1);
    assert.equal(handoffFile(project, 'hook-error.log'), null);
  });

  test('the lock is released after a run', async () => {
    const { home, project } = fresh('lock-released');
    await simpleTurn(project, 1, home);
    assert.equal(existsSync(join(project, '.claude', 'handoff', '.lock')), false);
  });

  test('when the lock is held by a live process for 30 seconds, it logs the timeout and still writes the turn', async () => {
    const { home, project } = fresh('lock-timeout');
    const lockDir = join(project, '.claude', 'handoff', '.lock');
    mkdirSync(lockDir, { recursive: true });
    writeFileSync(join(lockDir, 'owner'), JSON.stringify({ pid: process.pid, token: 'held-by-test', at: Date.now() }));
    const r = await simpleTurn(project, 1, home);
    assert.equal(r.code, 0);
    assert.equal(turnWritten(project, 1), true);
    assert.equal(count(logLines(project), /lock wait timed out, continuing without lock/), 1);
    assert.equal(existsSync(lockDir), true, "another process's lock is never removed");
  });

  test('a lock left by a process that has exited is taken over at once', async () => {
    const { home, project } = fresh('lock-dead-owner');
    const dead = spawnSync(process.execPath, ['-e', 'process.stdout.write(String(process.pid))'], { encoding: 'utf8' });
    const lockDir = join(project, '.claude', 'handoff', '.lock');
    mkdirSync(lockDir, { recursive: true });
    writeFileSync(join(lockDir, 'owner'), JSON.stringify({ pid: Number(dead.stdout), token: 'dead', at: Date.now() }));
    const t0 = Date.now();
    await simpleTurn(project, 1, home);
    assert.ok(Date.now() - t0 < 20000, 'did not wait for the timeout');
    assert.equal(turnWritten(project, 1), true);
    assert.equal(count(logLines(project), /timed out/), 0);
    assert.equal(existsSync(lockDir), false);
  });

  test('a lock folder that was never claimed (no owner file, older than 5 seconds) is taken over', async () => {
    const { home, project } = fresh('lock-unclaimed');
    const lockDir = join(project, '.claude', 'handoff', '.lock');
    mkdirSync(lockDir, { recursive: true });
    const old = new Date(Date.now() - 10000);
    utimesSync(lockDir, old, old);
    await simpleTurn(project, 1, home);
    assert.equal(turnWritten(project, 1), true);
    assert.equal(count(logLines(project), /timed out/), 0);
  });
});

describe('per-project leftovers and other handoff hooks (plugin copy)', { concurrency: true }, () => {
  const node = 'node';
  test('only .claude/commands/next.md: turn written, leftover note once, file kept', async () => {
    const { home, project } = fresh('left-next');
    put(join(project, '.claude', 'commands', 'next.md'), 'old command');
    const r = await twoRuns(project, home);
    assert.equal(r.turn1, true); assert.equal(r.turn2, true);
    assert.equal(r.log1.length, 1);
    assert.match(r.log1[0], /leftovers.*\.claude[\\/]commands[\\/]next\.md/);
    assert.equal(r.log2.length, 1);
    assert.equal(existsSync(join(project, '.claude', 'commands', 'next.md')), true);
  });

  test('all three leftovers: one note lists them all', async () => {
    const { home, project } = fresh('left-all');
    put(join(project, '.claude', 'commands', 'next.md'), 'old');
    put(join(project, '.claude', 'hooks', 'handoff.ps1'), '# old');
    put(join(project, '.claude', 'handoff-kit', 'README.md'), 'old');
    await simpleTurn(project, 1, home);
    assert.equal(turnWritten(project, 1), true);
    const l = logLines(project);
    assert.equal(l.length, 1);
    assert.match(l[0], /next\.md, \.claude[\\/]hooks[\\/]handoff\.ps1, \.claude[\\/]handoff-kit/);
  });

  test('clean project: turn written, no hook-error.log', async () => {
    const { home, project } = fresh('clean');
    await simpleTurn(project, 1, home);
    assert.equal(turnWritten(project, 1), true);
    assert.equal(handoffFile(project, 'hook-error.log'), null);
  });

  test('settings.json with only a git guard hook: turn written, no hook-error.log', async () => {
    const { home, project } = fresh('git-guard-only');
    put(join(project, '.claude', 'settings.json'), hookJson('if command -v node >/dev/null 2>&1; then node "$CLAUDE_PROJECT_DIR/.claude/hooks/git-guard.mjs"; fi'));
    await simpleTurn(project, 1, home);
    assert.equal(turnWritten(project, 1), true);
    assert.equal(handoffFile(project, 'hook-error.log'), null);
  });

  test('broken JSON in both project settings files: turn written, exit 0', async () => {
    const { home, project } = fresh('broken-settings');
    put(join(project, '.claude', 'settings.json'), '{ "hooks": { "Stop": [ broken');
    put(join(project, '.claude', 'settings.local.json'), 'not json at all');
    const r = await simpleTurn(project, 1, home);
    assert.equal(r.code, 0);
    assert.equal(turnWritten(project, 1), true);
    assert.equal(handoffFile(project, 'hook-error.log'), null);
  });

  // Live hooks (script present): the plugin copy skips. Path forms that make sense on POSIX.
  const live = [
    ['settings.local.json, ${CLAUDE_PROJECT_DIR}', 'settings.local.json', (p) => hookJson(`${node} "\${CLAUDE_PROJECT_DIR}/.claude/hooks/handoff.mjs"`), settingsLocalRe],
    ['settings.json, $CLAUDE_PROJECT_DIR in exec-form args', 'settings.json', () => execHookJson('node', ['$CLAUDE_PROJECT_DIR/.claude/hooks/handoff.mjs']), settingsJsonRe],
    ['settings.json, relative path, next to a git guard hook', 'settings.json', () => JSON.stringify({ hooks: { Stop: [{ hooks: [
      { type: 'command', command: 'node .claude/hooks/git-guard.mjs' },
      { type: 'command', command: 'node .claude/hooks/handoff.mjs' }] }] } }), settingsJsonRe],
    ['settings.local.json, absolute quoted path to an old handoff.ps1', 'settings.local.json', (p) => hookJson(`pwsh -File "${join(p, 'old-kit', 'handoff.ps1')}"`), settingsLocalRe],
    ['settings.json, exec-form arg with spaces in the path', 'settings.json', (p) => execHookJson('node', [join(p, 'old kit', 'handoff.mjs')]), settingsJsonRe],
  ];
  for (const [name, file, json, fileRe] of live) {
    test(`${name}, script present: skips, note once`, async () => {
      const { home, project } = fresh('live');
      put(join(project, '.claude', 'hooks', 'handoff.mjs'), '// old copy');
      put(join(project, 'old-kit', 'handoff.ps1'), '# old copy');
      put(join(project, 'old kit', 'handoff.mjs'), '// old copy');
      put(join(project, '.claude', file), json(project));
      assertSkipped(await twoRuns(project, home), fileRe);
    });
  }

  const userForms = [
    ['~/.claude/hooks/handoff.sh', 'sh ~/.claude/hooks/handoff.sh'],
    ['$HOME/.claude/hooks/handoff.sh', 'sh "$HOME/.claude/hooks/handoff.sh"'],
    ['${HOME}/.claude/hooks/handoff.sh', "sh '${HOME}/.claude/hooks/handoff.sh'"],
  ];
  for (const [name, command] of userForms) {
    test(`user settings.json, ${name}, script present: skips, note once`, async () => {
      const { home, project } = fresh('user-live');
      put(join(home, '.claude', 'hooks', 'handoff.sh'), '# other copy');
      put(join(home, '.claude', 'settings.json'), hookJson(command));
      assertSkipped(await twoRuns(project, home), userSettingsRe);
    });
  }

  test('settings.local.json hook with an absolute path, script missing: turn written, stale note once', async () => {
    const { home, project } = fresh('stale-local');
    put(join(project, '.claude', 'settings.local.json'), hookJson(`node "${join(project, 'old-kit', 'handoff.mjs')}"`));
    assertStale(await twoRuns(project, home), settingsLocalRe);
  });

  test('${CLAUDE_PROJECT_DIR} hook: skips while the script exists, writes turns once it is removed', async () => {
    const { home, project } = fresh('present-then-removed');
    const script = join(project, '.claude', 'hooks', 'handoff.mjs');
    put(script, '// old copy');
    put(join(project, '.claude', 'settings.local.json'), hookJson('node "${CLAUDE_PROJECT_DIR}/.claude/hooks/handoff.mjs"'));
    await simpleTurn(project, 1, home);
    assert.equal(turnWritten(project, 1), false);
    assert.equal(count(logLines(project), SKIP), 1);
    rmSync(script);
    await simpleTurn(project, 2, home);
    assert.equal(turnWritten(project, 2), true);
    const l2 = logLines(project);
    assert.equal(count(l2, STALE), 1);
    await simpleTurn(project, 3, home);
    assert.equal(turnWritten(project, 3), true);
    assert.equal(logLines(project).length, l2.length);
  });

  test('user settings.json hook with a missing ~/.claude/hooks/handoff.sh: turn written, note once', async () => {
    const { home, project } = fresh('stale-user');
    put(join(home, '.claude', 'settings.json'), hookJson('sh ~/.claude/hooks/handoff.sh'));
    assertStale(await twoRuns(project, home), userSettingsRe);
  });

  test('a hook path with an unknown variable ($SOMEVAR) is treated as missing', async () => {
    const { home, project } = fresh('unknown-var');
    put(join(project, '.claude', 'settings.json'), hookJson('node "$SOMEVAR/handoff.mjs"'));
    assertStale(await twoRuns(project, home), settingsJsonRe);
  });

  test("the plugin's own hook (${CLAUDE_PLUGIN_ROOT}) is not another copy", async () => {
    const { home, project } = fresh('own-hook');
    put(join(home, '.claude', 'settings.json'), hookJson('node "${CLAUDE_PLUGIN_ROOT}/scripts/handoff.mjs"'));
    await simpleTurn(project, 1, home);
    assert.equal(turnWritten(project, 1), true);
    assert.equal(handoffFile(project, 'hook-error.log'), null);
  });

  test('not the plugin copy (no CLAUDE_PLUGIN_ROOT): ignores other hooks and leftovers, writes the turn', async () => {
    const { home, project } = fresh('not-plugin');
    put(join(project, '.claude', 'hooks', 'handoff.ps1'), '# old copy');
    put(join(project, '.claude', 'settings.local.json'), hookJson('pwsh -File "${CLAUDE_PROJECT_DIR}/.claude/hooks/handoff.ps1"'));
    await simpleTurn(project, 1, home, { pluginRoot: '' });
    assert.equal(turnWritten(project, 1), true);
    assert.equal(handoffFile(project, 'hook-error.log'), null);
  });
});
