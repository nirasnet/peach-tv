import { openBrowser } from './browser.js';

const { context, page } = await openBrowser();
await page.goto('https://www.facebook.com/');

console.log('Log in to Facebook in the opened window (including 2FA).');
console.log('When you see your News Feed, close the browser window to save the session.');

// On macOS closing the last window doesn't quit Chromium, so treat it as done too.
page.on('close', () => context.close().catch(() => {}));
await new Promise((resolve) => context.on('close', resolve));
console.log('Session saved to ./profile');
