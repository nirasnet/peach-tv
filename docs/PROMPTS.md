# Prompts used for the Facebook post

The announcement post (caption, screenshots, the 16-second video and the posting itself) was made by
[Claude Code](https://claude.com/claude-code) from the prompts below, typed by a person who also logged in to
Facebook and checked the result. They're quoted as typed.

## 1. Build the poster

> can you automate post facebook for me by build in agent browser with i login facebook for you

The agent asked three questions (where to post, how to run it, what kind of content). The answers were:
personal profile, a Playwright script, and text with images and video. It then wrote
[`promo/poster/`](../promo/poster). That's a Playwright script that keeps a logged-in Chromium profile on disk,
so the human logs in once by hand and the script never sees the password.

## 2. Make the post

> ok now i want to pose about viral cleanyour.tv จะเล่าแนวๆ ว่าตามกระแสนิดนึง ปรับ TV ให้รองรับ kid mode และควบคุม ตั้งค่า ผ่านทาง iphone ได้ build in vpn ควบคุมจาก นอกบ้านได้ cap screen ตัวอย่า จอทีวี parrent mode, kid mode, lock screen mode , iphone app main , และทำ vdo โดยใช้ hyperframe นำเสนอสั้นๆ และลองโพสแบบ only me ดูก่อน

What the agent did:

- **TV screenshots:** used the agent's own API (`GET /screenshot`) for Parent mode, Kid mode (`POST /kids`) and a
  lock (`POST /lock`), then put the TV back the way it was.
- **iPhone screenshot:** taken from the iOS Simulator.
- **Video:** built [`promo/video/index.html`](../promo/video/index.html), a 1080×1080
  [HyperFrames](https://hyperframes.heygen.com) composition (HTML + GSAP), and rendered it with
  `npx hyperframes render`.
- **Post:** added `--audience only-me` to the poster, which refuses to publish if it can't confirm the audience,
  and posted it privately.

## 3. Rewrite it and open-source the project

> ok ปรับ wording ให้ดูเหมือน ไม่ใช่ ai โพส โพสแนวๆ เหมือน พี่หนูเนยก็ได้ https://www.facebook.com/nuuneoi/?locale=th_TH ตอนจบ ล่างสุด ค่อยบอกว่า โพสโดย ai นะ , และอยากให้ปรับ github ของ project นี้ แชร์ได้ public ได้ แต่ระวังข้อมูล ความลับอะไรเอาออกให้หมดด้วยนะ ข้อมูล technical อะไร ก็ไปอธิบายใน githnub แล้วกัน รวมถึง prompt ที่สร้าง ให้ บอกในโพส ว่า prompt ที่สร้าง ใน comment ด้วยละกัน

What the agent did:

- **Caption:** rewrote it in a casual, first-person tone, with a note at the end saying AI wrote it. The result
  is in [`promo/caption.txt`](../promo/caption.txt).
- **Secrets:** checked the private repo for anything that shouldn't be public: the TV token, the unlock code,
  App Store Connect key IDs, the Apple Team ID, contact details, and home and tailnet IP addresses. It published
  this repo as a fresh history with all of those removed or turned into environment variables.
- **Comment:** added a comment to the post with the GitHub link and these prompts.

## Reproducing the post

```bash
cd promo/poster && npm install && npx playwright install chromium
npm run login                       # log in to Facebook by hand once; the session stays in ./profile
node post.js --text-file ../caption.txt --audience only-me \
  --media ../peach-tv-promo.mp4 ../../docs/screens/*.jpg ../../docs/screens/*.png --dry-run
```

Facebook doesn't allow automated posting on personal profiles, so keep it occasional. Selectors match the English
and Thai UI and may break when Facebook changes its layout.
