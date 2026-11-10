#!/usr/bin/env node
// handoff.mjs - Claude Code Stop hook for macOS and Linux (Node 18+, built-in modules only).
// After every Claude Code turn, writes a readable summary to .claude/handoff/ so a planning
// chat can read what Claude Code did without screenshots:
//   handoff/last.md          latest turn (prompt, reply, files changed, commands, errors)
//   handoff/history.md       every turn appended, newest at the bottom
//   handoff/transcript.jsonl copy of the latest session's full transcript
// The Node port of handoff.ps1 (Windows); see docs/adr/0001-cross-platform-hooks.md in forge-kit.
// last.md has the same layout as handoff.ps1's, with LF line endings. Always exits 0.
// As the plugin copy (CLAUDE_PLUGIN_ROOT set), it steps aside when another handoff Stop hook
// whose script exists is active in ~/.claude/settings.json or the project's settings, notes a
// hook whose script is missing, and notes leftovers from the old per-project setup.

import {
  readFileSync, writeFileSync, appendFileSync, existsSync, statSync, mkdirSync,
  rmSync, renameSync, realpathSync,
} from 'node:fs';
import { join, resolve, isAbsolute, sep } from 'node:path';
import { homedir } from 'node:os';
import { createHash, randomBytes } from 'node:crypto';

const LOCK_WAIT_MS = 30000;       // same as handoff.ps1's mutex wait
const LOCK_STALE_MS = 60000;      // the hook times out after 30 s, so an older lock is abandoned
const LOCK_UNCLAIMED_MS = 5000;   // a lock dir with no owner file this old was never claimed
const isWindows = process.platform === 'win32';
const HANDOFF_SCRIPT = /handoff\.(ps1|mjs|sh)$/i;

function sleep(ms) { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); }
function pad(n) { return String(n).padStart(2, '0'); }
function stamp(d = new Date()) {   // local time, like Get-Date -Format s
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}
function clip(s, n) {
  if (s === null || s === undefined) return '';
  s = String(s);
  return s.length > n ? s.slice(0, n) + ' ...[truncated]' : s;
}
function sha1Hex(text) { return createHash('sha1').update(String(text), 'utf8').digest('hex').toUpperCase(); }
function textOf(content) {
  if (content === null || content === undefined) return '';
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.filter((b) => b && b.type === 'text').map((b) => b.text).join('\n');
}
function isFile(p) { try { return statSync(p).isFile(); } catch { return false; } }
function samePath(a, b) {
  const norm = (p) => { let r = resolve(p); try { r = realpathSync(p); } catch { } r = r.replace(/[\\/]+$/, ''); return isWindows ? r.toLowerCase() : r; };
  return norm(a) === norm(b);
}
function log(handoff, line) { appendFileSync(join(handoff, 'hook-error.log'), `${stamp()} ${line}\n`); }
function rel(p) { return p.split('/').join(sep); }   // show .claude/... with this OS's separator

// ---- the plugin-copy guard: other handoff Stop hooks in settings files ----

