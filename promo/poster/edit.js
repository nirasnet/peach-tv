// Edit one of your posts and/or add a comment to it.
//   node edit.js --find "unique text in the post" [--text-file new.txt] [--comment-file c.txt] [--dry-run]
import fs from 'node:fs';
import path from 'node:path';
import { openBrowser } from './browser.js';

const L = {
  actions: /Actions for this post|การดำเนินการสำหรับโพสต์นี้/i,
  edit: /^(Edit post|แก้ไขโพสต์)$/i,
  save: /^(Save|บันทึก)$/i,
  comment: /Write a comment|Comment as|เขียนความคิดเห็น|แสดงความคิดเห็นในฐานะ/i,
};

const args = process.argv.slice(2);
const arg = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
const find = arg('--find');
const text = arg('--text-file') && fs.readFileSync(arg('--text-file'), 'utf8').trim();
const comment = arg('--comment-file') && fs.readFileSync(arg('--comment-file'), 'utf8').trim();
const dryRun = args.includes('--dry-run');
if (!find) throw new Error('--find is required');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function typeLines(page, s, newline) {
  const lines = s.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    if (i) await page.keyboard.press(newline);
    if (lines[i]) await page.keyboard.insertText(lines[i]);
  }
}

const { context, page } = await openBrowser();
try {
  await page.goto('https://www.facebook.com/me', { waitUntil: 'domcontentloaded' });
  const hit = page.getByText(find).first();
  await hit.waitFor({ timeout: 30_000 });
  await hit.scrollIntoViewIfNeeded();
  // The post container is the nearest ancestor that also holds the post's "…" menu.
  const post = hit.locator(`xpath=ancestor::div[.//div[@aria-label and @role="button"]][.//*[@role="button" and (contains(@aria-label,"Actions for this post") or contains(@aria-label,"การดำเนินการสำหรับโพสต์นี้"))]][1]`);

  if (text) {
    await post.getByRole('button', { name: L.actions }).first().click();
    await page.getByRole('menuitem', { name: L.edit }).first().click({ timeout: 15_000 });
    const dialog = page.getByRole('dialog').filter({ has: page.getByRole('textbox') }).last();
    const box = dialog.getByRole('textbox').first();
    await box.waitFor({ timeout: 15_000 });
    await box.click();
    await page.keyboard.press(process.platform === 'darwin' ? 'Meta+A' : 'Control+A');
    await page.keyboard.press('Backspace');
    await sleep(800);
    await typeLines(page, text, 'Enter');
    await page.keyboard.insertText(' ');
    await sleep(1000);
    // Never save a half-typed post: check the first and last lines made it in.
    const typed = (await box.innerText()).replace(/\s+/g, ' ');
    const lines = text.split(/\r?\n/).filter(Boolean);
    for (const l of [lines[0], lines.at(-1)]) {
      if (!typed.includes(l.replace(/\s+/g, ' ').slice(0, 30))) throw new Error(`Edit box is missing: "${l.slice(0, 40)}"`);
    }
    if (dryRun) {
      await page.screenshot({ path: path.resolve('edit-dry-run.png') });
      console.log('Dry run: edit filled in, not saved (edit-dry-run.png).');
    } else {
      await dialog.getByRole('button', { name: L.save }).last().click();
      await dialog.waitFor({ state: 'detached', timeout: 60_000 });
      console.log('Post updated.');
    }
  }

  if (comment && !dryRun) {
    await page.goto('https://www.facebook.com/me', { waitUntil: 'domcontentloaded' });
    const hit2 = page.getByText(text ? text.split('\n')[0].slice(0, 40) : find).first();
    await hit2.waitFor({ timeout: 30_000 });
    await hit2.scrollIntoViewIfNeeded();
    const post2 = hit2.locator(`xpath=ancestor::div[.//*[@role="textbox" or @role="button"]][.//*[contains(@aria-label,"comment") or contains(@aria-label,"ความคิดเห็น")]][1]`);
    let box = post2.getByRole('textbox', { name: L.comment }).first();
    if (!(await box.isVisible().catch(() => false))) {
      await post2.getByRole('button', { name: /Leave a comment|^Comment$|แสดงความคิดเห็น/i }).first().click();
      // Facebook opens the post in a dialog with the comment box at the bottom.
      box = page.getByRole('dialog').last().getByRole('textbox', { name: L.comment }).last();
    }
    await box.click({ timeout: 15_000 });
    await typeLines(page, comment, 'Shift+Enter');
    await sleep(1500); // let link previews settle
    await page.keyboard.press('Enter');
    // Closing the browser while Facebook still shows "Posting…" loses the comment.
    await sleep(2000);
    const posting = page.getByText(/^(Posting|กำลังโพสต์)/);
    const end = Date.now() + 60_000;
    while (Date.now() < end && (await posting.count())) await sleep(1000);
    if (await posting.count()) throw new Error('Comment still "Posting…" after 60 s');
    await sleep(3000);
    console.log('Comment added.');
  }
  await page.screenshot({ path: path.resolve('edit-result.png') });
} catch (err) {
  await page.screenshot({ path: path.resolve(`debug-${Date.now()}.png`) }).catch(() => {});
  console.error('Failed:', err.message);
  process.exitCode = 1;
} finally {
  await context.close().catch(() => {});
}
