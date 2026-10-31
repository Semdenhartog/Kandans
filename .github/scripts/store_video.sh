#!/usr/bin/env bash
# Promovideo voor de Play Store (30 s, 1080x1920): de zes winkelplaatjes met een langzame zoom,
# elk 5 seconden, met een korte overgang via zwart. Gebruik: store_video.sh <map met plaatjes> <uit.mp4>
set -euo pipefail
src="$1"; out="$2"
work=$(mktemp -d)
i=0
for n in 1_beste_moment 2_run_opnemen 3_je_run 4_na_je_run 5_routes 6_coach; do
  [ -f "$src/$n.png" ] || continue
  i=$((i+1))
  ffmpeg -v error -y -i "$src/$n.png" \
    -vf "scale=2160:3840,zoompan=z='1+0.05*on/150':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=150:s=1080x1920:fps=30,fade=t=in:st=0:d=0.4,fade=t=out:st=4.6:d=0.4,format=yuv420p" \
    -frames:v 150 -c:v libx264 -preset veryfast -crf 20 -r 30 "$work/tmp_$i.mp4"
  mv "$work/tmp_$i.mp4" "$work/s$i.mp4"
  echo "file '$work/s$i.mp4'" >> "$work/list.txt"
done
ffmpeg -v error -y -f concat -safe 0 -i "$work/list.txt" -c copy "$out"
echo "Promovideo: $out ($i scènes)"
