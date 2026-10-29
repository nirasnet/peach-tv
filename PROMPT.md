# ทำตาม: ล้างทีวี + โหมดเด็ก ด้วย AI (copy วางได้เลย)

> 🎬 **ดูคลิปจับมือทำ:** เพจ **จับมือ AI** บน [Facebook](https://www.facebook.com/profile.php?id=61596056038143) · [YouTube @jabmueai](https://www.youtube.com/@jabmueai) · [TikTok @jabmue.ai](https://www.tiktok.com/@jabmue.ai)

ภาษาไทย · prompt เป็นภาษาอังกฤษเพื่อให้ AI ทำงานแม่นที่สุด แต่สั่งให้ AI คุยกับเราเป็นภาษาไทย

> **🙏 Credit:** ส่วนล้างทีวี (prompt 1) คือ **[CleanYourTV](https://github.com/Gathin23/cleanyourtv)** โดย
> **Gathin** ([@Gathin23](https://github.com/Gathin23), [cleanyour.tv](https://cleanyour.tv), MIT License)
> prompt ด้านล่างแค่สั่งให้ AI ไปดึง [PROMPT.md ต้นฉบับ](https://github.com/Gathin23/cleanyourtv/blob/main/PROMPT.md)
> มาทำตาม จะได้ฉบับล่าสุดที่ผู้สร้างอัปเดตตลอด ส่วนโหมดเด็กและแอป iPhone (prompt 2) คือ repo นี้ ต่อยอดจาก CleanYourTV

ใช้กับทีวี Android TV / Google TV (TCL, Sony, Xiaomi, Hisense, Chromecast ฯลฯ) ไม่ได้กับ Samsung, LG และ Fire TV

## เตรียมของ 3 อย่าง

- ✅ ทีวี Android TV / Google TV
- ✅ คอม Mac หรือ Windows ต่อ Wi-Fi วงเดียวกับทีวี
- ✅ AI coding agent ที่รันคำสั่งบนเครื่องได้ เช่น [Claude Code](https://claude.com/claude-code),
  [GitHub Copilot CLI](https://github.com/features/copilot/cli), Codex, Gemini CLI

## 1️⃣ เปิดโหมดนักพัฒนา (ที่ทีวี ใช้รีโมท)

**การตั้งค่า › ระบบ › เกี่ยวกับ** › เลื่อนลงไปที่ **บิลด์ของระบบปฏิบัติการ Android TV** แล้วกด OK 7 ครั้ง
จนขึ้นว่าเป็นนักพัฒนาแล้ว

(เมนูอังกฤษ: Settings › System › About › Android TV OS build; ทีวีรุ่นเก่าอยู่ที่ Device Preferences › About › Build)

## 2️⃣ เปิด USB debugging

ย้อนกลับมาที่ **ระบบ** จะมีเมนูใหม่ **ตัวเลือกสำหรับนักพัฒนาแอป** › เปิด **การแก้ไขข้อบกพร่อง USB**
(ถ้ามี "Network/ADB debugging" เปิดด้วย)

## 3️⃣ เปิด Terminal พิมพ์ `claude` หรือ `copilot` แล้วแปะ prompt นี้

กดปุ่ม copy มุมขวาบนของกล่อง แล้วแก้แค่รุ่นทีวี (ไม่รู้รุ่นก็เว้นไว้ได้ AI อ่านเองจากทีวี)

```text
Talk to me in Thai. Clone https://github.com/Gathin23/cleanyourtv and work inside that folder.
Open its PROMPT.md and do everything between the two --- lines, exactly as if I had pasted it to you.
My TV model is: ____ (if I left this blank, read the model from the TV once you are connected).
```

## 4️⃣ กด "อนุญาต" ที่ทีวี

ทีวีจะเด้งถามว่าอนุญาตให้คอมเครื่องนี้ไหม ติ๊ก **อนุญาตจากคอมพิวเตอร์เครื่องนี้เสมอ** แล้วกด **อนุญาต**

☕ จากนั้น AI จะถามไม่กี่ข้อ (ใช้แอปไหนบ้าง, dock กี่ช่อง, เก็บ voice assistant / Chromecast ไหม) แล้วปิดโฆษณา
ปิดแอปขยะ และลงหน้าโฮมใหม่ให้ เช็กทุกขั้นด้วยภาพหน้าจอจากทีวี

🛟 ไม่มีการลบแอปทิ้ง อยากกลับเป็นแบบเดิมพิมพ์บอก AI ว่า `restore my TV`

## 🧸 แถม: โหมดเด็ก + กฎเวลาดูทีวี + แอป iPhone (prompt 2)

ทำต่อในแชทเดิมได้เลย หลังจาก prompt 1 เสร็จ

```text
Talk to me in Thai. My TV was cleaned with CleanYourTV and the cleanyourtv folder is on this computer.
Clone https://github.com/nirasnet/peach-tv next to that folder, read its README.md, and set up the family TV
on my real TV step by step, checking each step with a screenshot from the TV:
1. Install the TV agent with tv-agent/install.sh. If network ADB is already closed, tell me how to turn
   USB debugging back on, and close it again at the end. Keep the agent token private, don't print it in chat.
2. Ask me which apps my kids may open, then turn on Kids mode with only those apps.
3. Ask me what hours the TV may be used on school days and on weekends, and the daily screen-time limit,
   then set those rules.
4. Show me the unlock code and how to unlock the lock screen with the remote.
5. Ask me whether I have a Mac with Xcode and an iPhone. If yes, build and install the Peach TV app
   (ios/build-and-install.sh) and pair it with the TV. If not, give me a small script to lock and unlock
   the TV from this computer.
Ask me before anything that needs my Apple account. Skip "away from home" (Tailscale) unless I ask for it.
```

- **โหมดเด็ก:** เปิดได้แค่แอปที่อนุญาต แอปอื่นเด้งกลับหน้าโฮม
- **กฎครอบครัว:** ช่วงเวลาที่ดูได้ และเวลาดูต่อวัน ทีวีบังคับใช้เอง ไม่ต้องมีมือถือ
- **แอป iPhone:** ล็อก ปิดทีวี สลับโหมดเด็ก/ผู้ใหญ่ ดูประวัติการดู
- ทดสอบจริงกับ TCL Google TV (Android 12) และคอม Mac รายละเอียดทั้งหมดอยู่ใน [README](README.md)

## ติดปัญหา

- เล่าอาการให้ AI ฟังในแชทเดิม มันจะเปิด `docs/TROUBLESHOOTING.md` ของ CleanYourTV มาช่วยแก้
- ถาม/แจ้งปัญหาเรื่องล้างทีวีที่ [CleanYourTV issues](https://github.com/Gathin23/cleanyourtv/issues)
- เรื่องโหมดเด็กและแอป iPhone ที่ [issues ของ repo นี้](https://github.com/nirasnet/peach-tv/issues)

> ใช้ด้วยความระวัง: เป็นโปรเจกต์งานอดิเรก อ่าน [Security](README.md#limits-tested-on-the-tv) ก่อน
> และอย่าเปิด port ของทีวีออกอินเทอร์เน็ต

ขอบคุณ **Gathin** ผู้สร้าง CleanYourTV ที่เปิดให้ทุกคนใช้ฟรี 🙏 · prompt ทั้งหมดที่ใช้สร้างแอปนี้อยู่ใน
[docs/PROMPTS.md](docs/PROMPTS.md)
