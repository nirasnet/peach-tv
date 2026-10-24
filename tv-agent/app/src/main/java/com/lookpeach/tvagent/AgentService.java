package com.lookpeach.tvagent;

import android.accessibilityservice.AccessibilityService;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.hardware.HardwareBuffer;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.SystemClock;
import android.util.Log;
import android.util.TypedValue;
import android.view.Display;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public class AgentService extends AccessibilityService {
    private static final String TAG = "PeachAgent";
    static final String VERSION = "1.6";
    private static final int PEACH = 0xFFFFB38A;
    private static final int CREAM = 0xFFFFF1E6;

    private final Handler main = new Handler(Looper.getMainLooper());
    private AgentServer server;
    private WindowManager windows;
    private View lockView;
    private View messageView;
    private TextView lockMessageText;
    private TextView lockSubText;
    private Rules rules;
    /** Set while a rule (not a parent) holds the lock: Rules.SCHEDULE or Rules.LIMIT. */
    private volatile String autoReason;
    private long autoSince;
    private long lastTick;
    private int warned;
    /** The screensaver is up: the screen is on but nobody is watching, so it is not screen time. */
    private volatile boolean dreaming;
    private static final long TICK_MS = 20_000;
    private AudioFocusRequest focusRequest;
    private volatile String foregroundPackage = "";
    private final StringBuilder typed = new StringBuilder();
    private ActivityLog activity;
    private SnapLog snaps;
    private Look look;
    /** A draft look shown on the TV for a few seconds from the phone; kind is parent, schedule or limit. */
    private Look previewLook;
    private String previewKind;
    private String shownKey;
    private android.animation.ObjectAnimator floatAnim;
    private final Runnable endPreview = () -> { previewLook = null; updateLock(); };
    /** The app the next history snapshot is for, and when the last one was taken. */
    private String snapPkg = "";
    private long lastSnapAt;
    /** When the lock appeared on a lit screen; after Rules.lockOffMin the TV is turned off. */
    private long lockedSince;
    private final Runnable snapSoon = () -> maybeSnap(System.currentTimeMillis());
    private final Map<String, Boolean> launchable = new HashMap<>();
    private final BroadcastReceiver screenReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            if (Intent.ACTION_DREAMING_STARTED.equals(action) || Intent.ACTION_DREAMING_STOPPED.equals(action)) {
                main.post(tick);
                dreaming = Intent.ACTION_DREAMING_STARTED.equals(action);
                return;
            }
            boolean on = Intent.ACTION_SCREEN_ON.equals(action);
            if (!on) dreaming = false;
            // Parent mode lasts until the TV goes off (unless the phone turned "auto" off).
            if (!on && !Kids.on(AgentService.this) && Kids.auto(AgentService.this)) Kids.set(AgentService.this, true, null, null);
            activity.screen(on, System.currentTimeMillis());
            main.removeCallbacks(tick);
            lastTick = 0;
            if (on) main.post(tick);
        }
    };
    /** Every 20 s while the screen is on: heartbeat for the history, screen time and the rules. */
    private final Runnable tick = new Runnable() {
        @Override
        public void run() {
            main.removeCallbacks(this);
            long now = System.currentTimeMillis();
            activity.heartbeat(now);
            enforce(now);
            maybeSnap(now);
            if (!((PowerManager) getSystemService(POWER_SERVICE)).isInteractive()) return;
            long left = rules == null ? -1 : rules.remainingSec(now);
            // Wake up right when time runs out instead of up to 20 s later.
            long delay = left > 0 && left * 1000 < TICK_MS ? Math.max(1000, left * 1000 + 500) : TICK_MS;
            main.postDelayed(this, delay);
        }
    };

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        Prefs.ensure(this);
        windows = (WindowManager) getSystemService(WINDOW_SERVICE);
        if (activity == null) {
            activity = new ActivityLog(this);
            boolean on = ((PowerManager) getSystemService(POWER_SERVICE)).isInteractive();
            activity.start(on, System.currentTimeMillis());
            IntentFilter screen = new IntentFilter(Intent.ACTION_SCREEN_ON);
            screen.addAction(Intent.ACTION_SCREEN_OFF);
            screen.addAction(Intent.ACTION_DREAMING_STARTED);
            screen.addAction(Intent.ACTION_DREAMING_STOPPED);
            if (Build.VERSION.SDK_INT >= 33) registerReceiver(screenReceiver, screen, RECEIVER_NOT_EXPORTED);
            else registerReceiver(screenReceiver, screen);
        }
        if (rules == null) rules = new Rules(Prefs.get(this));
        if (look == null) look = Look.load(Prefs.get(this));
        if (snaps == null) {
            snaps = new SnapLog(this);
            snaps.prune(System.currentTimeMillis());
        }
        updateLock();
        main.post(tick);
        if (server == null) {
            server = new AgentServer(this::handle, () -> Prefs.get(this).getString(Prefs.TOKEN, ""));
            server.start();
        }
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED || event.getPackageName() == null) return;
        String pkg = event.getPackageName().toString();
        if (pkg.equals(getPackageName()) || pkg.equals("com.android.systemui") || pkg.equals("android")) return;
        foregroundPackage = pkg;
        if (kidsBlock(pkg)) return;
        if (activity != null && isApp(pkg)) {
            activity.app(pkg, System.currentTimeMillis());
            if (!pkg.equals(snapPkg)) {
                snapPkg = pkg;
                lastSnapAt = 0;
                main.removeCallbacks(snapSoon);
                main.postDelayed(snapSoon, 5000);
            }
        }
    }

    // ---- Kids mode ----

    private long kidsToldAt;

    /** Kids mode: any other app (Settings and Live TV too) goes straight back to the Peach home. */
    private boolean kidsBlock(String pkg) {
        if (pkg == null || !Kids.on(this) || pkg.equals("com.gathin.tvhome") || !isApp(pkg)
                || Kids.apps(this).contains(pkg)) return false;
        Log.i(TAG, "kids mode: " + pkg + " sent home");
        performGlobalAction(GLOBAL_ACTION_HOME);
        long now = SystemClock.elapsedRealtime();
        if (now - kidsToldAt > 5000) {
            kidsToldAt = now;
            StringBuilder names = new StringBuilder();
            for (String a : Kids.apps(this)) {
                if (names.length() > 0) names.append(", ");
                names.append(label(a));
            }
            showMessage(names.length() == 0 ? "โหมดเด็ก 🧸" : "โหมดเด็ก 🧸 ดูได้เฉพาะ " + names);
        }
        return true;
    }

    private String kidsJson() {
        PackageManager pm = getPackageManager();
        Map<String, String> found = new java.util.TreeMap<>();
        for (String category : new String[]{Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER}) {
            for (android.content.pm.ResolveInfo ri : pm.queryIntentActivities(
                    new Intent(Intent.ACTION_MAIN).addCategory(category), 0)) {
                String pkg = ri.activityInfo.packageName;
                if (pkg.equals(getPackageName()) || pkg.equals("com.gathin.tvhome") || found.containsKey(pkg)) continue;
                found.put(pkg, String.valueOf(ri.loadLabel(pm)));
            }
        }
        java.util.List<Map.Entry<String, String>> list = new java.util.ArrayList<>(found.entrySet());
        list.sort((a, b) -> a.getValue().compareToIgnoreCase(b.getValue()));
        StringBuilder available = new StringBuilder();
        for (Map.Entry<String, String> e : list) {
            if (available.length() > 0) available.append(',');
            available.append("{\"pkg\":").append(Json.quote(e.getKey()))
                    .append(",\"label\":").append(Json.quote(e.getValue())).append('}');
        }
        StringBuilder apps = new StringBuilder();
        for (String a : Kids.apps(this)) {
            if (apps.length() > 0) apps.append(',');
            apps.append(Json.quote(a));
        }
        return "{\"ok\":true,\"enabled\":" + Kids.on(this) + ",\"auto\":" + Kids.auto(this)
                + ",\"apps\":[" + apps + "],\"available\":[" + available + "]}";
    }

    /** Only apps with a launcher entry (and the Peach home) go in the history, not dialogs or keyboards. */
    private boolean isApp(String pkg) {
        Boolean known = launchable.get(pkg);
        if (known == null) {
            PackageManager pm = getPackageManager();
            known = pkg.equals("com.gathin.tvhome") || pm.getLeanbackLaunchIntentForPackage(pkg) != null
                    || pm.getLaunchIntentForPackage(pkg) != null;
            launchable.put(pkg, known);
        }
        return known;
    }

    @Override
    public void onInterrupt() { }

    @Override
    public void onDestroy() {
        if (server != null) server.stop();
        server = null;
        if (activity != null) {
            try { unregisterReceiver(screenReceiver); } catch (IllegalArgumentException ignored) { }
            main.removeCallbacks(tick);
            main.removeCallbacks(snapSoon);
            activity.heartbeat(System.currentTimeMillis());
        }
        main.post(() -> {
            removeLock();
            removeView(messageView);
            messageView = null;
        });
        super.onDestroy();
    }

    // ---- Remote keys while locked ----

    @Override
    protected boolean onKeyEvent(KeyEvent event) {
        return lockView != null && lockKey(event);
    }

    /**
     * Shared by the accessibility key filter and the focused lock window: on firmware where the
     * filter never sees the remote, the overlay still holds key focus and swallows the keys itself.
     */
    private boolean lockKey(KeyEvent event) {
        int code = event.getKeyCode();
        if (previewLook != null && autoReason == null && !Prefs.get(this).getBoolean(Prefs.LOCKED, false)) {
            if (event.getAction() == KeyEvent.ACTION_UP) main.post(endPreview);
            return true;
        }
        if (code == KeyEvent.KEYCODE_VOLUME_UP || code == KeyEvent.KEYCODE_VOLUME_DOWN
                || code == KeyEvent.KEYCODE_VOLUME_MUTE || code == KeyEvent.KEYCODE_POWER) {
            return false;
        }
        if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) {
            char c = code == KeyEvent.KEYCODE_DPAD_UP ? 'U' : code == KeyEvent.KEYCODE_DPAD_DOWN ? 'D'
                    : code == KeyEvent.KEYCODE_DPAD_LEFT ? 'L' : code == KeyEvent.KEYCODE_DPAD_RIGHT ? 'R' : '.';
            typed.append(c);
            if (typed.length() > 12) typed.delete(0, typed.length() - 12);
            String unlock = Prefs.get(this).getString(Prefs.UNLOCK_CODE, "");
            if (Prefs.validCode(unlock) && typed.toString().endsWith(unlock)) {
                typed.setLength(0);
                main.post(this::parentUnlock);
            }
        }
        return true;
    }

    // ---- HTTP API ----

    private AgentServer.Response handle(AgentServer.Request r) {
        String route = r.method + " " + r.path;
        switch (route) {
            case "GET /status":
                return AgentServer.Response.json(200, statusJson());
            case "POST /sleep":
                return runOnMain(() -> {
                    boolean ok = Build.VERSION.SDK_INT >= 28 && performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN);
                    return ok ? okJson() : AgentServer.Response.error(500, "the TV refused to sleep");
                });
            case "POST /wake":
                wake();
                return okJson();
            case "POST /lock": {
                String message = field(r, "message");
                return runOnMain(() -> { setLocked(true, message); return AgentServer.Response.json(200, statusJson()); });
            }
            case "POST /unlock":
                return runOnMain(() -> { parentUnlock(); return AgentServer.Response.json(200, statusJson()); });
            case "GET /rules":
                return runOnMain(() -> AgentServer.Response.json(200, rulesJson()));
            case "POST /rules":
                return runOnMain(() -> {
                    try {
                        rules.update(new JSONObject(r.bodyText()));
                    } catch (JSONException e) {
                        return AgentServer.Response.error(400, "bad rules: " + e.getMessage());
                    }
                    warned = 0;
                    enforce(System.currentTimeMillis());
                    return AgentServer.Response.json(200, rulesJson());
                });
            case "POST /bonus":
                return runOnMain(() -> {
                    int minutes;
                    try {
                        minutes = new JSONObject(r.bodyText()).getInt("minutes");
                    } catch (JSONException e) {
                        return AgentServer.Response.error(400, "send {\"minutes\":15}");
                    }
                    if (minutes < 1 || minutes > 240) return AgentServer.Response.error(400, "1–240 minutes");
                    long now = System.currentTimeMillis();
                    rules.addBonus(minutes, now);
                    warned = 0;
                    enforce(now);
                    showMessage("ได้เวลาเพิ่มอีก " + minutes + " นาทีจ้า 🎁");
                    return AgentServer.Response.json(200, rulesJson());
                });
            case "POST /pause":
                return runOnMain(() -> {
                    boolean paused;
                    try {
                        paused = new JSONObject(r.bodyText()).getBoolean("today");
                    } catch (JSONException e) {
                        return AgentServer.Response.error(400, "send {\"today\":true}");
                    }
                    long now = System.currentTimeMillis();
                    rules.pauseToday(paused, now);
                    warned = 0;
                    enforce(now);
                    return AgentServer.Response.json(200, rulesJson());
                });
            case "POST /message": {
                String text = field(r, "text");
                if (text == null || text.trim().isEmpty()) return AgentServer.Response.error(400, "empty message");
                wake();
                main.post(() -> showMessage(text.trim()));
                return okJson();
            }
            case "GET /screenshot":
                return screenshot();
            case "GET /activity": {
                String date = ActivityLog.query(r.query).get("date");
                if (date == null) date = ActivityLog.dayKey(System.currentTimeMillis());
                boolean on = ((PowerManager) getSystemService(POWER_SERVICE)).isInteractive();
                String json = activity == null ? null
                        : activity.dayJson(date, on, foregroundPackage, System.currentTimeMillis(), this::label);
                return json == null ? AgentServer.Response.error(400, "date must be YYYY-MM-DD")
                        : AgentServer.Response.json(200, json);
            }
            case "GET /snaps": {
                String date = ActivityLog.query(r.query).get("date");
                if (date == null) date = ActivityLog.dayKey(System.currentTimeMillis());
                String json = snaps == null ? null : snaps.dayJson(date, this::label);
                return json == null ? AgentServer.Response.error(400, "date must be YYYY-MM-DD")
                        : AgentServer.Response.json(200, json);
            }
            case "GET /snap": {
                Map<String, String> q = ActivityLog.query(r.query);
                byte[] data = snaps == null ? null : snaps.read(q.get("date"), q.get("name"));
                return data == null ? AgentServer.Response.error(404, "no such snapshot (kept " + SnapLog.KEEP_DAYS + " days)")
                        : new AgentServer.Response(200, "image/jpeg", data);
            }
            case "GET /look":
                return runOnMain(() -> AgentServer.Response.json(200, lookJson()));
            case "POST /look":
                return runOnMain(() -> {
                    Look next = look.copy();
                    try {
                        next.read(new JSONObject(r.bodyText()));
                    } catch (JSONException e) {
                        return AgentServer.Response.error(400, "bad look: " + e.getMessage());
                    }
                    next.save(Prefs.get(this));
                    look = next;
                    updateLock();
                    return AgentServer.Response.json(200, lookJson());
                });
            case "POST /look/preview":
                return runOnMain(() -> {
                    Look draft = look.copy();
                    String kind;
                    try {
                        JSONObject o = new JSONObject(r.bodyText());
                        draft.read(o);
                        kind = o.optString("kind", "parent");
                    } catch (JSONException e) {
                        return AgentServer.Response.error(400, "bad look: " + e.getMessage());
                    }
                    if (!kind.equals("parent") && !kind.equals(Rules.SCHEDULE) && !kind.equals(Rules.LIMIT)
                            && !kind.equals("warn")) {
                        return AgentServer.Response.error(400, "kind must be parent, schedule, limit or warn");
                    }
                    wake();
                    if (kind.equals("warn")) {
                        showMessage(Look.fill(draft.warnText, words(System.currentTimeMillis(), 5)));
                        return okJson();
                    }
                    previewLook = draft;
                    previewKind = kind;
                    main.removeCallbacks(endPreview);
                    main.postDelayed(endPreview, 10_000);
                    updateLock();
                    return okJson();
                });
            case "GET /kids":
                return runOnMain(() -> AgentServer.Response.json(200, kidsJson()));
            case "POST /kids":
                return runOnMain(() -> {
                    try {
                        JSONObject o = new JSONObject(r.bodyText());
                        java.util.Set<String> apps = null;
                        if (o.has("apps")) {
                            org.json.JSONArray a = o.getJSONArray("apps");
                            apps = new java.util.LinkedHashSet<>();
                            for (int i = 0; i < a.length(); i++) apps.add(a.getString(i));
                        }
                        Kids.set(this, o.has("enabled") ? o.getBoolean("enabled") : null, apps,
                                o.has("auto") ? o.getBoolean("auto") : null);
                    } catch (JSONException e) {
                        return AgentServer.Response.error(400, "bad kids: " + e.getMessage());
                    }
                    kidsBlock(foregroundPackage);
                    return AgentServer.Response.json(200, kidsJson());
                });
            case "GET /config":
                return AgentServer.Response.json(200, "{\"ok\":true,\"unlockCode\":"
                        + Json.quote(Prefs.get(this).getString(Prefs.UNLOCK_CODE, "")) + "}");
            default:
                return AgentServer.Response.error(404, "unknown " + route);
        }
    }

    private static AgentServer.Response okJson() {
        return AgentServer.Response.json(200, "{\"ok\":true}");
    }

    private static String field(AgentServer.Request r, String name) {
        if (r.body.length == 0) return null;
        try {
            String v = new JSONObject(r.bodyText()).optString(name, "");
            if (v.length() > 200) v = v.substring(0, 200);
            return v;
        } catch (JSONException e) {
            return null;
        }
    }

    private interface MainTask { AgentServer.Response run(); }

    private AgentServer.Response runOnMain(MainTask task) {
        AtomicReference<AgentServer.Response> result = new AtomicReference<>();
        CountDownLatch done = new CountDownLatch(1);
        main.post(() -> {
            try { result.set(task.run()); } catch (RuntimeException e) {
                result.set(AgentServer.Response.error(500, String.valueOf(e.getMessage())));
            } finally { done.countDown(); }
        });
        try {
            if (!done.await(5, TimeUnit.SECONDS)) return AgentServer.Response.error(504, "the TV is busy");
        } catch (InterruptedException e) {
            return AgentServer.Response.error(500, "interrupted");
        }
        return result.get();
    }

    private String statusJson() {
        PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
        AudioManager am = (AudioManager) getSystemService(AUDIO_SERVICE);
        SharedPreferences p = Prefs.get(this);
        String pkg = foregroundPackage;
        int max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        int vol = max > 0 ? Math.round(100f * am.getStreamVolume(AudioManager.STREAM_MUSIC) / max) : 0;
        boolean muted = Build.VERSION.SDK_INT >= 23 && am.isStreamMute(AudioManager.STREAM_MUSIC);
        return "{\"ok\":true"
                + ",\"screenOn\":" + pm.isInteractive()
                + ",\"locked\":" + (p.getBoolean(Prefs.LOCKED, false) || autoReason != null)
                + ",\"lockReason\":" + Json.quote(p.getBoolean(Prefs.LOCKED, false) ? "parent" : autoReason)
                + ",\"lockMessage\":" + Json.quote(p.getString(Prefs.LOCK_MESSAGE, ""))
                + ",\"kidsMode\":" + Kids.on(this)
                + ",\"rulesOn\":" + (rules != null && rules.enabled)
                + ",\"usedSec\":" + (rules == null ? 0 : rules.usedSec(System.currentTimeMillis()))
                + ",\"remainingSec\":" + remainingJson()
                + ",\"app\":" + Json.quote(pkg)
                + ",\"appLabel\":" + Json.quote(label(pkg))
                + ",\"volume\":" + vol
                + ",\"muted\":" + muted
                + ",\"uptimeSec\":" + (SystemClock.elapsedRealtime() / 1000)
                + ",\"model\":" + Json.quote(Build.MANUFACTURER + " " + Build.MODEL)
                + ",\"android\":" + Json.quote(Build.VERSION.RELEASE)
                + ",\"agent\":" + Json.quote(VERSION)
                + "}";
    }

    private String label(String pkg) {
        if (pkg == null || pkg.isEmpty()) return "";
        if (pkg.equals("com.gathin.tvhome")) return "Home";
        try {
            PackageManager pm = getPackageManager();
            ApplicationInfo info = pm.getApplicationInfo(pkg, 0);
            return pm.getApplicationLabel(info).toString();
        } catch (PackageManager.NameNotFoundException e) {
            return pkg;
        }
    }

    @SuppressWarnings("deprecation")
    private void wake() {
        PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
        if (pm.isInteractive()) return;
        PowerManager.WakeLock lock = pm.newWakeLock(PowerManager.FULL_WAKE_LOCK
                | PowerManager.ACQUIRE_CAUSES_WAKEUP | PowerManager.ON_AFTER_RELEASE, "peach:wake");
        lock.acquire(3000);
    }

    // ---- Screenshot (Android 11+) ----

    private interface Shot { void done(byte[] jpeg, String error); }

    private AgentServer.Response screenshot() {
        if (Build.VERSION.SDK_INT < 30) return AgentServer.Response.error(501, "needs Android 11 or newer");
        PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
        if (!pm.isInteractive()) return AgentServer.Response.error(409, "the TV screen is off");
        AtomicReference<byte[]> jpeg = new AtomicReference<>();
        AtomicReference<String> error = new AtomicReference<>();
        CountDownLatch done = new CountDownLatch(1);
        main.post(() -> capture(1280, 82, false, (data, e) -> {
            jpeg.set(data);
            error.set(e);
            done.countDown();
        }));
        try {
            if (!done.await(8, TimeUnit.SECONDS)) return AgentServer.Response.error(504, "screenshot timed out");
        } catch (InterruptedException e) {
            return AgentServer.Response.error(500, "interrupted");
        }
        byte[] data = jpeg.get();
        if (data == null) return AgentServer.Response.error(500, error.get() == null ? "no image" : error.get());
        return new AgentServer.Response(200, "image/jpeg", data);
    }

    /** History snapshot: an app (not Home) on a lit, unlocked, awake screen, at open and every 10 minutes. */
    private void maybeSnap(long now) {
        String pkg = snapPkg;
        if (snaps == null || Build.VERSION.SDK_INT < 30 || pkg.isEmpty() || pkg.equals("com.gathin.tvhome")
                || !pkg.equals(foregroundPackage) || lockView != null || dreaming
                || !((PowerManager) getSystemService(POWER_SERVICE)).isInteractive()) return;
        if (lastSnapAt > 0 && now - lastSnapAt < SnapLog.EVERY_MS) return;
        lastSnapAt = now;
        capture(640, 60, true, (data, error) -> {
            if (data != null) snaps.save(now, pkg, data);
        });
    }

    /**
     * Captures the screen and encodes a JPEG off the main thread. With {@code skipBlack} an all-black
     * frame (Live TV, HDMI and DRM video come back black) reports null instead of a useless picture.
     */
    private void capture(int maxWidth, int quality, boolean skipBlack, Shot shot) {
        takeScreenshot(Display.DEFAULT_DISPLAY, getMainExecutor(), new TakeScreenshotCallback() {
            @Override
            public void onSuccess(ScreenshotResult result) {
                HardwareBuffer buffer = result.getHardwareBuffer();
                new Thread(() -> {
                    try {
                        Bitmap hw = Bitmap.wrapHardwareBuffer(buffer, result.getColorSpace());
                        if (hw == null) { shot.done(null, "could not read the screen"); return; }
                        Bitmap soft = hw.copy(Bitmap.Config.ARGB_8888, false);
                        hw.recycle();
                        int w = soft.getWidth(), h = soft.getHeight();
                        Bitmap out = soft;
                        if (w > maxWidth) {
                            out = Bitmap.createScaledBitmap(soft, maxWidth, Math.round(h * (float) maxWidth / w), true);
                            soft.recycle();
                        }
                        if (skipBlack && isBlack(out)) {
                            out.recycle();
                            shot.done(null, "black frame");
                            return;
                        }
                        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                        out.compress(Bitmap.CompressFormat.JPEG, quality, bytes);
                        out.recycle();
                        shot.done(bytes.toByteArray(), null);
                    } catch (RuntimeException e) {
                        shot.done(null, String.valueOf(e.getMessage()));
                    } finally {
                        buffer.close();
                    }
                }, "peach-shot").start();
            }

            @Override
            public void onFailure(int code) {
                shot.done(null, code == ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT ? "too fast, try again in a second"
                        : "the TV refused the screenshot (" + code + ")");
            }
        });
    }

    private static boolean isBlack(Bitmap b) {
        int w = b.getWidth(), h = b.getHeight();
        for (int y = 1; y < 8; y++) {
            for (int x = 1; x < 8; x++) {
                int c = b.getPixel(x * w / 8, y * h / 8);
                if (Color.red(c) + Color.green(c) + Color.blue(c) > 45) return false;
            }
        }
        return true;
    }

    // ---- Lock screen ----

    private void setLocked(boolean locked, String message) {
        SharedPreferences.Editor e = Prefs.get(this).edit().putBoolean(Prefs.LOCKED, locked);
        e.putString(Prefs.LOCK_MESSAGE, locked && message != null ? message : "");
        e.commit();
        if (activity != null) activity.lock(locked, System.currentTimeMillis());
        if (locked) wake();
        updateLock();
        Log.i(TAG, locked ? "locked" : "unlocked");
    }

    /** Phone Unlock or the remote's unlock code: lifts a parent lock, or pauses the rules for today. */
    private void parentUnlock() {
        if (Prefs.get(this).getBoolean(Prefs.LOCKED, false)) {
            setLocked(false, null);
        } else if (autoReason != null) {
            long now = System.currentTimeMillis();
            rules.pauseToday(true, now);
            enforce(now);
            showMessage("ปลดล็อกแล้ว ดูได้ถึงเที่ยงคืนนะ 🍑");
        }
    }

    /** Shows the lock for a parent lock, a rule or a phone preview, with the matching look and words, or removes it. */
    private void updateLock() {
        SharedPreferences p = Prefs.get(this);
        boolean manual = p.getBoolean(Prefs.LOCKED, false);
        String reason = autoReason;
        boolean preview = previewLook != null;
        if (!manual && reason == null && !preview) {
            removeLock();
            return;
        }
        Look l = preview ? previewLook : look;
        String kind = preview ? previewKind : manual ? "parent" : reason;
        long now = System.currentTimeMillis();
        Map<String, String> w = words(now, 0);
        String message, sub;
        if ("parent".equals(kind)) {
            message = preview && !manual ? "ถึงเวลาพักสายตาแล้วนะ" : p.getString(Prefs.LOCK_MESSAGE, "");
            sub = l.parentSub;
        } else if (Rules.SCHEDULE.equals(kind)) {
            message = Look.fill(l.scheduleText, w);
            sub = "TV TIME " + w.get("from") + " – " + w.get("to");
        } else {
            message = Look.fill(l.limitText, w);
            sub = "SCREEN TIME " + w.get("limit") + " · SEE YOU TOMORROW";
        }
        if (preview) sub = (sub.isEmpty() ? "" : sub + "  ·  ") + "PREVIEW";
        showLock(message, sub, l.style(kind));
    }

    /** Values for {from} {to} {limit} {min} in the wording. */
    private Map<String, String> words(long now, long minutesLeft) {
        Map<String, String> w = new HashMap<>();
        w.put("from", Rules.hhmm(rules.fromToday(now)));
        w.put("to", Rules.hhmm(rules.toToday(now)));
        w.put("limit", Look.thaiMinutes(rules.limitTodaySec(now) / 60));
        w.put("min", String.valueOf(minutesLeft));
        return w;
    }

    private String lookJson() {
        return "{\"ok\":true,\"look\":" + look.json() + ",\"themes\":" + Look.themesJson() + "}";
    }

    // ---- Family rules ----

    private void enforce(long now) {
        if (rules == null) return;
        boolean screenOn = ((PowerManager) getSystemService(POWER_SERVICE)).isInteractive();
        boolean manual = Prefs.get(this).getBoolean(Prefs.LOCKED, false);
        if (screenOn && !dreaming && !manual && autoReason == null && lastTick > 0) {
            rules.addUsage(Math.min(60, Math.max(0, (now - lastTick) / 1000)), now);
        }
        lastTick = screenOn ? now : 0;

        String reason = rules.blockReason(now);
        if (!Objects.equals(reason, autoReason)) {
            autoReason = reason;
            autoSince = now;
            if (activity != null) activity.mark(reason == null ? "allowed" : reason, now);
            updateLock();
        }
        if (reason == null && !manual && screenOn && !dreaming) {
            long left = rules.remainingSec(now);
            if (left < 0 || left > 300) warned = 0;
            else if (left <= 60 && warned < 2) { warned = 2; showMessage(Look.fill(look.warnText, words(now, 1))); }
            else if (left > 60 && warned < 1) { warned = 1; showMessage(Look.fill(look.warnText, words(now, (left + 59) / 60))); }
        }
        if (reason != null && rules.turnOff && screenOn && !manual && now - autoSince >= 5 * 60_000L
                && Build.VERSION.SDK_INT >= 28) {
            performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN);
        }
        // Nobody watches a lock screen: after lockOffMin on a lit screen, turn the TV off.
        boolean lockedNow = manual || reason != null;
        if (!screenOn || !lockedNow) {
            lockedSince = 0;
        } else if (lockedSince == 0) {
            lockedSince = now;
        } else if (rules.lockOffMin > 0 && now - lockedSince >= rules.lockOffMin * 60_000L
                && Build.VERSION.SDK_INT >= 28) {
            lockedSince = 0;
            if (activity != null) activity.mark("lockoff", now);
            performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN);
        }
    }

    private String rulesJson() {
        long now = System.currentTimeMillis();
        return "{\"ok\":true,\"rules\":" + rules.configJson() + ",\"today\":" + rules.todayJson(now, autoReason) + "}";
    }

    private String remainingJson() {
        if (rules == null) return "null";
        long left = rules.remainingSec(System.currentTimeMillis());
        return left < 0 ? "null" : String.valueOf(left);
    }

    private void removeLock() {
        if (floatAnim != null) floatAnim.cancel();
        floatAnim = null;
        removeView(lockView);
        lockView = null;
        shownKey = null;
        releaseAudio();
    }

    private void showLock(String message, String subText, Look.Style l) {
        String text = message == null || message.trim().isEmpty() ? "ถึงเวลาพักสายตาแล้วนะ" : message.trim();
        Look.Theme t = l.themeObj();
        if (lockView != null && l.key().equals(shownKey)) {
            lockMessageText.setText(text);
            lockSubText.setText(subText);
            return;
        }
        // A different theme: rebuild the window (keeps the audio focus held while locked).
        if (floatAnim != null) floatAnim.cancel();
        floatAnim = null;
        removeView(lockView);
        lockView = null;
        FrameLayout root = new FrameLayout(this) {
            @Override
            public boolean dispatchKeyEvent(KeyEvent event) {
                return lockKey(event) || super.dispatchKeyEvent(event);
            }
        };
        root.setFocusable(true);
        root.setFocusableInTouchMode(true);
        root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, t.bg));

        if (l.sprinkle && !t.sprinkle.isEmpty()) {
            // Fixed scatter of small faded emoji around the edges: a background, cheap to draw.
            float[][] spots = {{0.06f, 0.10f, 34}, {0.20f, 0.78f, 26}, {0.88f, 0.14f, 30}, {0.93f, 0.66f, 38},
                    {0.72f, 0.88f, 24}, {0.12f, 0.45f, 22}, {0.80f, 0.40f, 20}, {0.35f, 0.08f, 20},
                    {0.55f, 0.92f, 28}, {0.04f, 0.88f, 30}, {0.64f, 0.06f, 26}, {0.97f, 0.92f, 22}};
            int sw = getResources().getDisplayMetrics().widthPixels, sh = getResources().getDisplayMetrics().heightPixels;
            for (float[] s : spots) {
                TextView d = text(t.sprinkle, (int) s[2], Color.WHITE, false);
                d.setAlpha(0.22f);
                d.setRotation((s[0] * 97 % 40) - 20);
                FrameLayout.LayoutParams at = new FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT);
                at.leftMargin = Math.round(s[0] * sw) - dp((int) s[2]) / 2;
                at.topMargin = Math.round(s[1] * sh) - dp((int) s[2]) / 2;
                root.addView(d, at);
            }
        }

        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView big = text(l.bigEmoji(), 110, Color.WHITE, false);
        lockMessageText = text(text, 44, t.text, false);
        lockMessageText.setMaxWidth(dp(900));
        TextView sub = text(subText, 20, t.accent, true);
        lockSubText = sub;
        sub.setLetterSpacing(0.12f);
        sub.setPadding(0, dp(18), 0, 0);
        column.addView(big);
        column.addView(lockMessageText);
        column.addView(sub);
        root.addView(column, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER));
        if (l.animate) {
            floatAnim = android.animation.ObjectAnimator.ofFloat(big, "translationY", 0f, -dp(14));
            floatAnim.setDuration(1800);
            floatAnim.setRepeatMode(android.animation.ValueAnimator.REVERSE);
            floatAnim.setRepeatCount(android.animation.ValueAnimator.INFINITE);
            floatAnim.setInterpolator(new android.view.animation.AccelerateDecelerateInterpolator());
        }

        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN | WindowManager.LayoutParams.FLAG_FULLSCREEN,
                PixelFormat.OPAQUE);
        try {
            windows.addView(root, lp);
            root.requestFocus();
            lockView = root;
            shownKey = l.key();
            if (floatAnim != null) floatAnim.start();
            holdAudio();
        } catch (RuntimeException e) {
            Log.w(TAG, "lock overlay", e);
        }
    }

    /** Taking audio focus makes most players (Netflix, YouTube) pause behind the lock screen. */
    private void holdAudio() {
        if (focusRequest != null) return;
        AudioManager am = (AudioManager) getSystemService(AUDIO_SERVICE);
        focusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build())
                .setOnAudioFocusChangeListener(change -> { })
                .build();
        am.requestAudioFocus(focusRequest);
    }

    private void releaseAudio() {
        if (focusRequest == null) return;
        ((AudioManager) getSystemService(AUDIO_SERVICE)).abandonAudioFocusRequest(focusRequest);
        focusRequest = null;
    }

    // ---- Message bubble ----

    private void showMessage(String message) {
        removeView(messageView);
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setGravity(Gravity.CENTER_VERTICAL);
        int pad = dp(22);
        card.setPadding(pad, dp(16), pad + dp(8), dp(16));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(0xF0221110);
        bg.setCornerRadius(dp(36));
        bg.setStroke(dp(2), PEACH);
        card.setBackground(bg);
        TextView icon = text("🍑", 34, Color.WHITE, false);
        icon.setPadding(0, 0, dp(14), 0);
        TextView body = text(message, 26, CREAM, false);
        body.setMaxWidth(dp(820));
        card.addView(icon);
        card.addView(body);

        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                PixelFormat.TRANSLUCENT);
        lp.gravity = Gravity.TOP | Gravity.CENTER_HORIZONTAL;
        lp.y = dp(40);
        try {
            windows.addView(card, lp);
            messageView = card;
            View shown = card;
            main.postDelayed(() -> {
                if (messageView == shown) {
                    removeView(shown);
                    messageView = null;
                }
            }, 12_000);
        } catch (RuntimeException e) {
            Log.w(TAG, "message overlay", e);
        }
    }

    // ---- helpers ----

    private TextView text(String s, int sp, int color, boolean caps) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        t.setGravity(Gravity.CENTER);
        t.setTypeface(Typeface.create("sans-serif-light", Typeface.NORMAL));
        t.setAllCaps(caps);
        return t;
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    private void removeView(View v) {
        if (v == null || windows == null) return;
        try { windows.removeViewImmediate(v); } catch (RuntimeException ignored) { }
    }
}
