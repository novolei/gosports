#!/bin/bash
# Records one clip of the game with Godot's Movie Maker (MJPEG q0.92, fixed 60 fps, game audio included).
#   promo/rec.sh <name> <game-seconds> [WxH] -- <game args...>
# Output: promo_work/rec/<name>.avi (+ <name>.log with the game's own --log output).
# The project's window_*_override (1600x900) decides the movie size, so a temporary override.cfg (git-ignored) is written for the run
# and removed afterwards.  Always sequential (one override.cfg).  Music is muted by default (the promo gets its own soundtrack);
# pass --music=0.7 after -- to keep the game's.  The finished clip's size is verified (a wrong size is reported as FAILED).
cd "$(dirname "$0")/.."
NAME=$1; SECS=$2
shift 2
SIZE=1920x1080
if [[ "$1" =~ ^[0-9]+x[0-9]+$ ]]; then SIZE=$1; shift; fi
if [[ "$1" == "--" ]]; then shift; fi
W=${SIZE%x*}; H=${SIZE#*x}
G="/d/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe"
mkdir -p promo_work/rec
printf '[display]\n\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n\n[editor]\n\nmovie_writer/mjpeg_quality=0.92\nmovie_writer/disable_vsync=true\n' "$W" "$H" > override.cfg
FRAMES=$(( SECS * 60 ))
rm -f "promo_work/rec/$NAME.avi"
timeout $(( SECS * 3 + 240 )) "$G" --path . --write-movie "promo_work/rec/$NAME.avi" --fixed-fps 60 --quit-after $FRAMES -- \
  --nosave --music=0 --charstyle=0 --log "$@" > "promo_work/rec/$NAME.log" 2>&1
rm -f override.cfg
SZ=$(stat -c %s "promo_work/rec/$NAME.avi" 2>/dev/null || echo 0)
GOT=$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=s=x:p=0 "promo_work/rec/$NAME.avi" 2>/dev/null)
ERR=$(grep -cE "SCRIPT ERROR|Parse Error" "promo_work/rec/$NAME.log")
OK=ok; [[ "$GOT" != "$SIZE" ]] && OK="FAILED (wanted $SIZE)"
echo "rec $NAME: ${SECS}s  got $GOT  $(( SZ / 1048576 )) MB  script errors: $ERR  $OK"
