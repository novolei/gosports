#!/bin/bash
# promo/sheet.sh <clip> [fps=1] [cols=4] [rows=4] [start=0] [thumb-width=480]
#   -> promo_work/sheets/<clip>_<start>.jpg : a contact sheet of thumbnails with time stamps (to LOOK at footage without playing it)
cd "$(dirname "$0")/.."
F=$1; FPS=${2:-1}; C=${3:-4}; R=${4:-4}; S=${5:-0}; TW=${6:-480}
mkdir -p promo_work/sheets
B=$(basename "${F%.*}")
FONT="C\\:/Windows/Fonts/arial.ttf"
ffmpeg -v error -y -ss "$S" -i "$F" -vf "fps=$FPS,scale=$TW:-1,drawtext=fontfile='$FONT':text='%{pts\\:hms}':x=6:y=6:fontsize=18:fontcolor=white:box=1:boxcolor=black@0.5,tile=${C}x${R}" -frames:v 1 -q:v 3 "promo_work/sheets/${B}_${S}.jpg"
echo "promo_work/sheets/${B}_${S}.jpg"
