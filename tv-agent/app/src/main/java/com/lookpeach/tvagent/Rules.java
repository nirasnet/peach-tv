package com.lookpeach.tvagent;

import android.content.SharedPreferences;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.Calendar;

/**
 * Family TV rules, enforced on the TV so they work without the phone: allowed hours and a daily
 * screen-time limit, each with weekday (Mon–Fri) and weekend values. Screen time counts while the
 * screen is on and not locked. A bonus from the phone adds minutes; a parent override pauses the
 * rules until midnight.
 */
final class Rules {
    static final String SCHEDULE = "schedule";
    static final String LIMIT = "limit";

    private static final String CONFIG = "rules";
    private static final String USE_DAY = "use_day";
    private static final String USE_SEC = "use_sec";
    private static final String BONUS_SEC = "bonus_sec";
    private static final String GRANT_UNTIL = "grant_until";
    private static final String PAUSE_DAY = "pause_day";

    boolean enabled = false;
    boolean scheduleOn = true;
    boolean limitOn = true;
    boolean turnOff = false;
    /** Any lock (parent or rule) left on screen this long turns the TV off; 0 = never. Works with the rules off. */
    int lockOffMin = 10;
    int weekdayFrom = 7 * 60, weekdayTo = 20 * 60 + 30;
    int weekendFrom = 8 * 60, weekendTo = 21 * 60;
    int weekdayLimit = 60, weekendLimit = 120;

    private final SharedPreferences prefs;

    Rules(SharedPreferences prefs) {
        this.prefs = prefs;
        String saved = prefs.getString(CONFIG, "");
        if (!saved.isEmpty()) {
            try { read(new JSONObject(saved)); } catch (JSONException ignored) { }
        }
    }

    // ---- Config ----

    /** Applies the fields present in {@code o}; throws on bad values so the phone sees the error. */
    void update(JSONObject o) throws JSONException {
        Rules probe = new Rules(prefs);
        probe.read(o);
        read(o);
        prefs.edit().putString(CONFIG, configJson()).commit();
    }

    private void read(JSONObject o) throws JSONException {
        if (o.has("enabled")) enabled = o.getBoolean("enabled");
        if (o.has("turnOff")) turnOff = o.getBoolean("turnOff");
        if (o.has("lockOffMin")) {
            int m = o.getInt("lockOffMin");
            if (m < 0 || m > 240) throw new JSONException("lockOffMin must be 0–240 minutes");
            lockOffMin = m;
        }
        JSONObject s = o.optJSONObject("schedule");
        if (s != null) {
            if (s.has("enabled")) scheduleOn = s.getBoolean("enabled");
            if (s.has("weekdayFrom")) weekdayFrom = minute(s.getInt("weekdayFrom"));
            if (s.has("weekdayTo")) weekdayTo = minute(s.getInt("weekdayTo"));
            if (s.has("weekendFrom")) weekendFrom = minute(s.getInt("weekendFrom"));
            if (s.has("weekendTo")) weekendTo = minute(s.getInt("weekendTo"));
        }
        JSONObject l = o.optJSONObject("limit");
        if (l != null) {
            if (l.has("enabled")) limitOn = l.getBoolean("enabled");
            if (l.has("weekdayMin")) weekdayLimit = limitMinutes(l.getInt("weekdayMin"));
            if (l.has("weekendMin")) weekendLimit = limitMinutes(l.getInt("weekendMin"));
        }
    }

    private static int minute(int m) throws JSONException {
        if (m < 0 || m > 24 * 60) throw new JSONException("time must be 0–1440 minutes");
        return m;
    }

    private static int limitMinutes(int m) throws JSONException {
        if (m < 5 || m > 24 * 60) throw new JSONException("limit must be 5–1440 minutes");
        return m;
    }

    String configJson() {
        return "{\"enabled\":" + enabled + ",\"turnOff\":" + turnOff + ",\"lockOffMin\":" + lockOffMin
                + ",\"schedule\":{\"enabled\":" + scheduleOn
                + ",\"weekdayFrom\":" + weekdayFrom + ",\"weekdayTo\":" + weekdayTo
                + ",\"weekendFrom\":" + weekendFrom + ",\"weekendTo\":" + weekendTo + "}"
                + ",\"limit\":{\"enabled\":" + limitOn
                + ",\"weekdayMin\":" + weekdayLimit + ",\"weekendMin\":" + weekendLimit + "}}";
    }

    // ---- Today ----

    private static boolean weekend(Calendar c) {
        int d = c.get(Calendar.DAY_OF_WEEK);
        return d == Calendar.SATURDAY || d == Calendar.SUNDAY;
    }

