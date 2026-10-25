# Prompts

This project was built by giving prompts to AI coding agents. This page lists those prompts, quoted as typed
(typos and all), with a short note on what the agent did after each one.

- [Part 1: building the app](#part-1-building-the-app) (GitHub Copilot CLI)
- [Part 2: the Facebook post](#part-2-the-facebook-post) (Claude Code)

What was left out: "done" replies, the agent's automatic "keep working" nudges, a couple of messages typed by
accident, and anything private (an email address, IPs, keys). Those spots are marked `<…>`.

# Part 1: building the app

Built in one session of [GitHub Copilot CLI](https://github.com/features/copilot/cli) on a Mac, using
Claude Opus 5.5, on 23–25 October 2026. The agent worked on the real TV over ADB and Tailscale, ran the iPhone
app in the Simulator and on a real iPhone, and checked each step with screenshots from the TV.

## 1. Clean up the TV (CleanYourTV)

> add new project name cleantv

> ok on project clean tv i got this prompt plese do it for me  want to debloat my Android TV and replace its
> launcher with a clean Apple TV style home screen. … *(the rest of the
> [CleanYourTV prompt](https://github.com/Gathin23/cleanyourtv/blob/main/PROMPT.md), pasted as is)* … and i
> want to customize to personalize our family is Look Peach Family, add gimmic or something to awasome

- **Starting point:** cloned [Gathin23/cleanyourtv](https://github.com/Gathin23/cleanyourtv), found the TV
  (a TCL Google TV, Android 12) and backed up its settings.
- **Debloat:** turned off the ads, telemetry and preinstalled apps in three batches, with a screenshot after
  each batch.
- **New Home screen:** installed the Apple TV style launcher with a peach "Look Peach Family" theme.

> why it show ads as screen server to my TV i don't need it ,, it look like it nothing change

The screensaver was Google's ad-carrying Ambient mode, so the agent swapped it for the launcher's clock. The
old Home screen kept coming back because the Wi-Fi had been saved by the setup app. After the TV re-joined
Wi-Fi, the new Home screen stuck.

## 2. Control the TV from outside the home

> can i remote from my phone to lock this tv or close tv via internet if only lan can tv install vpn like tailscale

> install tailscale for me ,  and already have pin lock

Installed Tailscale on the TV and set it as an always-on VPN, so the TV can be reached from anywhere on the
family's private network.

## 3. The iPhone app

> make tv remote app for my ip17pro which auto check is tv is online and close or lock it or snap screen

Two parts came out of this one prompt:

- **[`tv-agent/`](../tv-agent):** a small Android accessibility service on the TV, with a token-protected HTTP API.
- **[`ios/`](../ios):** a SwiftUI app that checks the TV every few seconds and can lock it, turn it off, send a
  message and grab a screenshot.

The first lock could be bypassed with the remote, so the agent rebuilt the lock screen to catch every key.

## 4. Activity history

> in iphone app can we see tv log activity each day,  open, close, which app start from : to ,

The TV logs screen on/off and which app is open. The app shows a daily timeline, total screen time and
per-app bars.

## 5. Family rules: TV hours and screen time

> can set config schedule allow time each day like 7:00 am to 20:30 pm ,   and screen time each day 45 min,
> 1 hour ,2 hour,  like this can qulick enable , disable it,  is anything is recomend please tell me

- **Where the rules run:** on the TV itself, so they still work when the phone is offline.
- **Recommendations the agent added:** separate weekday and weekend times, warnings 5 and 1 minutes before time
  runs out, bonus time from the phone, and a parent override until midnight.

> if tv lock more than 10  minute. turn off it,  in tv log each app when app open every 10 minute snap shot
> screen and link with history can view on app, and it can auto delete in 7 day,

- **Turn off when idle:** the TV turns off after it has been locked for 10 minutes.
- **Snapshots:** small screenshots taken when an app opens and every 10 minutes after, shown in the history and
  deleted after 7 days.

## 6. Lock screen wording and themes

> อยากให้สามารถ ปรับ wording ตอน lock กับ tv time ได้ ใส่เป็น templete มาให้เลือก กับแก้ไขเองแล้วบันทึกไว้ได้
> และปรับ theme, ฉากหลัก ได้ ขอหลายๆแบบ

> lock screen each mode must be can select background ./ theme by individual

- **Themes:** 11 lock-screen themes (peach, night, sakura, dino and others) and wording templates you can edit
  and save.
- **Per-lock look:** each kind of lock (parent, bedtime, time limit) gets its own look, with a live preview on
  the TV.

## 7. Share with the family (TestFlight)

> how can i share this app to my wife

> her email is `<…>`

Set the app up for App Store Connect, uploaded a build and invited her as a TestFlight tester. The scripts are
in [`ios/scripts/`](../ios/scripts).

## 8. Kid mode

> main manu on tv cannot switch to kid account

Google TV's own profile switcher lives in the stock launcher, which was disabled. The agent tried a few
workarounds and none was clean, so it stopped there. That led to the next prompt.

> ok default mode is kid mode show only, AIS plas app , other app hide,    in iphone app add feature change mode
> if enable kids mode show only AIS plan,

- **On the TV:** Kid mode is the default. The Home screen shows only the allowed apps (AIS PLAY), and any
  other app is sent back Home.
- **In the iPhone app:** a Kids/Parent switch and an editor for the allowed apps. The TV goes back to Kid mode
  when the screen turns off.

> when we adjust time is it reflection to tv ex. before sat ,sun quota 2 hour when we change to 1 hour is it
> effective to TV,

It takes effect right away. The agent added a warning before saving a limit that would lock the TV
immediately.

## 9. Built-in VPN for the non-technical user

> ok add to , todo list
> next i want to consult when we outside home without same wifi it need to use tailscale ,  but non technical
> from my wife it hard to config it it many step,  can we do something one stop service build it of this project

The agent offered three options:

- **A:** share the TV with her own Tailscale account.
- **B:** build Tailscale into the app.
- **C:** a cloud relay.

The answers were **B**, with the key sent as an **invite link** rather than built into the app, and used on
both phones.

- **Built in:** [libtailscale](https://github.com/tailscale/libtailscale) is part of the iPhone app, so there's
  no separate VPN app.
- **Joining:** a parent taps "Invite family" and sends a link over LINE. The other person taps it once and
  is done.
- **Access rules:** the phones are tagged so they can reach only the TV's port 8765.

> please check icon peach tv family on appstore connect is not show icon

> how to do it What you need to do (one time, in the Tailscale admin console; steps are in  README.md  under
> "Away from home") step by step

> can you do it for me now login in edge it show *(pasted the default access policy)* on step 1

> complete step5

The agent wrote the exact policy edits, then checked that the TV and phones had the right tags and could reach
each other.

## 10. Lock until TV time

> ok it done ,  i have question if now i lock by app tomorrow after 07:00 is it unlock auto

> because sometime we unlock for their kid then finish we will lock  and i wonder tommorow on schedule if it
> allow time it must unlock auto?

A lock set from the phone now lifts by itself when the next allowed TV time starts. The app shows "Locked till
tomorrow 7:00".

> update my phone again

## 11. Waking the TV

> why google tv can use remote to open tv from standby mode but our app cannot wake screen on

> ok try it can you use REA to analyse this packen from google tv remote to check this how it work

> is it finish is you need to test on tv

The agent found that a power key press does wake the TV, but its own time-limit rule was putting the TV straight
back to sleep. A fix for that rule was still in progress and isn't in this repo yet. From deep standby, nothing on the network wakes this TV, not even Wake-on-LAN.

# Part 2: the Facebook post

The announcement post (caption, screenshots, the 16-second video and the posting itself) was made by
[Claude Code](https://claude.com/claude-code) from the prompts below, typed by a person who also logged in to
Facebook and checked the result. They're quoted as typed.

### 1. Build the poster

> can you automate post facebook for me by build in agent browser with i login facebook for you

The agent asked three questions (where to post, how to run it, what kind of content). The answers were:
personal profile, a Playwright script, and text with images and video. It then wrote
[`promo/poster/`](../promo/poster). That's a Playwright script that keeps a logged-in Chromium profile on disk,
so the human logs in once by hand and the script never sees the password.

### 2. Make the post

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

### 3. Rewrite it and open-source the project

> ok ปรับ wording ให้ดูเหมือน ไม่ใช่ ai โพส โพสแนวๆ เหมือน พี่หนูเนยก็ได้ https://www.facebook.com/nuuneoi/?locale=th_TH ตอนจบ ล่างสุด ค่อยบอกว่า โพสโดย ai นะ , และอยากให้ปรับ github ของ project นี้ แชร์ได้ public ได้ แต่ระวังข้อมูล ความลับอะไรเอาออกให้หมดด้วยนะ ข้อมูล technical อะไร ก็ไปอธิบายใน githnub แล้วกัน รวมถึง prompt ที่สร้าง ให้ บอกในโพส ว่า prompt ที่สร้าง ใน comment ด้วยละกัน

What the agent did:

- **Caption:** rewrote it in a casual, first-person tone, with a note at the end saying AI wrote it. The result
  is in [`promo/caption.txt`](../promo/caption.txt).
- **Secrets:** checked the private repo for anything that shouldn't be public: the TV token, the unlock code,
  App Store Connect key IDs, the Apple Team ID, contact details, and home and tailnet IP addresses. It published
  this repo as a fresh history with all of those removed or turned into environment variables.
- **Comment:** added a comment to the post with the GitHub link and these prompts.

### 4. Add a narrator

> video ขอเสียง บรรยาย ให้เหมือนเสียงคนจริงๆ ได้ใหม

> can ve user https://elevenlabs.io/voices/7XW5JhaNn90bnFojQ5DA voice from elevenlabs , add quiet background

> you can automate by chrome like fb post

> ขอเสียงผู้ชายดีกว่า xYmBpJREC3WfqEFpbPvO https://elevenlabs.io/voices/xYmBpJREC3WfqEFpbPvO

What the agent did:

- **Why the website:** the ElevenLabs free plan blocks library voices over the API, so the agent drove the
  ElevenLabs website instead, in the same logged-in browser it uses for Facebook. The script is
  [`promo/poster/elevenlabs-tts.js`](../promo/poster/elevenlabs-tts.js).
- **Voice:** generated the narration ([`promo/video/narration.txt`](../promo/video/narration.txt)) with the
  "Songkran - Calm & Humble" voice on Eleven v4.
- **Timing:** found the pauses between lines and re-timed each scene to start with its line.
- **Music:** made a quiet ukulele and piano bed with ElevenLabs sound generation and mixed it about 17 dB under
  the voice.

### 5. Publish

> post it with public

Voice and music: [ElevenLabs](https://elevenlabs.io).

### Reproducing the post

```bash
cd promo/poster && npm install && npx playwright install chromium
npm run login                       # log in to Facebook by hand once; the session stays in ./profile
node post.js --text-file ../caption.txt --audience only-me \
  --media ../peach-tv-promo.mp4 ../../docs/screens/*.jpg ../../docs/screens/*.png --dry-run
```

Facebook doesn't allow automated posting on personal profiles, so keep it occasional. Selectors match the English
and Thai UI and may break when Facebook changes its layout.
