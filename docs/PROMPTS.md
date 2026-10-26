# Prompts

ภาษาไทย · [English](PROMPTS.en.md)

โปรเจกต์นี้ทำด้วยการสั่ง AI coding agent ทั้งหมด หน้านี้รวม prompt ที่พิมพ์จริง (ไม่ได้แก้คำผิด) และสรุปสั้นๆ ว่า
agent ทำอะไรต่อจากแต่ละ prompt

> อยากทำตามแบบไม่ต้องอ่านทั้งหมด: [PROMPT.md](../PROMPT.md) มี prompt สั้นๆ แบบ copy วางได้เลย

- [ส่วนที่ 1: สร้างแอพ](#ส่วนที่-1-สร้างแอพ)
- [ส่วนที่ 2: โพส Facebook](#ส่วนที่-2-โพส-facebook)

**ใช้ AI coding agent ตัวไหนก็ได้** ไม่จำเป็นต้องใช้ GitHub Copilot หรือเจ้าไหนเป็นพิเศษ ขอแค่เป็น agent ที่รันคำสั่ง
shell บนเครื่องเราได้ เช่น Claude Code, GitHub Copilot CLI, Codex, Gemini CLI, Cursor ฯลฯ เอา prompt ด้านล่างไปใช้ได้เลย
(ตอนทำจริง ส่วนที่ 1 ใช้ GitHub Copilot CLI กับ Claude Opus 5.5 ส่วนที่ 2 ใช้ Claude Code)

สิ่งที่ตัดออก: คำตอบสั้นๆ อย่าง "done", ข้อความ "keep working" ที่ตัว agent ส่งเองอัตโนมัติ, ข้อความที่พิมพ์พลาด
และข้อมูลส่วนตัว (อีเมล, IP, key) ตรงที่ตัดจะเขียนว่า `<…>`

# ส่วนที่ 1: สร้างแอพ

ทำในแชทยาวแชทเดียวกับ AI coding agent บน Mac วันที่ 23–25 ต.ค. 2026 agent ทำงานกับทีวีจริงผ่าน ADB และ Tailscale
รันแอพ iPhone ทั้งใน Simulator และบน iPhone จริง และเช็กทุกขั้นด้วย screenshot จากทีวี

## 1. ล้างทีวีให้สะอาด (CleanYourTV)

> add new project name cleantv

> ok on project clean tv i got this prompt plese do it for me  want to debloat my Android TV and replace its
> launcher with a clean Apple TV style home screen. … *(ที่เหลือคือ
> [CleanYourTV prompt](https://github.com/Gathin23/cleanyourtv/blob/main/PROMPT.md) แปะทั้งก้อน)* … and i
> want to customize to personalize our family is Look Peach Family, add gimmic or something to awasome

- **เริ่มต้น:** clone [Gathin23/cleanyourtv](https://github.com/Gathin23/cleanyourtv) มา หาทีวีในวง LAN
  (TCL Google TV, Android 12) แล้ว backup ค่าเดิมไว้ก่อน
- **Debloat:** ปิดโฆษณา, telemetry และแอพที่ติดมากับเครื่อง ทำเป็น 3 รอบ และถ่าย screenshot เช็กทุกรอบ
- **หน้า Home ใหม่:** ลง launcher สไตล์ Apple TV พร้อมธีมสีพีช "Look Peach Family"

> why it show ads as screen server to my TV i don't need it ,, it look like it nothing change

ภาพพักหน้าจอเป็น Ambient mode ของ Google ซึ่งมีโฆษณา agent เลยเปลี่ยนเป็นนาฬิกาของ launcher แทน ส่วนหน้า Home
เก่าที่เด้งกลับมาตลอด เป็นเพราะ Wi-Fi ถูกบันทึกไว้โดยแอพตั้งค่าเครื่อง พอให้ทีวีต่อ Wi-Fi ใหม่ หน้า Home ใหม่ก็อยู่ถาวร

## 2. คุมทีวีจากนอกบ้าน

> can i remote from my phone to lock this tv or close tv via internet if only lan can tv install vpn like tailscale

> install tailscale for me ,  and already have pin lock

ลง Tailscale บนทีวีและตั้งเป็น always-on VPN ทีวีเลยต่อเข้าเครือข่ายส่วนตัวของบ้านได้จากทุกที่

## 3. แอพ iPhone

> make tv remote app for my ip17pro which auto check is tv is online and close or lock it or snap screen

prompt เดียวได้มา 2 ส่วน:

- **[`tv-agent/`](../tv-agent):** Android accessibility service ตัวเล็กๆ บนทีวี มี HTTP API ที่ต้องใช้ token
- **[`ios/`](../ios):** แอพ SwiftUI ที่เช็กสถานะทีวีทุกไม่กี่วินาที สั่งล็อก ปิดทีวี ส่งข้อความ และดูภาพหน้าจอได้

หน้าล็อกเวอร์ชันแรกกดรีโมตหลุดออกมาได้ agent เลยทำหน้าล็อกใหม่ให้ดักทุกปุ่ม

## 4. ประวัติการดูทีวี

> in iphone app can we see tv log activity each day,  open, close, which app start from : to ,

ทีวีเก็บ log เปิด/ปิดจอ และแอพที่เปิดอยู่ ในแอพจะเห็น timeline รายวัน เวลาดูรวม และกราฟแท่งแยกตามแอพ

## 5. กฎครอบครัว: เวลาดูทีวีและ screen time

> can set config schedule allow time each day like 7:00 am to 20:30 pm ,   and screen time each day 45 min,
> 1 hour ,2 hour,  like this can qulick enable , disable it,  is anything is recomend please tell me

- **กฎทำงานที่ไหน:** บนทีวีเอง มือถือไม่ออนไลน์ก็ยังบังคับใช้ได้
- **ที่ agent แนะนำเพิ่ม:** แยกเวลาวันธรรมดากับเสาร์-อาทิตย์, เตือนก่อนหมดเวลา 5 นาทีและ 1 นาที, เพิ่มเวลาพิเศษจากมือถือ
  และให้ผู้ปกครองพักกฎได้ถึงเที่ยงคืน

> if tv lock more than 10  minute. turn off it,  in tv log each app when app open every 10 minute snap shot
> screen and link with history can view on app, and it can auto delete in 7 day,

- **ปิดเองเมื่อล็อกนาน:** ล็อกค้างเกิน 10 นาที ทีวีปิดเอง
- **Snapshot:** ถ่ายภาพหน้าจอเล็กๆ ตอนเปิดแอพและทุก 10 นาที ดูได้ในประวัติ และลบเองหลัง 7 วัน

## 6. ข้อความและธีมหน้าล็อก

> อยากให้สามารถ ปรับ wording ตอน lock กับ tv time ได้ ใส่เป็น templete มาให้เลือก กับแก้ไขเองแล้วบันทึกไว้ได้
> และปรับ theme, ฉากหลัก ได้ ขอหลายๆแบบ

> lock screen each mode must be can select background ./ theme by individual

- **ธีม:** หน้าล็อก 11 ธีม (peach, night, sakura, dino ฯลฯ) และ template ข้อความที่แก้และบันทึกเองได้
- **แยกตามประเภทการล็อก:** ล็อกโดยพ่อแม่, ล็อกตอนนอน, ล็อกตอนหมดเวลา ตั้งหน้าตาแยกกันได้ และ preview บนทีวีได้ทันที

## 7. แชร์ให้คนในบ้านใช้ (TestFlight)

> how can i share this app to my wife

> her email is `<…>`

ตั้งค่าแอพบน App Store Connect อัปโหลด build แล้วเชิญเป็น tester ใน TestFlight script อยู่ใน
[`ios/scripts/`](../ios/scripts)

## 8. Kid mode

> main manu on tv cannot switch to kid account

ตัวสลับโปรไฟล์ของ Google TV อยู่ใน launcher เดิมที่ถูกปิดไปแล้ว agent ลองหลายวิธีแต่ไม่มีวิธีไหนเนียน เลยหยุดไว้
แล้วมาเป็น prompt ถัดไปแทน

> ok default mode is kid mode show only, AIS plas app , other app hide,    in iphone app add feature change mode
> if enable kids mode show only AIS plan,

- **บนทีวี:** ค่าเริ่มต้นเป็น Kid mode หน้า Home โชว์แค่แอพที่อนุญาต (AIS PLAY) เปิดแอพอื่นจะเด้งกลับ Home
- **ในแอพ iPhone:** ปุ่มสลับ Kids/Parent และหน้าเลือกแอพที่อนุญาต พอปิดจอ ทีวีจะกลับเป็น Kid mode เอง

> when we adjust time is it reflection to tv ex. before sat ,sun quota 2 hour when we change to 1 hour is it
> effective to TV,

มีผลทันที agent เพิ่มคำเตือนก่อนบันทึก ถ้าเวลาที่ตั้งใหม่จะทำให้ทีวีล็อกทันที

## 9. VPN ในตัวแอพ สำหรับคนที่ไม่ถนัดเทคนิค

> ok add to , todo list
> next i want to consult when we outside home without same wifi it need to use tailscale ,  but non technical
> from my wife it hard to config it it many step,  can we do something one stop service build it of this project

agent เสนอ 3 ทาง:

- **A:** แชร์ทีวีให้บัญชี Tailscale ของภรรยา
- **B:** ฝัง Tailscale ไว้ในแอพเลย
- **C:** ใช้ cloud relay

เลือก **B** ส่ง key ผ่าน **ลิงก์เชิญ** แทนการฝัง key ไว้ในแอพ และใช้กับมือถือทั้งสองเครื่อง

- **ฝังในแอพ:** ใช้ [libtailscale](https://github.com/tailscale/libtailscale) ในแอพ iPhone ไม่ต้องลงแอพ VPN แยก
- **การเข้าร่วม:** พ่อหรือแม่กด "Invite family" แล้วส่งลิงก์ทาง LINE อีกคนกดลิงก์ครั้งเดียวก็ใช้ได้เลย
- **สิทธิ์การเข้าถึง:** มือถือถูกติด tag ให้เข้าได้แค่ port 8765 ของทีวีเท่านั้น

> please check icon peach tv family on appstore connect is not show icon

> how to do it What you need to do (one time, in the Tailscale admin console; steps are in  README.md  under
> "Away from home") step by step

> can you do it for me now login in edge it show *(แปะ access policy ค่าเริ่มต้นมา)* on step 1

> complete step5

agent เขียน policy ที่ต้องแก้ให้ตรงๆ แล้วเช็กว่าทีวีกับมือถือได้ tag ถูกต้องและคุยกันได้จริง

## 10. ล็อกไว้จนถึงเวลาดูทีวี

> ok it done ,  i have question if now i lock by app tomorrow after 07:00 is it unlock auto

> because sometime we unlock for their kid then finish we will lock  and i wonder tommorow on schedule if it
> allow time it must unlock auto?

ล็อกที่สั่งจากมือถือจะปลดเองเมื่อถึงช่วงเวลาดูทีวีรอบถัดไป ในแอพจะขึ้นว่า "Locked till tomorrow 7:00"

> update my phone again

## 11. ปลุกทีวีจาก standby

> why google tv can use remote to open tv from standby mode but our app cannot wake screen on

> ok try it can you use REA to analyse this packen from google tv remote to check this how it work

> is it finish is you need to test on tv

agent พบว่ากดปุ่ม power ปลุกทีวีได้จริง แต่กฎจำกัดเวลาของแอพเราเองสั่งทีวีกลับไปหลับทันที ตัวแก้กฎนี้ยังทำไม่เสร็จ
และยังไม่ได้อยู่ใน repo นี้ ส่วนตอนทีวีอยู่ใน deep standby ไม่มีอะไรทางเครือข่ายปลุกได้เลย แม้แต่ Wake-on-LAN

# ส่วนที่ 2: โพส Facebook

โพสประกาศโปรเจกต์ (แคปชัน, screenshot, วิดีโอพร้อมเสียงบรรยาย และการโพส) ทำโดย AI coding agent จาก prompt ด้านล่าง
คนทำแค่ login Facebook เองและเช็กผลลัพธ์

### 1. สร้างตัวโพส

> can you automate post facebook for me by build in agent browser with i login facebook for you

agent ถามกลับ 3 ข้อ (โพสที่ไหน, รันแบบไหน, เนื้อหาแบบไหน) คำตอบคือ โปรไฟล์ส่วนตัว, Playwright script และข้อความพร้อมรูป
และวิดีโอ ได้ออกมาเป็น [`promo/poster/`](../promo/poster) เป็น Playwright script ที่เก็บ Chromium profile ที่ login
แล้วไว้ในเครื่อง คน login เองครั้งเดียว script ไม่เคยเห็นรหัสผ่าน

### 2. ทำโพส

> ok now i want to pose about viral cleanyour.tv จะเล่าแนวๆ ว่าตามกระแสนิดนึง ปรับ TV ให้รองรับ kid mode และควบคุม ตั้งค่า ผ่านทาง iphone ได้ build in vpn ควบคุมจาก นอกบ้านได้ cap screen ตัวอย่า จอทีวี parrent mode, kid mode, lock screen mode , iphone app main , และทำ vdo โดยใช้ hyperframe นำเสนอสั้นๆ และลองโพสแบบ only me ดูก่อน

- **Screenshot ทีวี:** ใช้ API ของ agent เอง (`GET /screenshot`) ถ่าย Parent mode, Kid mode (`POST /kids`) และหน้าล็อก
  (`POST /lock`) แล้วคืนค่าทีวีกลับเหมือนเดิม
- **Screenshot iPhone:** ถ่ายจาก iOS Simulator
- **วิดีโอ:** ทำ [`promo/video/index.html`](../promo/video/index.html) เป็น composition ขนาด 1080×1080 ของ
  [HyperFrames](https://hyperframes.heygen.com) (HTML + GSAP) แล้ว render ด้วย `npx hyperframes render`
- **โพส:** เพิ่ม `--audience only-me` ให้ตัวโพส ถ้ายืนยันไม่ได้ว่าตั้ง audience ถูก จะไม่ยอมโพส แล้วโพสแบบเห็นคนเดียวก่อน

### 3. ปรับคำและเปิด source

> ok ปรับ wording ให้ดูเหมือน ไม่ใช่ ai โพส โพสแนวๆ เหมือน พี่หนูเนยก็ได้ https://www.facebook.com/nuuneoi/?locale=th_TH ตอนจบ ล่างสุด ค่อยบอกว่า โพสโดย ai นะ , และอยากให้ปรับ github ของ project นี้ แชร์ได้ public ได้ แต่ระวังข้อมูล ความลับอะไรเอาออกให้หมดด้วยนะ ข้อมูล technical อะไร ก็ไปอธิบายใน githnub แล้วกัน รวมถึง prompt ที่สร้าง ให้ บอกในโพส ว่า prompt ที่สร้าง ใน comment ด้วยละกัน

- **แคปชัน:** เขียนใหม่ให้เป็นภาษาพูด เล่าแบบคนเล่าเอง แล้วบอกตอนท้ายว่า AI เขียน ดูได้ที่
  [`promo/caption.txt`](../promo/caption.txt)
- **ความลับ:** ไล่ repo ส่วนตัวหาสิ่งที่ไม่ควรเปิด: token ทีวี, รหัสปลดล็อก, key ID ของ App Store Connect, Apple Team ID,
  ข้อมูลติดต่อ, IP ในบ้านและใน tailnet แล้วเปิด repo นี้เป็น history ใหม่ ที่เอาของพวกนั้นออกหรือเปลี่ยนเป็น environment
  variable แล้ว
- **คอมเมนต์:** คอมเมนต์ใต้โพส ใส่ลิงก์ GitHub และ prompt

### 4. ใส่เสียงบรรยาย

> video ขอเสียง บรรยาย ให้เหมือนเสียงคนจริงๆ ได้ใหม

> can ve user https://elevenlabs.io/voices/7XW5JhaNn90bnFojQ5DA voice from elevenlabs , add quiet background

> you can automate by chrome like fb post

> ขอเสียงผู้ชายดีกว่า xYmBpJREC3WfqEFpbPvO https://elevenlabs.io/voices/xYmBpJREC3WfqEFpbPvO

- **ทำไมใช้หน้าเว็บ:** ElevenLabs แพ็กเกจฟรีไม่ให้ใช้เสียงจาก library ผ่าน API agent เลยคุมหน้าเว็บ ElevenLabs แทน
  ด้วย browser ที่ login ไว้ตัวเดียวกับที่ใช้โพส Facebook script อยู่ที่
  [`promo/poster/elevenlabs-tts.js`](../promo/poster/elevenlabs-tts.js)
- **เสียง:** สร้างเสียงบรรยาย ([`promo/video/narration.txt`](../promo/video/narration.txt)) ด้วยเสียง
  "Songkran - Calm & Humble" บน Eleven v4
- **จังหวะ:** หาช่วงเงียบระหว่างประโยค แล้วจัดเวลาให้แต่ละฉากเริ่มพร้อมประโยคของมัน
- **เพลง:** ใช้ ElevenLabs sound generation ทำเพลงอูคูเลเล่กับเปียโนเบาๆ แล้วมิกซ์ให้เบากว่าเสียงพูดประมาณ 17 dB

### 5. โพสจริง

> post it with public

เสียงบรรยายและเพลง: [ElevenLabs](https://elevenlabs.io)

### ลองทำตาม

```bash
cd promo/poster && npm install && npx playwright install chromium
npm run login                       # login Facebook เองครั้งเดียว session จะเก็บไว้ใน ./profile
node post.js --text-file ../caption.txt --audience only-me \
  --media ../peach-tv-promo.mp4 ../../docs/screens/*.jpg ../../docs/screens/*.png --dry-run
```

มี script อื่นด้วย: `audience.js` (เปลี่ยนว่าใครเห็นโพส), `comment.js` (คอมเมนต์ใต้โพส/Reel ของตัวเอง) และ `reel.js`
(โพส Reel ติดป้าย AI และแชร์เข้ากลุ่ม) ทุกตัวมี `--dry-run`

Facebook ไม่อนุญาตให้โพสอัตโนมัติบนโปรไฟล์ส่วนตัว ใช้นานๆ ครั้งพอ selector รองรับ UI ภาษาอังกฤษและไทย และอาจพังได้เมื่อ
Facebook เปลี่ยนหน้าตา
