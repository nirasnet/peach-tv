// Change who can see one of your posts.
//   node audience.js --find "unique text in the post" --audience only-me|friends|public [--dry-run]
// --dry-run selects the option, screenshots it (audience-dry-run.png) and closes without saving.
import path from 'node:path';
import { openBrowser } from './browser.js';

const AUDIENCE = {
  'only-me': /^(Only me|เฉพาะฉัน)/i,
  friends: /^(Friends|เพื่อน)(?!ของ| of| except)/i,
  public: /^(Public|สาธารณะ)/i,
};
const L = {
  actions: /Actions for this post|การดำเนินการสำหรับโพสต์นี้/i,
  editAudience: /Edit audience|Edit privacy|แก้ไขกลุ่มเป้าหมาย|แก้ไขความเป็นส่วนตัว/i,
  done: /^(Done|Save|เสร็จสิ้น|บันทึก)$/i,
  close: /^(Close|Cancel|ปิด|ยกเลิก)$/i,
};

const args = process.argv.slice(2);
const arg = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
const find = arg('--find');
const audience = arg('--audience');
const dryRun = args.includes('--dry-run');
if (!find) throw new Error('--find is required');
if (!AUDIENCE[audience]) throw new Error(`--audience must be one of: ${Object.keys(AUDIENCE).join(', ')}`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const { context, page } = await openBrowser();
try {
  await page.goto('https://www.facebook.com/me', { waitUntil: 'domcontentloaded' });
  const hit = page.getByText(find).first();
  await hit.waitFor({ timeout: 30_000 });
  await hit.scrollIntoViewIfNeeded();
  const post = hit.locator(`xpath=ancestor::div[.//*[@role="button" and (contains(@aria-label,"Actions for this post") or contains(@aria-label,"การดำเนินการสำหรับโพสต์นี้"))]][1]`);
  if ((await post.getByRole('button', { name: L.actions }).count()) !== 1) throw new Error('Could not pin down exactly one post');

  await post.getByRole('button', { name: L.actions }).first().click();
  await page.getByRole('menuitem', { name: L.editAudience }).first().click({ timeout: 15_000 });

  const dialog = page.getByRole('dialog').filter({ has: page.getByRole('radio') }).last();
  await dialog.waitFor({ timeout: 15_000 });
  const option = dialog.getByRole('radio', { name: AUDIENCE[audience] }).first();
  await option.click({ timeout: 15_000 });
  await sleep(800);
  if ((await option.getAttribute('aria-checked')) !== 'true') throw new Error(`"${audience}" did not get selected`);

  if (dryRun) {
    await page.screenshot({ path: path.resolve('audience-dry-run.png') });
    console.log(`Dry run: "${audience}" selected, not saved (audience-dry-run.png).`);
  } else {
    const done = dialog.getByRole('button', { name: L.done }).last();
    if (await done.count()) await done.click();
    await dialog.waitFor({ state: 'detached', timeout: 30_000 }).catch(() => {});
    await sleep(2500);
    await page.reload({ waitUntil: 'domcontentloaded' });
    const hit2 = page.getByText(find).first();
    await hit2.waitFor({ timeout: 30_000 });
    await hit2.scrollIntoViewIfNeeded();
    await sleep(1500);
    await page.screenshot({ path: path.resolve('audience-result.png') });
    console.log(`Audience set to ${audience} (audience-result.png).`);
  }
} catch (err) {
  await page.screenshot({ path: path.resolve(`debug-${Date.now()}.png`) }).catch(() => {});
  console.error('Failed:', err.message);
  process.exitCode = 1;
} finally {
  await context.close().catch(() => {});
}
