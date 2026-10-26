// Add a top-level comment to one of your posts.
//   node comment.js --find "unique text in the post" --text-file comment.txt [--dry-run]
//   node comment.js --url https://www.facebook.com/reel/<id> --text-file comment.txt [--dry-run]
// --dry-run types the comment, screenshots it (comment-dry-run.png) and clears it without sending.
// Refuses to post if a comment containing the same first line is already on the post.
import fs from 'node:fs';
import path from 'node:path';
import { openBrowser } from './browser.js';

const L = {
  actions: /Actions for this post|การดำเนินการสำหรับโพสต์นี้/i,
  comment: /^(Leave a comment|Comment|แสดงความคิดเห็น)$/i,
  box: /Write a comment|Comment as|เขียนความคิดเห็น|แสดงความคิดเห็นในฐานะ/i,
};

const args = process.argv.slice(2);
const arg = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
const find = arg('--find');
const url = arg('--url');
const text = arg('--text-file') && fs.readFileSync(arg('--text-file'), 'utf8').trim();
const dryRun = args.includes('--dry-run');
if (!(find || url) || !text) throw new Error('--find or --url, and --text-file, are required');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const lines = text.split(/\r?\n/);
const want = lines.filter(Boolean);
// Facebook renders emoji as images, so they are missing from innerText: compare without them.
const norm = (s) => s.replace(/[\p{Extended_Pictographic}\u{FE0F}\u{200D}]/gu, '').replace(/\s+/g, ' ').trim();

const { context, page } = await openBrowser();
try {
  let scope;
  if (url) {
    // A reel or post permalink: the comment box lives in the page (or a side panel), not in a feed card.
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    await sleep(6000);
    scope = page.locator('body');
    if (!(await scope.getByRole('textbox', { name: L.box }).count())) {
      await page.getByRole('button', { name: L.comment }).first().click({ timeout: 15_000 });
      await sleep(3000);
    }
  } else {
    await page.goto('https://www.facebook.com/me', { waitUntil: 'domcontentloaded' });
    const hit = page.getByText(find).first();
    await hit.waitFor({ timeout: 30_000 });
    await hit.scrollIntoViewIfNeeded();
    const post = hit.locator(`xpath=ancestor::div[.//*[@role="button" and (contains(@aria-label,"Actions for this post") or contains(@aria-label,"การดำเนินการสำหรับโพสต์นี้"))]][1]`);
    if ((await post.getByRole('button', { name: L.actions }).count()) !== 1) throw new Error('Could not pin down exactly one post');

    await post.getByRole('button', { name: L.comment }).first().click({ timeout: 15_000 });
    await sleep(3000);
    // Facebook either opens the post in a dialog or focuses an inline box under it.
    const dialog = page.getByRole('dialog').filter({ hasText: find }).last();
    scope = (await dialog.count()) ? dialog : post;
  }

  if (norm(await scope.innerText()).includes(norm(want[0]).slice(0, 40))) {
    throw new Error('A comment with this first line is already on the post');
  }

  const box = scope.getByRole('textbox', { name: L.box }).last();
  await box.waitFor({ timeout: 15_000 });
  await box.click();
  for (let i = 0; i < lines.length; i++) {
    if (i) await page.keyboard.press('Shift+Enter');
    if (lines[i]) await page.keyboard.insertText(lines[i]);
  }
  await sleep(1500);
  const typed = norm(await box.innerText());
  for (const l of [want[0], want.at(-1)]) {
    if (!typed.includes(norm(l).slice(0, 25))) throw new Error(`Comment box is missing: "${l.slice(0, 40)}"`);
  }

  if (dryRun) {
    await box.scrollIntoViewIfNeeded();
    await page.screenshot({ path: path.resolve('comment-dry-run.png') });
    console.log('Dry run: comment typed but not sent (comment-dry-run.png).');
    await box.click();
    await page.keyboard.press(process.platform === 'darwin' ? 'Meta+A' : 'Control+A');
    await page.keyboard.press('Backspace');
    await sleep(800);
  } else {
    await page.keyboard.press('Enter');
    await sleep(2000);
    const posting = page.getByText(/^(Posting|กำลังโพสต์)/);
    const end = Date.now() + 60_000;
    while (Date.now() < end && (await posting.count())) await sleep(1000);
    if (await posting.count()) throw new Error('Comment still "Posting…" after 60 s');
    await sleep(3000);
    // Facebook shortens long links when showing the comment, so check plain text lines only.
    const shown = norm(await scope.innerText());
    for (const l of want.filter((l) => !/https?:/.test(l)).slice(0, 2)) {
      if (!shown.includes(norm(l).trim().slice(0, 25))) throw new Error(`Posted comment is missing: "${l.slice(0, 40)}"`);
    }
    await page.getByText(norm(want[0]).slice(0, 20)).last().scrollIntoViewIfNeeded().catch(() => {});
    await page.screenshot({ path: path.resolve('comment-result.png') });
    console.log('Comment posted (comment-result.png).');
  }
} catch (err) {
  await page.screenshot({ path: path.resolve(`debug-${Date.now()}.png`) }).catch(() => {});
  console.error('Failed:', err.message);
  process.exitCode = 1;
} finally {
  await context.close().catch(() => {});
}
