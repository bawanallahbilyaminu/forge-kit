// update-expected.mjs - regenerate tests/fixtures/handoff/expected/*.last.md from handoff.ps1.
// Windows only: run `node tests/handoff/update-expected.mjs` after an intended change to the
// last.md layout, then check the diff. handoff.ps1 is the reference; handoff.mjs must match it
// (see parity.test.mjs and the expected-output test in handoff.test.mjs).

import { mkdirSync, writeFileSync, copyFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  isWindows, newRoot, removeRoot, newHome, newProject, runHook, handoffFile,
  normalizeLastMd, fixtureCases, fixtureDir,
} from './helpers.mjs';

if (!isWindows) {
  console.error('update-expected.mjs needs Windows PowerShell 5.1 (handoff.ps1 is the reference).');
  process.exit(1);
}
const root = newRoot();
try {
  const home = newHome(root, 'home');
  const outDir = join(fixtureDir, 'expected');
  mkdirSync(outDir, { recursive: true });
  for (const c of fixtureCases.cases) {
    const project = newProject(root, c.fixture);
    const transcript = join(project, 'transcript.jsonl');
    copyFileSync(join(fixtureDir, `${c.fixture}.jsonl`), transcript);
    const r = await runHook({ impl: 'ps1', project, transcript, reply: c.reply, session: fixtureCases.session, cwd: fixtureCases.cwd, home });
    const md = handoffFile(project, 'last.md');
    if (r.code !== 0 || md === null) throw new Error(`handoff.ps1 failed for ${c.fixture} (exit ${r.code})`);
    writeFileSync(join(outDir, `${c.fixture}.last.md`), normalizeLastMd(md));
    console.log(`wrote expected/${c.fixture}.last.md`);
  }
} finally {
  removeRoot(root);
}
