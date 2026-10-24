package com.lookpeach.tvagent;

import android.content.Context;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Small screen snapshots of what was on: files/snaps/YYYY-MM-DD/epochMs_package.jpg, kept 7 days.
 * The agent takes one when an app opens and every 10 minutes while it stays on screen.
 */
final class SnapLog {
    static final long EVERY_MS = 10 * 60_000L;
    static final int KEEP_DAYS = 7;
    private static final Pattern NAME = Pattern.compile("\\d{13}_[A-Za-z0-9._]{1,120}\\.jpg");
    private static final Pattern DAY = Pattern.compile("\\d{4}-\\d{2}-\\d{2}");

    private final File dir;
    private String prunedDay = "";

    SnapLog(Context c) {
        dir = new File(c.getFilesDir(), "snaps");
        //noinspection ResultOfMethodCallIgnored
        dir.mkdirs();
    }

    synchronized void save(long time, String pkg, byte[] jpeg) {
        String day = ActivityLog.dayKey(time);
        File d = new File(dir, day);
        //noinspection ResultOfMethodCallIgnored
        d.mkdirs();
        File f = new File(d, time + "_" + pkg.replaceAll("[^A-Za-z0-9._]", "_") + ".jpg");
        try (FileOutputStream out = new FileOutputStream(f)) {
            out.write(jpeg);
        } catch (IOException ignored) {
        }
        if (!day.equals(prunedDay)) prune(time);
    }

    /** Deletes day folders older than {@link #KEEP_DAYS}. */
    synchronized void prune(long now) {
        prunedDay = ActivityLog.dayKey(now);
        String oldest = ActivityLog.dayKey(now - (KEEP_DAYS - 1) * 86_400_000L);
        File[] days = dir.listFiles();
        if (days == null) return;
        for (File d : days) {
            if (d.getName().compareTo(oldest) >= 0) continue;
            File[] files = d.listFiles();
            if (files != null) for (File f : files) //noinspection ResultOfMethodCallIgnored
                f.delete();
            //noinspection ResultOfMethodCallIgnored
            d.delete();
        }
    }

    /** {"ok":true,"date":..,"keepDays":7,"snaps":[{"time","app","label","name"}],"days":[..]} or null for a bad date. */
    synchronized String dayJson(String date, ActivityLog.Labeler labeler) {
        if (!DAY.matcher(date).matches()) return null;
        StringBuilder out = new StringBuilder("{\"ok\":true,\"date\":").append(Json.quote(date))
                .append(",\"keepDays\":").append(KEEP_DAYS).append(",\"snaps\":[");
        String[] names = new File(dir, date).list();
        if (names != null) {
            Arrays.sort(names);
            boolean first = true;
            for (String n : names) {
                if (!NAME.matcher(n).matches()) continue;
                String pkg = n.substring(14, n.length() - 4);
                if (!first) out.append(',');
                first = false;
                out.append("{\"time\":").append(n.substring(0, 13))
                        .append(",\"app\":").append(Json.quote(pkg))
                        .append(",\"label\":").append(Json.quote(labeler.label(pkg)))
                        .append(",\"name\":").append(Json.quote(n)).append('}');
            }
        }
        out.append("],\"days\":[");
        List<String> days = new ArrayList<>();
        String[] all = dir.list();
        if (all != null) for (String d : all) if (DAY.matcher(d).matches()) days.add(d);
        Collections.sort(days);
        for (int i = 0; i < days.size(); i++) out.append(i == 0 ? "" : ",").append(Json.quote(days.get(i)));
        return out.append("]}").toString();
    }

    /** The JPEG, or null when the name is not one of ours (no paths) or it was deleted. */
    synchronized byte[] read(String date, String name) {
        if (date == null || name == null || !DAY.matcher(date).matches() || !NAME.matcher(name).matches()) return null;
        File f = new File(new File(dir, date), name);
        if (!f.isFile() || f.length() > 4_000_000) return null;
        byte[] data = new byte[(int) f.length()];
        try (FileInputStream in = new FileInputStream(f)) {
            int off = 0;
            while (off < data.length) {
                int n = in.read(data, off, data.length - off);
                if (n < 0) return null;
                off += n;
            }
        } catch (IOException e) {
            return null;
        }
        return data;
    }
}
