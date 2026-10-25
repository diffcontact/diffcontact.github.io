#!/usr/bin/env bash
# Rebuild the page media from the paper PDF and the multimedia attachments (what was run on 2026-10-25).
#   usage: tools/make_media.sh <paper.pdf> <MultimediaAttachment dir>
# Figures: every "Fig. N." of the PDF, cropped above its caption at 4x (tools/extract_figures.py).
# Videos: the four attachments remuxed without re-encoding (+faststart for streaming, metadata stripped), one poster
# frame each, and an 18-s muted teaser of six 3-s hardware segments (trot, pace, debris, push, low-friction trot,
# low-friction gait-free) from Attachment 1. Times are stream timestamps.
set -eu
PDF=$1; M=$2; P=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$P/assets/figures" "$P/assets/videos"
python3 "$P/tools/extract_figures.py" "$PDF" "$P/assets/figures" 4
for i in 1 2 3 4; do
  ffmpeg -v error -y -i "$M/Multimedia_Attachment_$i.mp4" -map 0 -c copy -map_metadata -1 -movflags +faststart \
         "$P/assets/videos/video$i.mp4"
done
poster() { ffmpeg -v error -y -ss "$2" -i "$M/Multimedia_Attachment_$1.mp4" -frames:v 1 -vf scale=1280:-2 -q:v 3 \
                  "$P/assets/videos/video$1_poster.jpg"; }
poster 1 66; poster 2 31; poster 3 31.5; poster 4 38.5
f=""; k=0
for t in 20.5 24.0 31.0 42.0 62.0 93.0; do
  f="$f[0:v]trim=start=$t:duration=3,setpts=PTS-STARTPTS,scale=1280:720[s$k];"; k=$((k + 1))
done
ffmpeg -v error -y -i "$M/Multimedia_Attachment_1.mp4" -filter_complex "${f}[s0][s1][s2][s3][s4][s5]concat=n=6:v=1:a=0[v]" \
       -map "[v]" -an -c:v libx264 -crf 25 -preset slow -pix_fmt yuv420p -r 30 -map_metadata -1 -movflags +faststart \
       "$P/assets/videos/teaser.mp4"
ffmpeg -v error -y -ss 7.5 -i "$P/assets/videos/teaser.mp4" -frames:v 1 -q:v 3 "$P/assets/videos/teaser_poster.jpg"
echo "media rebuilt in $P/assets"
