package com.lookpeach.tvagent;

import android.content.Context;
import android.content.SharedPreferences;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * What the TV did, one file per day in files/activity/YYYY-MM-DD.tsv (TV local time), kept 60 days.
 * Each line is "epochMs \t kind [\t package]" with kind on, off, app, lock or unlock. The phone
 * reads ready-made spans through {@link #dayJson}, so the history survives while the TV is offline.
 */
final class ActivityLog {
    interface Labeler { String label(String pkg); }

    private static final int KEEP_DAYS = 60;
    /** A heartbeat older than this when the agent starts means the TV lost power without an "off". */
    static final long HEARTBEAT_MS = 60_000;
    private static final long STALE_MS = 3 * HEARTBEAT_MS;
    private static final String LAST_ON = "act_on";
    private static final String LAST_APP = "act_app";
    private static final String ALIVE = "act_alive";

    private final File dir;
    private final SharedPreferences prefs;

    ActivityLog(Context c) {
        dir = new File(c.getFilesDir(), "activity");
        //noinspection ResultOfMethodCallIgnored
        dir.mkdirs();
        prefs = Prefs.get(c);
        prune();
    }

    /** Called when the agent starts (boot, reinstall, re-enable). Closes a session a power cut left open. */
    synchronized void start(boolean screenOn, long now) {
        boolean wasOn = prefs.getBoolean(LAST_ON, false);
        long alive = prefs.getLong(ALIVE, 0);
        if (wasOn && (now - alive > STALE_MS || !screenOn)) {
            write(alive > 0 && now - alive > STALE_MS ? alive : now, "off", null);
            wasOn = false;
        }
        if (screenOn && !wasOn) write(now, "on", null);
        heartbeat(now);
    }

    synchronized void screen(boolean on, long now) {
        if (prefs.getBoolean(LAST_ON, false) == on) return;
        write(now, on ? "on" : "off", null);
        heartbeat(now);
    }

    synchronized void app(String pkg, long now) {
        if (pkg.equals(prefs.getString(LAST_APP, ""))) return;
        write(now, "app", pkg);
    }

    synchronized void lock(boolean locked, long now) {
        write(now, locked ? "lock" : "unlock", null);
    }

    /** Rule events for the timeline: schedule, limit, allowed, lockoff. */
    synchronized void mark(String kind, long now) {
        write(now, kind, null);
    }

    void heartbeat(long now) {
        prefs.edit().putLong(ALIVE, now).apply();
    }

    private void write(long time, String kind, String pkg) {
        SharedPreferences.Editor e = prefs.edit();
        if (kind.equals("on")) e.putBoolean(LAST_ON, true);
        if (kind.equals("off")) e.putBoolean(LAST_ON, false);
        if (kind.equals("app")) e.putString(LAST_APP, pkg);
        e.apply();
        String line = time + "\t" + kind + (pkg == null ? "" : "\t" + pkg) + "\n";
        try (FileOutputStream out = new FileOutputStream(file(dayKey(time)), true)) {
            out.write(line.getBytes(StandardCharsets.UTF_8));
        } catch (IOException ignored) {
        }
    }

    // ---- Reading ----

    private static final class Event {
        final long time; final String kind; final String pkg;
        Event(long time, String kind, String pkg) { this.time = time; this.kind = kind; this.pkg = pkg; }
    }

    /** JSON for one day: TV-on sessions, app spans (from–to), lock marks and per-app totals. */
    synchronized String dayJson(String date, boolean screenOnNow, String appNow, long now, Labeler labeler) {
        long start = parseDay(date);
        if (start < 0) return null;
        long end = Math.min(nextDay(start), now);
        List<Event> events = new ArrayList<>();
        for (int back = 3; back >= 1; back--) read(dayKey(start - back * 86_400_000L + 3_600_000L), events);
        read(date, events);
        Collections.sort(events, (a, b) -> Long.compare(a.time, b.time));

        StringBuilder sessions = new StringBuilder();
        StringBuilder apps = new StringBuilder();
        StringBuilder marks = new StringBuilder();
        Map<String, Long> totals = new LinkedHashMap<>();
        long onTotal = 0;
        boolean on = false;
        long onSince = 0, appSince = 0;
        String app = "";
        for (Event ev : events) {
            if (ev.time >= end) break;
            switch (ev.kind) {
                case "on":
                    if (on) break;
                    on = true; onSince = ev.time; appSince = ev.time;
                    break;
                case "off":
                    if (!on) break;
                    onTotal += span(sessions, null, onSince, ev.time, start, false);
                    spanApp(apps, totals, app, appSince, ev.time, start, false, labeler);
                    on = false;
                    break;
                case "app":
                    if (on) spanApp(apps, totals, app, appSince, ev.time, start, false, labeler);
                    app = ev.pkg == null ? "" : ev.pkg; appSince = ev.time;
                    break;
                case "lock": case "unlock": case "schedule": case "limit": case "allowed": case "lockoff":
                    if (ev.time >= start) {
                        if (marks.length() > 0) marks.append(',');
                        marks.append("{\"time\":").append(ev.time).append(",\"kind\":").append(Json.quote(ev.kind)).append('}');
                    }
                    break;
                default:
            }
        }
        if (on) {
            boolean ongoing = end == now && screenOnNow;
            onTotal += span(sessions, null, onSince, end, start, ongoing);
            spanApp(apps, totals, app, appSince, end, start, ongoing, labeler);
        }

        StringBuilder total = new StringBuilder();
        List<Map.Entry<String, Long>> sorted = new ArrayList<>(totals.entrySet());
        Collections.sort(sorted, (a, b) -> Long.compare(b.getValue(), a.getValue()));
        for (Map.Entry<String, Long> t : sorted) {
            if (total.length() > 0) total.append(',');
            total.append("{\"app\":").append(Json.quote(t.getKey()))
                    .append(",\"label\":").append(Json.quote(labeler.label(t.getKey())))
                    .append(",\"seconds\":").append(t.getValue() / 1000).append('}');
        }
        return "{\"ok\":true,\"date\":" + Json.quote(date)
                + ",\"dayStart\":" + start + ",\"now\":" + now
                + ",\"onSeconds\":" + onTotal / 1000
                + ",\"sessions\":[" + sessions + "]"
                + ",\"apps\":[" + apps + "]"
                + ",\"totals\":[" + total + "]"
                + ",\"marks\":[" + marks + "]"
                + ",\"days\":" + daysJson() + "}";
    }

    /** Appends one span clipped to the day; returns its clipped length in ms. */
    private static long span(StringBuilder out, String extra, long from, long to, long dayStart,
                             boolean ongoing) {
        long a = Math.max(from, dayStart);
        if (to <= a) return 0;
        if (out.length() > 0) out.append(',');
        out.append("{\"start\":").append(a).append(",\"end\":").append(to)
                .append(",\"ongoing\":").append(ongoing);
        if (extra != null) out.append(',').append(extra);
        out.append('}');
        return to - a;
    }

    private static void spanApp(StringBuilder out, Map<String, Long> totals, String pkg, long from, long to,
                                long dayStart, boolean ongoing, Labeler labeler) {
        if (pkg == null || pkg.isEmpty()) return;
        long length = span(out, "\"app\":" + Json.quote(pkg) + ",\"label\":" + Json.quote(labeler.label(pkg)),
                from, to, dayStart, ongoing);
        if (length > 0) {
            Long old = totals.get(pkg);
            totals.put(pkg, (old == null ? 0 : old) + length);
        }
    }

    private void read(String day, List<Event> into) {
        File f = file(day);
        if (!f.isFile()) return;
        try (BufferedReader in = new BufferedReader(new InputStreamReader(new FileInputStream(f), StandardCharsets.UTF_8))) {
            String line;
            while ((line = in.readLine()) != null) {
                String[] parts = line.split("\t");
                if (parts.length < 2) continue;
                try {
                    into.add(new Event(Long.parseLong(parts[0]), parts[1], parts.length > 2 ? parts[2] : null));
                } catch (NumberFormatException ignored) {
                }
            }
        } catch (IOException ignored) {
        }
    }

    private String daysJson() {
        String[] names = dir.list();
        List<String> days = new ArrayList<>();
        if (names != null) for (String n : names) if (n.endsWith(".tsv")) days.add(n.substring(0, n.length() - 4));
        Collections.sort(days);
        StringBuilder b = new StringBuilder("[");
        for (int i = 0; i < days.size(); i++) b.append(i > 0 ? "," : "").append(Json.quote(days.get(i)));
        return b.append(']').toString();
    }

    private void prune() {
        String[] names = dir.list();
        if (names == null) return;
        String oldest = dayKey(System.currentTimeMillis() - KEEP_DAYS * 86_400_000L);
        for (String n : names) {
            //noinspection ResultOfMethodCallIgnored
            if (n.endsWith(".tsv") && n.compareTo(oldest) < 0) new File(dir, n).delete();
        }
    }

    private File file(String day) { return new File(dir, day + ".tsv"); }

    static String dayKey(long time) {
        Calendar c = Calendar.getInstance();
        c.setTimeInMillis(time);
        return String.format(Locale.ROOT, "%04d-%02d-%02d",
                c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH));
    }

    /** Local midnight of "YYYY-MM-DD", or -1. */
    static long parseDay(String date) {
        if (date == null || !date.matches("\\d{4}-\\d{2}-\\d{2}")) return -1;
        Calendar c = Calendar.getInstance();
        c.clear();
        c.set(Integer.parseInt(date.substring(0, 4)), Integer.parseInt(date.substring(5, 7)) - 1,
                Integer.parseInt(date.substring(8, 10)), 0, 0, 0);
        return c.getTimeInMillis();
    }

    private static long nextDay(long midnight) {
        Calendar c = Calendar.getInstance();
        c.setTimeInMillis(midnight);
        c.add(Calendar.DAY_OF_MONTH, 1);
        return c.getTimeInMillis();
    }

    static Map<String, String> query(String q) {
        Map<String, String> out = new HashMap<>();
        if (q == null) return out;
        for (String pair : q.split("&")) {
            int eq = pair.indexOf('=');
            if (eq > 0) out.put(pair.substring(0, eq), pair.substring(eq + 1));
        }
        return out;
    }
}