// Expands one path token from a hook command into a full path, or null if it can't.
function expandHookPath(t, projectDir, userHome) {
  try {
    t = String(t).trim().replace(/;+$/, '').replace(/^["']+|["']+$/g, '');
    if (!t) return null;
    const pairs = [
      [/\$\{CLAUDE_PROJECT_DIR\}/gi, projectDir], [/\$env:CLAUDE_PROJECT_DIR(?!\w)/gi, projectDir],
      [/\$CLAUDE_PROJECT_DIR(?!\w)/gi, projectDir], [/%CLAUDE_PROJECT_DIR%/gi, projectDir],
      [/\$\{USERPROFILE\}/gi, userHome], [/\$env:USERPROFILE(?!\w)/gi, userHome],
      [/\$USERPROFILE(?!\w)/gi, userHome], [/%USERPROFILE%/gi, userHome],
      [/\$\{HOME\}/gi, userHome], [/\$env:HOME(?!\w)/gi, userHome], [/\$HOME(?!\w)/gi, userHome],
    ];
    for (const [re, val] of pairs) {
      if (re.test(t)) {
        if (!val) return null;
        re.lastIndex = 0;
        t = t.replace(re, () => val);
      }
    }
    if (/^~([\\/]|$)/.test(t)) {
      if (!userHome) return null;
      t = userHome + t.slice(1);
    }
    if (isWindows && /^\/[a-zA-Z]\//.test(t)) t = t[1] + ':' + t.slice(2);   // Git Bash /c/...
    if (/\$|%[^%]+%/.test(t)) return null;   // a variable we don't know
    if (!isAbsolute(t)) {
      if (!projectDir) return null;
      t = resolve(projectDir, t);
    }
    return resolve(t);
  } catch { return null; }
}
// Finds the handoff script path in a hook's command (parts[0]) and args (the rest), or null.
function hookScriptPath(parts, projectDir, userHome) {
  for (let i = 0; i < parts.length; i++) {
    const p = String(parts[i] || '');
    if (!/handoff\.(ps1|mjs|sh)/i.test(p)) continue;
    // An exec-form arg (not the command string) that is the whole path, possibly with spaces
    if (i > 0 && HANDOFF_SCRIPT.test(p.trim().replace(/^["']+|["']+$/g, ''))) {
      const x = expandHookPath(p, projectDir, userHome);
      if (x) return x;
    }
    // Otherwise a token of a shell command string, quoted or not
    for (const m of p.matchAll(/"([^"]*)"|'([^']*)'|(\S+)/g)) {
      const tok = (m[1] || m[2] || m[3] || '').trim().replace(/;+$/, '').replace(/^["']+|["']+$/g, '');
      if (HANDOFF_SCRIPT.test(tok)) return expandHookPath(tok, projectDir, userHome);
    }
  }
  return null;
}
// 'active': a Stop hook in this settings file runs another handoff script that exists.
// 'stale': there are such hooks, but none of their scripts exists or can be resolved.
// 'none': no such hook, no file, or bad JSON.
function foreignHandoffHook(settingsPath, pluginRoot, projectDir, userHome) {
  try {
    if (!settingsPath || !existsSync(settingsPath)) return 'none';
    const s = JSON.parse(readFileSync(settingsPath, 'utf8'));
    if (!s || !s.hooks) return 'none';
    const root = String(pluginRoot || '').replace(/\\/g, '/').replace(/\/+$/, '').toLowerCase();
    let foundAny = false;
    for (const g of [].concat(s.hooks.Stop || [])) {
      if (!g) continue;
      for (const h of [].concat(g.hooks || [])) {
        if (!h) continue;
        const parts = [String(h.command || '')];
        if (h.args) for (const a of [].concat(h.args)) parts.push(String(a));
        const c = parts.join(' ').replace(/\\/g, '/').toLowerCase();
        if (!/handoff\.(ps1|mjs|sh)/.test(c)) continue;
        if (c.includes('claude_plugin_root')) continue;
        if (root && c.includes(root)) continue;
        foundAny = true;
        const script = hookScriptPath(parts, projectDir, userHome);
        if (script && isFile(script)) return 'active';
      }
    }
    return foundAny ? 'stale' : 'none';
  } catch { return 'none'; }
}

// ---- the per-project lock: an atomic mkdir, released in finally ----

function pidAlive(pid) {
  try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; }
}
function tryLock(lockDir, token) {
  try { mkdirSync(lockDir); } catch (e) { if (e.code === 'EEXIST') return false; throw e; }
  writeFileSync(join(lockDir, 'owner'), JSON.stringify({ pid: process.pid, token, at: Date.now() }));
  return true;
}
function lockIsStale(lockDir) {
  let st;
  try { st = statSync(lockDir); } catch { return false; }   // gone: just try again
  const age = Date.now() - st.mtimeMs;
  let owner = null;
  try { owner = JSON.parse(readFileSync(join(lockDir, 'owner'), 'utf8')); } catch { }
  if (owner && owner.pid) { if (!pidAlive(owner.pid)) return true; }
  else if (age > LOCK_UNCLAIMED_MS) return true;
  return age > LOCK_STALE_MS;
}
function acquireLock(lockDir, token) {
  const deadline = Date.now() + LOCK_WAIT_MS;
  for (;;) {
    if (tryLock(lockDir, token)) return true;
    if (lockIsStale(lockDir)) {
      // Rename first, so only one waiter clears a given stale lock.
      const aside = `${lockDir}.stale-${token}`;
      try { renameSync(lockDir, aside); rmSync(aside, { recursive: true, force: true }); } catch { }
      continue;
    }
    if (Date.now() >= deadline) return false;
    sleep(100);
  }
}
function releaseLock(lockDir, token) {
  try {
    const owner = JSON.parse(readFileSync(join(lockDir, 'owner'), 'utf8'));
    if (owner.token === token) rmSync(lockDir, { recursive: true, force: true });
  } catch { }
}

// ---- main ----

function main(state) {
  const hook = JSON.parse(readFileSync(0, 'utf8'));
  const userHome = homedir();

  // Installed once for all projects: write into the current project's .claude/handoff
  const projectDir = String(process.env.CLAUDE_PROJECT_DIR || hook.cwd || '');
  if (!projectDir) return;
  if (samePath(realpathSync(projectDir), userHome)) return;   // skip the home folder
  const handoff = join(projectDir, '.claude', 'handoff');
  mkdirSync(handoff, { recursive: true });
  state.handoff = handoff;
  const gi = join(handoff, '.gitignore');
  if (!existsSync(gi)) {
    // Two first runs in a new project can race here. If this write fails but the file now
    // exists, the other run wrote it: ignore that. Anything else goes to the outer catch.
    try { writeFileSync(gi, '*\n'); } catch (e) { if (!existsSync(gi)) throw e; }
  }

  const pluginRoot = process.env.CLAUDE_PLUGIN_ROOT;
  if (pluginRoot) {
    // Leftovers from the old per-project setup: note them once. Never delete, never skip for these.
    try {
      const leftMarker = join(handoff, '.leftovers-noted');
      if (!existsSync(leftMarker)) {
        const found = ['.claude/commands/next.md', '.claude/hooks/handoff.ps1', '.claude/handoff-kit']
          .filter((r) => existsSync(join(projectDir, r))).map(rel);
        if (found.length > 0) {
          log(handoff, 'Found leftovers from the old per-project code-handoff setup in this project: ' +
            found.join(', ') + '. The code-handoff plugin now provides the hook and the command ' +
            `(/code-handoff:next), so these can be deleted. If a Stop hook in ${rel('.claude/settings.json')} or ` +
            `${rel('.claude/settings.local.json')} still runs a handoff script, remove that hook entry first. Keep ${rel('.claude/handoff/')}. ` +
            "See 'Upgrading from the per-project setup' in the code-handoff README. Nothing was deleted, and turns are still written.");
          writeFileSync(leftMarker, stamp());
        }
      }
    } catch { }

    // Double install: if another handoff Stop hook is active and its script exists, let that
    // copy write the turn and stop here (before the lock). A hook whose script is missing
    // can't write anything, so note it once and carry on writing the turn here.
    const userLabel = isWindows ? '%USERPROFILE%\\.claude\\settings.json' : '~/.claude/settings.json';
    const sources = [
      { path: join(userHome, '.claude', 'settings.json'), marker: '.double-install-noted', staleMarker: '.stale-hook-noted-user', label: userLabel, user: true },
      { path: join(projectDir, '.claude', 'settings.json'), marker: '.project-hook-noted', staleMarker: '.stale-hook-noted-project', label: `this project's ${rel('.claude/settings.json')}` },
      { path: join(projectDir, '.claude', 'settings.local.json'), marker: '.project-local-hook-noted', staleMarker: '.stale-hook-noted-local', label: `this project's ${rel('.claude/settings.local.json')}` },
    ];
    for (const src of sources) {
      const found = foreignHandoffHook(src.path, pluginRoot, projectDir, userHome);
      if (found === 'none') continue;
      if (found === 'stale') {
        try {
          const m = join(handoff, src.staleMarker);
          if (!existsSync(m)) {
            log(handoff, `A Stop hook in ${src.label} runs a handoff script that doesn't exist, or whose path can't be resolved. ` +
              'The plugin copy ignores that hook and writes each turn itself. The hook fails on every turn, so remove that ' +
              `handoff entry from ${src.label} and keep its other settings. ` +
              "See 'Upgrading from the per-project setup' in the code-handoff README.");
            writeFileSync(m, stamp());
          }
        } catch { }
        continue;
      }
      const m = join(handoff, src.marker);
      if (!existsSync(m)) {
        if (src.user) {
          log(handoff, `code-handoff is installed twice: as the Claude Code plugin and as another handoff Stop hook in ${src.label}. ` +
            'The plugin copy now skips so each turn is written once. ' +
            `To keep only the plugin, remove that handoff Stop hook entry from ${src.label} and keep its other settings.`);
        } else {
          log(handoff, 'code-handoff is installed twice: as the Claude Code plugin and as a per-project Stop hook ' +
            `in ${src.label}. The plugin copy now skips so each turn is written once by the project copy. ` +
            `To keep only the plugin, remove the handoff Stop hook entry from ${src.label.replace("this project's ", '')} and keep its other settings. ` +
            "If you delete that hook's script but keep the entry, the plugin notices and writes the turns itself. " +
            "See 'Upgrading from the per-project setup' in the code-handoff README.");
        }
        writeFileSync(m, stamp());
      }
      return;
    }
  }

  // Serialise runs for this project: Claude Code can fire the Stop hook twice for one turn.
  // Released in the outer finally, which every path after this point goes through.
  state.lockDir = join(handoff, '.lock');
  state.token = randomBytes(8).toString('hex');
  state.locked = acquireLock(state.lockDir, state.token);
  if (!state.locked) log(handoff, 'lock wait timed out, continuing without lock');

  sleep(2000);   // the transcript is written asynchronously; give it a moment

  // --- read the transcript (Claude Code may still be writing it) ---
  let all = '';
  const tp = String(hook.transcript_path || '');
  if (tp && existsSync(tp)) all = readFileSync(tp, 'utf8');
  const lines = all.split('\n');

  // --- walk back to the last real user prompt ---
  const events = [];
  let prompt = '';
  let scanned = 0;
  for (let i = lines.length - 1; i >= 0 && scanned < 5000; i--) {
    const l = lines[i].trim();
    if (!l) continue;
    scanned++;
    let e;
    try { e = JSON.parse(l); } catch { continue; }
    if (!e || typeof e !== 'object') continue;
    if (e.isSidechain) continue;
    if (e.type === 'user' && !e.isMeta) {
      const c = e.message && e.message.content;
      const isToolResult = Array.isArray(c) && c.some((b) => b && b.type === 'tool_result');
      if (!isToolResult) {
        const t = textOf(c);
        if (t && !/^\s*(<local-command|<system-reminder|\[Request interrupted)/i.test(t)) { prompt = t; break; }
      }
    }
    events.unshift(e);
  }

  // --- collect what happened after the prompt ---
  const edited = new Map();
  const commands = [];
  const errors = [];
  const texts = [];
  const toolCounts = new Map();
  const toolLabel = new Map();
  for (const e of events) {
    const c = e.message && e.message.content;
    if (!Array.isArray(c)) continue;
    if (e.type === 'assistant') {
      for (const b of c) {
        if (!b) continue;
        if (b.type === 'text' && b.text) texts.push(String(b.text));
        else if (b.type === 'tool_use') {
          const n = String(b.name || '');
          toolCounts.set(n, (toolCounts.get(n) || 0) + 1);
          const inp = b.input || {};
          let label = n;
          if (['Edit', 'Write', 'MultiEdit', 'NotebookEdit'].includes(n)) {
            const p = String(inp.file_path || inp.notebook_path || '');
            if (p) edited.set(p, n);
            label = `${n} ${p}`;
          } else if (['Bash', 'PowerShell'].includes(n)) {
            commands.push(clip(inp.command, 300));
            label = `${n}: ` + clip(inp.command, 120);
          } else if (inp.file_path) label = `${n} ${inp.file_path}`;
          else if (inp.pattern) label = `${n} ${inp.pattern}`;
          toolLabel.set(String(b.id), label);
        }
      }
    } else if (e.type === 'user') {
      for (const b of c) {
        if (b && b.type === 'tool_result' && b.is_error) {
          const what = toolLabel.get(String(b.tool_use_id)) || 'tool';
          const msg = clip(textOf(b.content), 500).replace(/\r?\n/g, ' ');
          errors.push(`- **${what}** -> ${msg}`);
        }
      }
    }
  }

  let reply = hook.last_assistant_message ? String(hook.last_assistant_message) : '';
  if (!reply && texts.length > 0) reply = texts[texts.length - 1];
  if (!prompt) prompt = '(not found in transcript)';

  // --- skip a turn that was already written (duplicate hook run); same key as handoff.ps1 ---
  const turnKey = sha1Hex(`${hook.session_id ?? ''}|${prompt}|${reply}`);
  const keyFile = join(handoff, '.last-turn');
  const duplicate = existsSync(keyFile) && readFileSync(keyFile, 'utf8').trim() === turnKey;
  if (duplicate) return;

  // --- build the markdown ---
  const out = [];
  const d = new Date();
  out.push('# Claude Code - latest turn', '');
  out.push(`- **When:** ${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`);
  out.push(`- **Session:** ${hook.session_id ?? ''}`);
  out.push(`- **Working dir:** ${hook.cwd ?? ''}`);
  if (toolCounts.size > 0) {
    // Most used first; ties by name, so the order is stable
    const summary = [...toolCounts.entries()].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
      .map(([k, v]) => `${k} x${v}`).join(', ');
    out.push(`- **Tools used:** ${summary}`);
  }
  out.push('');
  out.push('## Prompt', '', clip(prompt, 6000), '');
  if (texts.length > 1) {
    out.push('## Progress notes along the way', '');
    for (let k = 0; k < texts.length - 1; k++) out.push('- ' + clip(texts[k], 400).replace(/\r?\n/g, ' '));
    out.push('');
  }
  out.push('## Final reply', '', clip(reply, 12000), '');
  out.push(`## Files changed (${edited.size})`, '');
  for (const [k, v] of edited) out.push(`- ${k} (${v})`);
  if (edited.size === 0) out.push('- none');
  out.push('');
  out.push(`## Commands run (${commands.length})`, '');
  if (commands.length > 0) { out.push('```', ...commands, '```'); } else out.push('- none');
  out.push('');
  out.push(`## Errors (${errors.length})`, '');
  out.push(...errors);
  if (errors.length === 0) out.push('- none');
  const md = out.join('\n') + '\n';

  // --- write outputs ---
  writeFileSync(join(handoff, 'last.md'), md);
  const hist = join(handoff, 'history.md');
  appendFileSync(hist, '\n\n---\n\n' + md);
  if (statSync(hist).size > 600 * 1024) {
    const h = readFileSync(hist, 'utf8');
    writeFileSync(hist, h.slice(h.length - 400000));
  }
  writeFileSync(keyFile, turnKey);
  if (all) {
    try { writeFileSync(join(handoff, 'transcript.jsonl'), all); } catch { }
  }
}

const state = { handoff: null, lockDir: null, token: null, locked: false };
try {
  main(state);
} catch (e) {
  try { if (state.handoff) log(state.handoff, `${e && e.message ? e.message : e}`); } catch { }
} finally {
  if (state.locked) releaseLock(state.lockDir, state.token);
}
process.exitCode = 0;
