import { openBrowser } from './browser.js';

const { context, page } = await openBrowser();
// node login.js [url]  (default: Facebook)
await page.goto(process.argv[2] ?? 'https://www.facebook.com/');

console.log('Log in in the opened window (including 2FA).');
console.log('When you are logged in, close the browser window to save the session.');

// On macOS closing the last window doesn't quit Chromium, so treat it as done too.
page.on('close', () => context.close().catch(() => {}));
await new Promise((resolve) => context.on('close', resolve));
console.log('Session saved to ./profile');
