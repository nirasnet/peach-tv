package com.lookpeach.tvagent;

import android.content.SharedPreferences;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * How the lock screen looks and what it says: a theme (background, big emoji, decorations, colours)
 * and the wording for each kind of lock and for the time-running-out warning. Texts may use
 * {from} {to} (today's TV hours), {limit} (today's screen time) and {min} (minutes left).
 */
final class Look {
    static final class Theme {
        final String id;
        final int[] bg;
        final String emoji;
        final String sprinkle;
        final int text;
        final int accent;

        Theme(String id, int[] bg, String emoji, String sprinkle, int text, int accent) {
            this.id = id;
            this.bg = bg;
            this.emoji = emoji;
            this.sprinkle = sprinkle;
            this.text = text;
            this.accent = accent;
        }
    }

    static final Map<String, Theme> THEMES = new LinkedHashMap<>();

    private static void add(Theme t) { THEMES.put(t.id, t); }

    static {
        add(new Theme("peach", new int[] {0xFF2A1210, 0xFF140806, 0xFF060303}, "🍑", "🍑", 0xFFFFF1E6, 0xFFFFB38A));
        add(new Theme("night", new int[] {0xFF101845, 0xFF070B24, 0xFF02030A}, "🌙", "✨", 0xFFEFF2FF, 0xFFB9C7FF));
        add(new Theme("ocean", new int[] {0xFF07405A, 0xFF042436, 0xFF010A10}, "🐳", "🫧", 0xFFE8FBFF, 0xFF7FE3F0));
        add(new Theme("forest", new int[] {0xFF143A1E, 0xFF09190D, 0xFF020703}, "🌳", "🍃", 0xFFEFFFEA, 0xFF9BE58F));
        add(new Theme("sakura", new int[] {0xFF4A1834, 0xFF240B1A, 0xFF0A0307}, "🌸", "🌸", 0xFFFFF0F6, 0xFFFFB3D1));
        add(new Theme("sunset", new int[] {0xFF5A250C, 0xFF2E1014, 0xFF0A0408}, "🌅", "☁️", 0xFFFFF4E6, 0xFFFFC27A));
        add(new Theme("space", new int[] {0xFF22104A, 0xFF0D0624, 0xFF030108}, "🚀", "⭐", 0xFFF3EDFF, 0xFFC9A7FF));
        add(new Theme("candy", new int[] {0xFF4A1F52, 0xFF231240, 0xFF0A0614}, "🍭", "🍬", 0xFFFFF0FB, 0xFFFF9AE6));
        add(new Theme("teddy", new int[] {0xFF44291A, 0xFF22140B, 0xFF0A0603}, "🧸", "🍯", 0xFFFFF5EA, 0xFFE8C39E));
        add(new Theme("dino", new int[] {0xFF24401A, 0xFF13230D, 0xFF050A03}, "🦖", "🌴", 0xFFF2FFE8, 0xFFC4F08A));
        add(new Theme("mono", new int[] {0xFF1E1E1E, 0xFF0D0D0D, 0xFF000000}, "🔒", "", 0xFFF2F2F2, 0xFFBDBDBD));
    }

    static final String KEY = "look";
    /** Lock kinds that each have their own style. */
    static final String[] KINDS = {"parent", "schedule", "limit"};

    /** Background, big picture and decorations of one kind of lock. */
    static final class Style {
        String theme = "peach";
        /** Empty = the theme's own emoji. */
        String emoji = "";
        boolean sprinkle = true;
        boolean animate = true;

        void read(JSONObject o) throws JSONException {
            if (o.has("theme")) {
                String t = o.getString("theme");
                if (!THEMES.containsKey(t)) throw new JSONException("unknown theme " + t);
                theme = t;
            }
            if (o.has("emoji")) emoji = text(o, "emoji", 8, true);
            if (o.has("sprinkle")) sprinkle = o.getBoolean("sprinkle");
            if (o.has("animate")) animate = o.getBoolean("animate");
        }

        Theme themeObj() {
            Theme t = THEMES.get(theme);
            return t == null ? THEMES.get("peach") : t;
        }

        String bigEmoji() { return emoji.isEmpty() ? themeObj().emoji : emoji; }

