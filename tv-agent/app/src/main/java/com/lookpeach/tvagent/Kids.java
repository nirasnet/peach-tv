package com.lookpeach.tvagent;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.Uri;

import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;

/**
 * Kids mode: only the allowed apps (AIS PLAY by default) may run; the Peach home shows only their tiles
 * (it reads {@link KidsProvider}). On by default. With "auto" on, parent mode lasts until the TV is turned off.
 */
final class Kids {
    static final String AIS_PLAY = "com.ais.mimo.aisplay.tv";
    static final Uri URI = Uri.parse("content://com.lookpeach.tvagent.kids/state");
    private static final String ON = "kids_on", APPS = "kids_apps", AUTO = "kids_auto";

    private Kids() { }

    static boolean on(Context c) {
        return Prefs.get(c).getBoolean(ON, true);
    }

    static boolean auto(Context c) {
        return Prefs.get(c).getBoolean(AUTO, true);
    }

    static Set<String> apps(Context c) {
        String raw = Prefs.get(c).getString(APPS, AIS_PLAY);
        if (raw.isEmpty()) return Collections.emptySet();
        return new LinkedHashSet<>(Arrays.asList(raw.split(",")));
    }

    /** Null leaves that setting as it is. Tells the home screen when anything changed. */
    static void set(Context c, Boolean on, Set<String> apps, Boolean auto) {
        SharedPreferences.Editor e = Prefs.get(c).edit();
        if (on != null) e.putBoolean(ON, on);
        if (auto != null) e.putBoolean(AUTO, auto);
        if (apps != null) {
            StringBuilder b = new StringBuilder();
            for (String pkg : apps) {
                if (pkg == null || !pkg.matches("[A-Za-z0-9_.]{1,200}")) continue;
                if (b.length() > 0) b.append(',');
                b.append(pkg);
            }
            e.putString(APPS, b.toString());
        }
        e.commit();
        c.getContentResolver().notifyChange(URI, null);
    }
}
