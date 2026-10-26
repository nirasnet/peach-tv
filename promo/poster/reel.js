// Post a reel from your profile.
//   node reel.js --video clip.mp4 --text-file caption.txt --audience only-me|friends|public
//                [--ai-label] [--group "Group name" ...] [--dry-run]
// --ai-label turns on Meta's "AI info" label (needed for realistic AI voice or video).
// --group (repeatable) also posts the reel in that group, matched by the start of its name;
// reels must be public to share to groups.
// --dry-run fills everything in, screenshots it (reel-dry-run.png) and closes without posting.
import fs from 'node:fs';
import path from 'node:path';
import { openBrowser } from './browser.js';

const AUDIENCE = {
  'only-me': /^(Only me|เฉพาะฉัน)$/i,
  friends: /^(Friends|เพื่อน)$/i,
  public: /^(Public|สาธารณะ)$/i,
};
const L = {
  next: /^(Next|ถัดไป)$/i,
  audienceBtn: /^(Only me|Friends|Public|Close friends|Custom|เฉพาะฉัน|เพื่อน|สาธารณะ)/i,
  done: /^(Done|เสร็จสิ้น)$/i,
  ai: /^(Add AI label|เพิ่มป้ายกำกับ AI)/i,
  groups: /^(Share to groups|แชร์ไปยังกลุ่ม)/i,
  post: /^(Post|โพสต์)$/i,
  close: /^(Close|ปิด)$/i,
  discard: /^(Discard|Leave|ละทิ้ง|ออก)$/i,
};

const args = process.argv.slice(2);
const arg = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
const video = arg('--video') && path.resolve(arg('--video'));
const text = arg('--text-file') && fs.readFileSync(arg('--text-file'), 'utf8').trim();
const audience = arg('--audience');
const groups = args.flatMap((a, i) => (a === '--group' && args[i + 1] ? [args[i + 1].trim()] : []));
const aiLabel = args.includes('--ai-label');
const dryRun = args.includes('--dry-run');
if (!video || !fs.existsSync(video)) throw new Error('--video <existing file> is required');
if (!AUDIENCE[audience]) throw new Error(`--audience must be one of: ${Object.keys(AUDIENCE).join(', ')}`);
if (groups.length && audience !== 'public') throw new Error('--group needs --audience public');
if (groups.length > 9) throw new Error('Facebook allows at most 9 groups');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const norm = (s) => s.replace(/[\p{Extended_Pictographic}\u{FE0F}\u{200D}]/gu, '').replace(/\s+/g, ' ').trim();

const { context, page } = await openBrowser();
const settings = () => page.getByRole('dialog').filter({ has: page.getByRole('button', { name: L.post }) }).last();
try {
  await page.goto('https://www.facebook.com/reels/create/', { waitUntil: 'domcontentloaded' });
  const input = page.locator('input[type=file]').first();
  await input.waitFor({ state: 'attached', timeout: 30_000 });
  await input.setInputFiles(video);

  // Upload screen, then the edit screen, then "Reel settings".
  for (let step = 0; step < 3 && !(await page.getByRole('button', { name: L.post }).count()); step++) {
    const next = page.getByRole('button', { name: L.next }).last();
    await next.waitFor({ timeout: 120_000 });
    const end = Date.now() + 120_000;
    while (Date.now() < end && (await next.getAttribute('aria-disabled')) === 'true') await sleep(1000);
    await sleep(2000);
    await next.click();
    await sleep(4000);
  }
  const dlg = settings();
  await dlg.waitFor({ timeout: 30_000 });

  if (text) {
    const box = dlg.getByRole('textbox').first();
    await box.click();
    const lines = text.split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      if (i) await page.keyboard.press('Shift+Enter');
      if (lines[i]) await page.keyboard.insertText(lines[i]);
    }
    await sleep(1500);
    const typed = norm(await box.innerText());
    const want = lines.filter(Boolean);
    for (const l of [want[0], want.at(-1)]) {
      if (!typed.includes(norm(l).slice(0, 25))) throw new Error(`Description is missing: "${l.slice(0, 40)}"`);
    }
  }

  // Audience: the settings row is a button named after the current audience.
  const audBtn = dlg.getByRole('button', { name: L.audienceBtn }).first();
  if (!AUDIENCE[audience].test((await audBtn.innerText()).split('\n')[0].trim())) {
    await audBtn.click();
    const ad = page.getByRole('dialog').filter({ hasText: /Select audience|เลือกกลุ่มเป้าหมาย/ }).last();
    await ad.waitFor({ timeout: 15_000 });
    await ad.getByText(AUDIENCE[audience]).first().click();
    await sleep(800);
    await ad.getByRole('button', { name: L.done }).click();
    await sleep(2500);
  }
  const shownAud = (await settings().getByRole('button', { name: L.audienceBtn }).first().innerText()).split('\n')[0].trim();
  if (!AUDIENCE[audience].test(shownAud)) throw new Error(`Audience shows "${shownAud}", wanted ${audience}`);

  if (aiLabel) {
    const sw = settings().getByRole('switch', { name: L.ai }).first();
    if ((await sw.getAttribute('aria-checked')) !== 'true') await sw.click();
    await sleep(1000);
    if ((await sw.getAttribute('aria-checked')) !== 'true') throw new Error('AI label did not turn on');
  }

  if (groups.length) {
    await settings().getByRole('button', { name: L.groups }).first().click();
    const gd = page.getByRole('dialog').filter({ hasText: /Select groups|เลือกกลุ่ม/ }).last();
    await gd.waitFor({ timeout: 15_000 });
    await sleep(2000);
    for (const g of groups) {
      // Each group is a row with its name and a checkbox; exactly one row must carry this name.
      const name = gd.getByText(new RegExp(`^${esc(g)}`));
      if ((await name.count()) !== 1) throw new Error(`Expected 1 group starting "${g}", found ${await name.count()}`);
      const row = name.locator('xpath=ancestor::*[.//input[@type="checkbox"] or .//*[@role="checkbox"]][1]');
      const box = row.locator('input[type=checkbox], [role=checkbox]').first();
      await name.scrollIntoViewIfNeeded();
      await name.click();
      await sleep(800);
      const on = (await box.getAttribute('aria-checked')) === 'true' || (await box.isChecked().catch(() => false));
      if (!on) throw new Error(`Group "${g}" did not get ticked`);
    }
    await page.screenshot({ path: path.resolve('reel-groups.png') });
    await gd.getByRole('button', { name: L.done }).click();
    await sleep(2500);
  }

  if (dryRun) {
    await page.screenshot({ path: path.resolve('reel-dry-run.png') });
    console.log('Dry run: reel filled in, not posted (reel-dry-run.png' + (groups.length ? ', reel-groups.png' : '') + ').');
  } else {
    await settings().getByRole('button', { name: L.post }).click();
    // Facebook keeps the dialog while it uploads, then closes it.
    await settings().waitFor({ state: 'detached', timeout: 300_000 });
    await sleep(5000);
    await page.screenshot({ path: path.resolve('reel-result.png') });
    console.log('Reel posted (reel-result.png).');
  }
} catch (err) {
  await page.screenshot({ path: path.resolve(`debug-${Date.now()}.png`) }).catch(() => {});
  console.error('Failed:', err.message);
  process.exitCode = 1;
} finally {
  await context.close().catch(() => {});
}
