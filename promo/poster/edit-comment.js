// Replace the text of one of your comments on one of your posts.
//   node edit-comment.js --url <post url> --find "text in the post" --comment "text in the comment" --text-file new.txt [--dry-run]
import fs from 'node:fs';
import path from 'node:path';
import { openBrowser } from './browser.js';

const L = {
  menu: /Edit or delete this|แก้ไขหรือลบรายการนี้/i,
  edit: /^(Edit|แก้ไข)$/i,
};

const args = process.argv.slice(2);
const arg = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
const find = arg('--find');
const url = arg('--url');
const match = arg('--comment');
const text = arg('--text-file') && fs.readFileSync(arg('--text-file'), 'utf8').trim();
const dryRun = args.includes('--dry-run');
if (!url || !find || !match || !text) throw new Error('--url, --find, --comment and --text-file are required');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const { context, page } = await openBrowser();
try {
  // Open the post on its own page; on the profile feed the comment button is easy to miss.
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.getByText(find).first().waitFor({ timeout: 30_000 });
  const dialog = page.getByRole('dialog').filter({ hasText: find }).last();
  const scope = (await dialog.count()) ? dialog : page.locator('body');
  // Load every comment so the match count is real.
  for (let i = 0; i < 10; i++) {
    const more = scope.getByRole('button', { name: /View more comments|ดูความคิดเห็นเพิ่มเติม/i }).first();
    if (!(await more.isVisible().catch(() => false))) break;
    await more.click();
    await sleep(2000);
  }

  // The comment is an article; exactly one must match so we never edit the wrong one.
  const comments = scope.getByRole('article').filter({ hasText: match });
  await comments.first().waitFor({ timeout: 30_000 });
  const n = await comments.count();
  if (n !== 1) throw new Error(`Expected 1 matching comment, found ${n}`);
  const c = comments.first();
  await c.scrollIntoViewIfNeeded();
  await c.hover();
  await sleep(800);
  await c.getByRole('button', { name: L.menu }).first().click({ timeout: 15_000 });
  // The comment menu items aren't always menuitems, so match the visible "Edit" text.
  await page.getByText(L.edit).locator('visible=true').first().click({ timeout: 15_000 });

  // The edit box replaces the comment text in place and holds the old text.
  const box = scope.getByRole('textbox').filter({ hasText: match }).first();
  await box.waitFor({ timeout: 15_000 });
  await box.click();
  await page.keyboard.press(process.platform === 'darwin' ? 'Meta+A' : 'Control+A');
  await page.keyboard.press('Backspace');
  await sleep(800);
  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    if (i) await page.keyboard.press('Shift+Enter');
    if (lines[i]) await page.keyboard.insertText(lines[i]);
  }
  await sleep(1500);
  const editBox = scope.getByRole('textbox').filter({ hasText: lines.find(Boolean).slice(0, 30) }).first();
  const typed = (await editBox.innerText()).replace(/\s+/g, ' ');
  const want = lines.filter(Boolean);
  for (const l of [want[0], want.at(-1)]) {
    if (!typed.includes(l.replace(/\s+/g, ' ').slice(0, 30))) throw new Error(`Edit box is missing: "${l.slice(0, 40)}"`);
  }
  if (dryRun) {
    await page.screenshot({ path: path.resolve('edit-comment-dry-run.png') });
    console.log('Dry run: comment edit filled in, not saved (edit-comment-dry-run.png).');
    await page.keyboard.press('Escape');
  } else {
    await page.keyboard.press('Enter');
    await sleep(5000);
    // Facebook shortens long links when showing the comment, so check plain text lines only.
    const shown = await scope.innerText();
    for (const l of want.filter((l) => !/https?:/.test(l)).slice(-2)) {
      if (!shown.includes(l.trim().slice(0, 25))) throw new Error(`Saved comment is missing: "${l.slice(0, 40)}"`);
    }
    await page.screenshot({ path: path.resolve('edit-comment-result.png') });
    console.log('Comment updated.');
  }
} catch (err) {
  await page.screenshot({ path: path.resolve(`debug-${Date.now()}.png`) }).catch(() => {});
  console.error('Failed:', err.message);
  process.exitCode = 1;
} finally {
  await context.close().catch(() => {});
}