        /** Identifies what the lock window shows, so a change rebuilds it. */
        String key() { return theme + "|" + bigEmoji() + "|" + sprinkle + "|" + animate; }

        String fields() {
            return "\"theme\":" + Json.quote(theme) + ",\"emoji\":" + Json.quote(emoji)
                    + ",\"sprinkle\":" + sprinkle + ",\"animate\":" + animate;
        }
    }

    final Map<String, Style> styles = new LinkedHashMap<>();
    {
        for (String k : KINDS) styles.put(k, new Style());
    }
    String parentSub = "TV locked by Look Peach Family";
    String scheduleText = "ตอนนี้ไม่ใช่เวลาดูทีวีนะ 🌙";
    String limitText = "วันนี้ดูทีวีครบเวลาแล้วนะ ⏰";
    String warnText = "อีก {min} นาทีหมดเวลาดูทีวีนะ ⏰";

    static Look load(SharedPreferences p) {
        Look l = new Look();
        String saved = p.getString(KEY, "");
        if (!saved.isEmpty()) {
            try { l.read(new JSONObject(saved)); } catch (JSONException ignored) { }
        }
        return l;
    }

    Look copy() {
        Look l = new Look();
        try { l.read(new JSONObject(json())); } catch (JSONException ignored) { }
        return l;
    }

    void save(SharedPreferences p) { p.edit().putString(KEY, json()).commit(); }

    /** Applies the fields present; throws on bad values so the phone sees the error. */
    void read(JSONObject o) throws JSONException {
        // Top-level style fields set every kind at once (older apps and saved looks use them).
        for (Style s : styles.values()) s.read(o);
        JSONObject per = o.optJSONObject("styles");
        if (per != null) {
            for (String k : KINDS) {
                JSONObject one = per.optJSONObject(k);
                if (one != null) styles.get(k).read(one);
            }
        }
        if (o.has("parentSub")) parentSub = text(o, "parentSub", 60, true);
        if (o.has("scheduleText")) scheduleText = text(o, "scheduleText", 120, false);
        if (o.has("limitText")) limitText = text(o, "limitText", 120, false);
        if (o.has("warnText")) warnText = text(o, "warnText", 120, false);
    }

    private static String text(JSONObject o, String name, int max, boolean emptyOk) throws JSONException {
        String v = o.getString(name).trim();
        if (v.length() > max) throw new JSONException(name + " is longer than " + max + " characters");
        if (v.isEmpty() && !emptyOk) throw new JSONException(name + " is empty");
        return v;
    }

    /** The style of a lock kind; anything unknown (warn) uses the parent style. */
    Style style(String kind) {
        Style s = styles.get(kind);
        return s == null ? styles.get("parent") : s;
    }

    static String fill(String text, Map<String, String> values) {
        String out = text;
        for (Map.Entry<String, String> e : values.entrySet()) out = out.replace("{" + e.getKey() + "}", e.getValue());
        return out;
    }

    /** Thai wording for a number of minutes: "45 นาที", "1 ชั่วโมง", "1 ชั่วโมง 30 นาที". */
    static String thaiMinutes(int minutes) {
        int h = minutes / 60, m = minutes % 60;
        if (h == 0) return m + " นาที";
        return m == 0 ? h + " ชั่วโมง" : h + " ชั่วโมง " + m + " นาที";
    }

    String json() {
        StringBuilder per = new StringBuilder();
        for (Map.Entry<String, Style> e : styles.entrySet()) {
            if (per.length() > 0) per.append(',');
            per.append(Json.quote(e.getKey())).append(":{").append(e.getValue().fields()).append('}');
        }
        // Top-level style = the parent lock's, for older apps.
        return "{" + style("parent").fields() + ",\"styles\":{" + per + "}"
                + ",\"parentSub\":" + Json.quote(parentSub)
                + ",\"scheduleText\":" + Json.quote(scheduleText)
                + ",\"limitText\":" + Json.quote(limitText)
                + ",\"warnText\":" + Json.quote(warnText) + "}";
    }

    static String themesJson() {
        StringBuilder b = new StringBuilder("[");
        for (Theme t : THEMES.values()) {
            if (b.length() > 1) b.append(',');
            b.append(Json.quote(t.id));
        }
        return b.append(']').toString();
    }
}
