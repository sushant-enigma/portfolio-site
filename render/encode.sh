#!/usr/bin/env bash
# Turns the lossless masters from render.py into the files the site serves, in site/media/:
#   <view>.av1.webm   AV1, smaller; played by Chrome, Edge, Firefox and newer Apple devices
#   <view>.h264.mp4   H.264, played everywhere else (older iPhones and Macs)
#   <view>.jpg        the first frame, shown until the video plays (and instead of it, for reduced motion)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p ../site/media

for view in landscape portrait; do
  src="out/$view.mkv"
  [ -f "$src" ] || { echo "missing $src: run render.py first" >&2; exit 1; }
  ffmpeg -y -loglevel error -i "$src" -c:v libsvtav1 -preset 4 -crf 36 -pix_fmt yuv420p -g 90 \
    -svtav1-params tune=0 -an "../site/media/$view.av1.webm"
  level=4.0; [ "$view" = portrait ] && level=5.0   # 1080x2340 is too many pixels for level 4.x
  ffmpeg -y -loglevel error -i "$src" -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -profile:v high \
    -level:v "$level" -g 90 -movflags +faststart -an "../site/media/$view.h264.mp4"
  ffmpeg -y -loglevel error -i "out/$view-poster.png" -q:v 3 "../site/media/$view.jpg"
done
ls -l ../site/media | awk 'NR > 1 { printf "%-24s %6.2f MB\n", $9, $5 / 1048576 }'
