#!/usr/bin/env bash
# Phone perf probe (debug APK): writes a settings.cfg for the given config, restarts the game, taps through the
# menu into a match and prints the averaged [perf] values (fps / GPU ms / draws) the debug build logs every 5 s.
#   tools/phone_perf.sh <adb serial> <label> [quality] [render_scale] [shadow_size] [dbg flags, comma separated]
# Only touches the game's own package (force-stop + its settings file). Screen taps assume a 2400x1080 landscape phone.
set -u
ADB="${ADB:-/h/GDP/mini-tanks/.tools/android-setup/sdk/platform-tools/adb.exe}"
S="$1"; LABEL="$2"; Q="${3:-1}"; RS="${4:-0.0}"; SH="${5:-0}"; DBG="${6:-}"
PKG=com.gosports.volleyball.dev
TMPF="$(mktemp)"
printf '[settings]\nquality=%s\nrender_scale=%s\nshadow_size=%s\ndbg="%s"\n' "$Q" "$RS" "$SH" "$DBG" > "$TMPF"
"$ADB" -s "$S" shell am force-stop $PKG
MSYS_NO_PATHCONV=1 "$ADB" -s "$S" push "$(cygpath -w "$TMPF")" /data/local/tmp/gosports_settings.cfg >/dev/null
MSYS_NO_PATHCONV=1 "$ADB" -s "$S" shell "run-as $PKG sh -c 'mkdir -p files && cp /data/local/tmp/gosports_settings.cfg files/settings.cfg'"
rm -f "$TMPF"
"$ADB" -s "$S" logcat -c
"$ADB" -s "$S" shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 11
"$ADB" -s "$S" shell input tap 305 322;  sleep 2.5      # start
"$ADB" -s "$S" shell input tap 1331 838; sleep 2.5      # select character
"$ADB" -s "$S" shell input tap 144 196;  sleep 2.5      # confirm character
"$ADB" -s "$S" shell input tap 1418 954; sleep 24       # start match
LINES="$("$ADB" -s "$S" logcat -d 2>&1 | grep -E "\[perf\]" | tail -3)"
printf '%-34s' "$LABEL"
echo "$LINES" | awk '{for(i=1;i<=NF;i++){split($i,a,"="); if(a[1]=="fps")f+=a[2]; if(a[1]=="render_gpu")g+=a[2]; if(a[1]=="render_cpu")c+=a[2]; if(a[1]=="draws")d+=a[2]} n++} END{printf "fps=%-3.0f gpu=%-5.1fms render_cpu=%-4.1fms draws=%.0f\n", f/n, g/n, c/n, d/n}'
