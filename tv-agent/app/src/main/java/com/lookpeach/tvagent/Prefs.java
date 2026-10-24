package com.lookpeach.tvagent;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Base64;

import java.security.SecureRandom;

/** Phone token, TV unlock code and the lock state, kept across reboots. */
final class Prefs {
    private static final String FILE = "agent";
    static final String TOKEN = "token";
    static final String UNLOCK_CODE = "unlock_code";
    static final String LOCKED = "locked";
    static final String LOCK_MESSAGE = "lock_message";

    private Prefs() { }

    static SharedPreferences get(Context c) {
        return c.getApplicationContext().getSharedPreferences(FILE, Context.MODE_PRIVATE);
    }

    /** Creates a random token and unlock code on first use. */
    static synchronized void ensure(Context c) {
        SharedPreferences p = get(c);
        SharedPreferences.Editor e = p.edit();
        SecureRandom rnd = new SecureRandom();
        if (p.getString(TOKEN, "").isEmpty()) {
            byte[] raw = new byte[24];
            rnd.nextBytes(raw);
            e.putString(TOKEN, Base64.encodeToString(raw, Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP));
        }
        if (!validCode(p.getString(UNLOCK_CODE, ""))) {
            String arrows = "UDLR";
            StringBuilder code = new StringBuilder();
            for (int i = 0; i < 6; i++) code.append(arrows.charAt(rnd.nextInt(4)));
            e.putString(UNLOCK_CODE, code.toString());
        }
        e.commit();
    }

    /** 4 to 12 arrows: U, D, L, R. */
    static boolean validCode(String code) {
        return code != null && code.matches("[UDLR]{4,12}");
    }
}
