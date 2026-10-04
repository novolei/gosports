#!/bin/bash
# usage: coll_count.sh label extra-flags...  -> prints level-3 collisions per run
label=$1; shift
G="/d/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe"
cd /g/NewGDP/go-sports
for i in 1 2 3 4; do
  out=$(timeout 300 "$G" --path . -- --screen=match --autoplay --points=11 --quit_after=170 --log --timescale=2 "$@" 2>&1)
  k3=$(echo "$out" | grep -c "level=3")
  k2=$(echo "$out" | grep -c "level=2")
  st=$(echo "$out" | grep -o 'knockdowns": \[[0-9, ]*\]' | tail -1)
  echo "$label run$i level3=$k3 level2=$k2 $st"
done
