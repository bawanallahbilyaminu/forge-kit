#!/usr/bin/env node
// git-guard.mjs - Claude Code Stop hook for macOS and Linux (Node 18+, built-in modules only).
// When Claude Code is about to end a turn with uncommitted or unpushed work, send it back
// once to commit and push (or explain why not). Never blocks twice in a row, never errors out.
// Same behaviour and messages as git-guard.ps1 (Windows); see docs/adr/0001-cross-platform-hooks.md
// in forge-kit. Exits 0, or 2 to block with the message on stderr.

import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

function git(args, cwd) {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  if (r.error || r.status === null) return { code: -1, out: '' };
  return { code: r.status, out: r.stdout || '' };
}
function lines(text) {
  return text.split(/\r?\n/).filter((l) => l.trim() !== '');
}

function main() {
  const raw = readFileSync(0, 'utf8');
  const hook = raw.trim() ? JSON.parse(raw) : {};      // bad JSON throws -> exit 0 below
  if (hook && hook.stop_hook_active) return 0;          // already sent back once this turn

  const dir = process.env.CLAUDE_PROJECT_DIR || (hook && hook.cwd) || '';
  if (!dir) return 0;

  const inside = git(['rev-parse', '--is-inside-work-tree'], dir);
  if (inside.code !== 0 || inside.out.trim() !== 'true') return 0;   // not a git repo yet

  const status = git(['status', '--porcelain'], dir);
  const dirty = status.code === 0 ? lines(status.out).length : 0;
  let ahead = 0;
  let unpushedNote = '';
  const remotes = lines(git(['remote'], dir).out);
  const hasCommits = git(['rev-parse', '--verify', 'HEAD'], dir).code === 0;
  if (remotes.length > 0 && hasCommits) {
    if (git(['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}'], dir).code === 0) {
      const count = git(['rev-list', '--count', '@{u}..HEAD'], dir);
      if (count.code === 0) ahead = parseInt(count.out.trim(), 10) || 0;
    } else {
      ahead = 1;
      unpushedNote = ' (current branch has no upstream yet - push with -u)';
    }
  }

  if (dirty === 0 && ahead === 0) return 0;

  const parts = [];
  if (dirty > 0) parts.push(`${dirty} uncommitted file change(s)`);
  if (ahead > 0) parts.push(`unpushed commit(s)${unpushedNote}`);
  const msg = 'Git guard: this repo has ' + parts.join(' and ') + '. ' +
    'If this turn made a meaningful change, commit it now with a Conventional Commit message (reference FR IDs) and push. ' +
    'If the work is incomplete or intentionally left uncommitted, say so in one line in your reply and stop.';
  process.stderr.write(msg + '\n');
  return 2;
}

let code = 0;
try { code = main(); } catch { code = 0; }
process.exitCode = code;
