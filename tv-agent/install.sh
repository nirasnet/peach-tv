#!/usr/bin/env bash
# Build the Peach Remote agent, install it on the TV over ADB, switch its service on and print the
# pairing details for the iPhone app. Needs ADB debugging on the TV (only for this install).
# Usage: TV_HOST=192.168.1.50 ./install.sh
set -euo pipefail
cd "$(dirname "$0")"
: "${TV_HOST:?set TV_HOST to the TV IP}"
# Uses the ADB helpers (tools/tv.py, tools/b64push.py) from a CleanYourTV checkout next to this repo.
CLEANTV="${CLEANTV:-$(cd ../../cleanyourtv && pwd)}"
PY="$CLEANTV/tools/venv/bin/python"
TV="$PY -I $CLEANTV/tools/tv.py"
export TV_HOST
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"

./gradlew -q assembleRelease
"$PY" -I "$CLEANTV/tools/b64push.py" app/build/outputs/apk/release/app-release.apk /data/local/tmp/peachagent.apk
OUT=$($TV 'pm install -r /data/local/tmp/peachagent.apk; rm -f /data/local/tmp/peachagent.apk')
echo "$OUT"
case "$OUT" in *Success*) ;; *) echo "ERROR: install failed" >&2; exit 1 ;; esac

SVC=com.lookpeach.tvagent/.AgentService
# TCL's TclAppBoot blocks accessibility services at boot without APP_AUTO_START; write it out, app-ops save lazily.
$TV 'appops set com.lookpeach.tvagent APP_AUTO_START allow 2>/dev/null; appops write-settings'
# Append to the enabled services (keeping the launcher's), or re-bind it after an update.
$TV "s=\$(settings get secure enabled_accessibility_services); case \"\$s\" in *$SVC*) settings put secure enabled_accessibility_services \"\$(echo \$s | sed 's#:*$SVC##')\"; sleep 1; settings put secure enabled_accessibility_services \"\$s\" ;; null|'') settings put secure enabled_accessibility_services $SVC ;; *) settings put secure enabled_accessibility_services \"\$s:$SVC\" ;; esac; settings put secure accessibility_enabled 1"
sleep 3
$TV 'settings get secure enabled_accessibility_services'
$TV 'am broadcast -a com.lookpeach.tvagent.GET -n com.lookpeach.tvagent/.ConfigReceiver' | sed -n 's/.*data="\(.*\)"/\1/p' > .pairing.json
cat .pairing.json
echo "Pairing saved to tv-agent/.pairing.json (keep it private)."
