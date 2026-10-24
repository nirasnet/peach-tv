// Usage:
//   node post.js --text "Hello" [--media a.jpg b.mp4 ...] [--dry-run]
//   node post.js --text-file caption.txt --media clip.mp4 --audience only-me
import fs from 'node:fs';
import path from 'node:path';
import { openBrowser } from './browser.js';

// UI labels in English + Thai. Add your language here if Facebook shows something else.
const L = {
  composer: /What's on your mind|คุณคิดอะไรอยู่/i,
  photoVideo: /^(Photo\/video|รูปภาพ\/วิดีโอ)$/i,
  next: /^(Next|ถัดไป)$/i,
  post: /^(Post|โพสต์)$/i,
  uploading: /uploading|กำลังอัปโหลด/i,
  privacy: /Edit privacy|แก้ไขความเป็นส่วนตัว/i,
  done: /^(Done|เสร็จสิ้น|Save|บันทึก)$/i,
};

// Audience choices. Facebook remembers the last one as your default for later posts.
const AUDIENCE = {
  'only-me': /Only me|เฉพาะฉัน/i,
  friends: /^(Friends|เพื่อน)(?!ของ| of)/i,
  public: /Public|สาธารณะ/i,
};

function parseArgs(argv) {
  const opts = { text: '', media: [], dryRun: false, audience: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--text') opts.text = argv[++i] ?? '';
    else if (a === '--text-file') opts.text = fs.readFileSync(argv[++i], 'utf8').trim();
    else if (a === '--dry-run') opts.dryRun = true;
    else if (a === '--no-wait') opts.noWait = true;
    else if (a === '--audience') {
      opts.audience = argv[++i];
      if (!AUDIENCE[opts.audience]) throw new Error(`--audience must be one of: ${Object.keys(AUDIENCE).join(', ')}`);
    }
    else if (a === '--media') {
      while (argv[i + 1] && !argv[i + 1].startsWith('--')) opts.media.push(path.resolve(argv[++i]));
    } else throw new Error(`Unknown argument: ${a}`);
  }
  if (!opts.text && !opts.media.length) throw new Error('Nothing to post: give --text and/or --media');
  for (const f of opts.media) if (!fs.existsSync(f)) throw new Error(`File not found: ${f}`);
  return opts;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitEnabled(button, timeoutMs) {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    if ((await button.isVisible()) && (await button.getAttribute('aria-disabled')) !== 'true') return;
    await sleep(500);
  }
  throw new Error('Timed out waiting for the button to become enabled');
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const hasVideo = opts.media.some((f) => /\.(mp4|mov|m4v|webm|avi|mkv)$/i.test(f));
  const { context, page } = await openBrowser();

  try {
    await page.goto('https://www.facebook.com/', { waitUntil: 'domcontentloaded' });
    if (/login|checkpoint/.test(page.url()) || (await page.locator('input[name="pass"]').count())) {
      throw new Error('Not logged in. Run `npm run login` first.');
    }

    // 1. Open the composer
    await page.getByRole('button', { name: L.composer }).first().click({ timeout: 30_000 });
    const dialog = page.getByRole('dialog').filter({ has: page.getByRole('textbox') }).last();
    await dialog.waitFor({ timeout: 30_000 });

    // 1b. Audience. Verified afterwards so a failure can never post more widely than asked.
    if (opts.audience) {
      const re = AUDIENCE[opts.audience];
      const privacyBtn = dialog.getByRole('button', { name: L.privacy }).first();
      await privacyBtn.click({ timeout: 15_000 });
      await page.getByRole('radio', { name: re }).first().click({ timeout: 15_000 });
      const done = page.getByRole('dialog').getByRole('button', { name: L.done }).last();
      if (await done.isVisible().catch(() => false)) await done.click();
      await sleep(1500);
      const label = (await dialog.getByRole('button', { name: L.privacy }).first().getAttribute('aria-label')) ?? '';
      if (!re.test(label)) throw new Error(`Could not set audience to ${opts.audience} (composer says: "${label}")`);
      console.log(`Audience: ${label}`);
    }

    // 2. Type the text (line by line so newlines survive)
    if (opts.text) {
      await dialog.getByRole('textbox').first().click();
      const lines = opts.text.split(/\r?\n/);
      for (let i = 0; i < lines.length; i++) {
        if (i) await page.keyboard.press('Enter');
        if (lines[i]) await page.keyboard.insertText(lines[i]);
      }
      await page.keyboard.insertText(' '); // closes the #hashtag suggestion menu
    }

    // 3. Attach photos/videos
    if (opts.media.length) {
      let input = dialog.locator('input[type="file"]');
      if (!(await input.count())) {
        await dialog.getByRole('button', { name: L.photoVideo }).first().click();
        await input.first().waitFor({ state: 'attached', timeout: 15_000 });
      }
      await input.first().setInputFiles(opts.media);
      await sleep(3000);
    }

    // 4. Some accounts get a "Next" step (audience / settings) before "Post"
    const mediaTimeout = hasVideo ? 30 * 60_000 : 3 * 60_000;
    const next = dialog.getByRole('button', { name: L.next });
    if (await next.first().isVisible().catch(() => false)) {
      await waitEnabled(next.first(), mediaTimeout);
      await next.first().click();
    }
    const postBtn = page.getByRole('dialog').getByRole('button', { name: L.post }).last();
    await waitEnabled(postBtn, mediaTimeout);

    if (opts.dryRun) {
      await page.screenshot({ path: path.resolve('dry-run.png') });
      console.log('Dry run: everything is filled in but not posted (see dry-run.png).');
      if (opts.noWait) return;
      console.log('Close the window when done.');
      page.on('close', () => context.close().catch(() => {}));
      await new Promise((r) => context.on('close', r));
      return;
    }

    // 5. Publish and wait for upload to finish
    await postBtn.click();
    await page.getByRole('dialog').filter({ has: postBtn }).waitFor({ state: 'detached', timeout: mediaTimeout });
    if (opts.media.length) {
      const end = Date.now() + mediaTimeout;
      await sleep(5000);
      while (Date.now() < end && (await page.getByText(L.uploading).first().isVisible().catch(() => false))) {
        await sleep(3000);
      }
    }
    await sleep(5000);
    console.log('Posted.');
  } catch (err) {
    const shot = path.resolve(`debug-${Date.now()}.png`);
    await page.screenshot({ path: shot, fullPage: false }).catch(() => {});
    console.error(`Failed: ${err.message}\nScreenshot: ${shot}`);
    process.exitCode = 1;
  } finally {
    await context.close().catch(() => {});
  }
}

main();
