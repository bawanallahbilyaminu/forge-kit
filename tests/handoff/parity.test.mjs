// parity.test.mjs - handoff.mjs and handoff.ps1 write the same last.md for the shared fixtures.
// Runs only on Windows, where both implementations are available. Elsewhere the expected-output
// test in handoff.test.mjs checks handoff.mjs against tests/fixtures/handoff/expected/, which
// update-expected.mjs generates from handoff.ps1.
// Compared after normalizeLastMd: timestamp line, CRLF vs LF, and the order of tied tool counts.

import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { copyFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  isWindows, newRoot, removeRoot, newHome, newProject, runHook, handoffFile,
  normalizeLastMd, fixtureCases, fixtureDir, readExpected,
} from './helpers.mjs';

describe('handoff.mjs and handoff.ps1 parity', { skip: !isWindows && 'needs Windows PowerShell (handoff.ps1)', concurrency: 5 }, () => {
  let root;
  let home;
  before(() => { root = newRoot(); home = newHome(root, 'home'); });
  after(() => removeRoot(root));

  async function lastMd(impl, fixture, reply) {
    const project = newProject(root, `${impl}-${fixture}`);
    const transcript = join(project, 'transcript.jsonl');
    copyFileSync(join(fixtureDir, `${fixture}.jsonl`), transcript);
    const r = await runHook({ impl, project, transcript, reply, session: fixtureCases.session, cwd: fixtureCases.cwd, home });
    assert.equal(r.code, 0, `${impl} exit code`);
    const md = handoffFile(project, 'last.md');
    assert.notEqual(md, null, `${impl} wrote no last.md`);
    return normalizeLastMd(md);
  }

  for (const c of fixtureCases.cases) {
    test(`${c.fixture}: same last.md from both, and it matches expected/${c.fixture}.last.md`, async () => {
      const [fromPs, fromNode] = await Promise.all([lastMd('ps1', c.fixture, c.reply), lastMd('node', c.fixture, c.reply)]);
      assert.equal(fromNode, fromPs);
      assert.equal(fromPs, readExpected(c.fixture),
        'handoff.ps1 output changed: run node tests/handoff/update-expected.mjs and review the diff');
    });
  }
});
