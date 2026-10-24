package com.lookpeach.tvagent;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

/**
 * adb only (the receiver requires WRITE_SECURE_SETTINGS, which the shell holds):
 *   am broadcast -a com.lookpeach.tvagent.GET -n com.lookpeach.tvagent/.ConfigReceiver
 *   am broadcast -a com.lookpeach.tvagent.SET -n com.lookpeach.tvagent/.ConfigReceiver --es token X --es unlock_code UUDDLR
 * Both answer with the current settings as JSON in the broadcast result data.
 */
public class ConfigReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        Prefs.ensure(context);
        SharedPreferences p = Prefs.get(context);
        if ("com.lookpeach.tvagent.SET".equals(intent.getAction())) {
            SharedPreferences.Editor e = p.edit();
            String token = intent.getStringExtra("token");
            if (token != null && token.length() >= 16) e.putString(Prefs.TOKEN, token);
            String code = intent.getStringExtra("unlock_code");
            if (Prefs.validCode(code)) e.putString(Prefs.UNLOCK_CODE, code);
            e.commit();
        }
        setResultCode(1);
        setResultData("{\"token\":" + Json.quote(p.getString(Prefs.TOKEN, ""))
                + ",\"unlockCode\":" + Json.quote(p.getString(Prefs.UNLOCK_CODE, ""))
                + ",\"port\":" + AgentServer.PORT + "}");
    }
}
