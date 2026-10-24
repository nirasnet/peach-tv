// Generate speech on the ElevenLabs website with a library voice (works on the free plan,
// which blocks library voices over the API). Log in once first: node login.js https://elevenlabs.io/app/sign-in
//   node elevenlabs-tts.js <voiceId> <text.txt> <out.mp3>
import fs from 'node:fs';
import path from 'node:path';
import { openBrowser } from './browser.js';

const [voiceId, textFile, out] = process.argv.slice(2);
if (!voiceId || !textFile || !out) throw new Error('usage: node elevenlabs-tts.js <voiceId> <text.txt> <out.mp3>');
const text = fs.readFileSync(textFile, 'utf8').trim();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function dismissPopups(page) {
  for (const name of [/^Got it$/, /^Close popup$/]) {
    const b = page.getByRole('button', { name }).first();
    if (await b.isVisible().catch(() => false)) { await b.click(); await sleep(500); }
  }
}

const { context, page } = await openBrowser();
try {
  await page.goto(`https://elevenlabs.io/app/voice-library?voiceId=${voiceId}`, { waitUntil: 'domcontentloaded' });
  if (/sign-in/.test(page.url())) throw new Error('Not logged in to ElevenLabs. Run: node login.js https://elevenlabs.io/app/sign-in');
  await page.getByRole('button', { name: 'Use voice' }).first().click({ timeout: 30_000 });
  await page.waitForURL(/text-to-speech/, { timeout: 30_000 });
  await sleep(2000);
  await dismissPopups(page);

  // Clear whatever was left in the editor, then type line by line.
  const clear = page.getByRole('button', { name: 'Clear text' });
  if (await clear.isVisible().catch(() => false)) { await clear.click(); await sleep(500); }
  const editor = page.locator('[contenteditable=true]').first();
  await editor.click();
  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    if (i) await page.keyboard.press('Enter');
    if (lines[i]) await page.keyboard.insertText(lines[i]);
  }
  await sleep(1000);
  const voice = await page.getByRole('button', { name: /^Select voice - / }).first().getAttribute('aria-label').catch(() => '');
  const model = await page.getByRole('button', { name: /^Select model - / }).first().getAttribute('aria-label').catch(() => '');
  console.log(`${voice} | ${model}`);

  await page.getByRole('button', { name: /Generate speech|Regenerate speech/ }).first().click();
  const dl = page.getByRole('button', { name: 'Download Audio' });
  await dl.waitFor({ timeout: 120_000 });
  for (let i = 0; i < 180 && (await dl.isDisabled()); i++) await sleep(1000);
  const [download] = await Promise.all([page.waitForEvent('download', { timeout: 60_000 }), dl.click()]);
  await download.saveAs(path.resolve(out));
  console.log(`Saved ${download.suggestedFilename()} -> ${out}`);
} catch (err) {
  await page.screenshot({ path: path.resolve(`debug-${Date.now()}.png`) }).catch(() => {});
  console.error('Failed:', err.message);
  process.exitCode = 1;
} finally {
  await context.close().catch(() => {});
}