    private static Calendar at(long now) {
        Calendar c = Calendar.getInstance();
        c.setTimeInMillis(now);
        return c;
    }

    int fromToday(long now) { return weekend(at(now)) ? weekendFrom : weekdayFrom; }
    int toToday(long now) { return weekend(at(now)) ? weekendTo : weekdayTo; }
    int limitTodaySec(long now) { return (weekend(at(now)) ? weekendLimit : weekdayLimit) * 60; }

    /** Resets the counters at midnight. */
    private void roll(long now) {
        String today = ActivityLog.dayKey(now);
        if (!today.equals(prefs.getString(USE_DAY, ""))) {
            prefs.edit().putString(USE_DAY, today).putLong(USE_SEC, 0).putLong(BONUS_SEC, 0).apply();
        }
    }

    void addUsage(long seconds, long now) {
        roll(now);
        prefs.edit().putLong(USE_SEC, prefs.getLong(USE_SEC, 0) + seconds).apply();
    }

    long usedSec(long now) { roll(now); return prefs.getLong(USE_SEC, 0); }
    long bonusSec(long now) { roll(now); return prefs.getLong(BONUS_SEC, 0); }
    long grantUntil() { return prefs.getLong(GRANT_UNTIL, 0); }

    /** Extra minutes for today: more screen time, and that long past the end of TV hours. */
    void addBonus(int minutes, long now) {
        roll(now);
        long grant = Math.max(now, grantUntil()) + minutes * 60_000L;
        prefs.edit().putLong(BONUS_SEC, bonusSec(now) + minutes * 60L).putLong(GRANT_UNTIL, grant).apply();
    }

    boolean pausedToday(long now) { return ActivityLog.dayKey(now).equals(prefs.getString(PAUSE_DAY, "")); }

    void pauseToday(boolean paused, long now) {
        prefs.edit().putString(PAUSE_DAY, paused ? ActivityLog.dayKey(now) : "").apply();
    }

    private boolean inHours(long now) {
        Calendar c = at(now);
        int m = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE);
        int from = fromToday(now), to = toToday(now);
        if (from == to) return true;
        return from < to ? m >= from && m < to : m >= from || m < to;
    }

    /** Why the TV must be locked now, or null. */
    String blockReason(long now) {
        if (!enabled || pausedToday(now)) return null;
        if (scheduleOn && !inHours(now) && now >= grantUntil()) return SCHEDULE;
        if (limitOn && usedSec(now) >= limitTodaySec(now) + bonusSec(now)) return LIMIT;
        return null;
    }

    /** Seconds of TV left before a rule locks it, or -1 when nothing will. */
    long remainingSec(long now) {
        if (!enabled || pausedToday(now)) return -1;
        if (blockReason(now) != null) return 0;
        long left = -1;
        if (limitOn) left = Math.max(0, limitTodaySec(now) + bonusSec(now) - usedSec(now));
        if (scheduleOn && inHours(now)) {
            int to = toToday(now), from = fromToday(now);
            if (from != to) {
                Calendar end = at(now);
                end.set(Calendar.HOUR_OF_DAY, 0);
                end.set(Calendar.MINUTE, 0);
                end.set(Calendar.SECOND, 0);
                end.set(Calendar.MILLISECOND, 0);
                end.add(Calendar.MINUTE, to);
                if (end.getTimeInMillis() <= now) end.add(Calendar.DAY_OF_MONTH, 1);
                long untilEnd = (Math.max(end.getTimeInMillis(), grantUntil()) - now) / 1000;
                left = left < 0 ? untilEnd : Math.min(left, untilEnd);
            }
        } else if (scheduleOn && now < grantUntil()) {
            long g = (grantUntil() - now) / 1000;
            left = left < 0 ? g : Math.min(left, g);
        }
        return left;
    }

    String todayJson(long now, String reason) {
        long remaining = remainingSec(now);
        return "{\"usedSec\":" + usedSec(now)
                + ",\"limitSec\":" + limitTodaySec(now)
                + ",\"bonusSec\":" + bonusSec(now)
                + ",\"remainingSec\":" + (remaining < 0 ? "null" : String.valueOf(remaining))
                + ",\"from\":" + fromToday(now) + ",\"to\":" + toToday(now)
                + ",\"weekend\":" + weekend(at(now))
                + ",\"paused\":" + pausedToday(now)
                + ",\"grantUntil\":" + grantUntil()
                + ",\"blocked\":" + (reason == null ? "null" : Json.quote(reason)) + "}";
    }

    static String hhmm(int minutes) {
        return String.format(java.util.Locale.ROOT, "%02d:%02d", (minutes / 60) % 24, minutes % 60);
    }
}
