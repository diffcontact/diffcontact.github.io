#!/usr/bin/env bash
# Rebuild the page media from the paper PDF and the multimedia attachments.
#   usage: tools/make_media.sh <paper.pdf> <MultimediaAttachment dir>
# Figures: every "Fig. N." of the PDF, cropped above its caption at 4x (tools/extract_figures.py).
# Clips: segments of the attachments cut at frame numbers (30 fps), without the black title cards, muted, metadata
# stripped, each with a poster of its first frame. Attachments 3 and 4 show the methods one after another; they become one
# clip per method, with each segment padded by its last frame to a common length, so the three clips of a section switch
# pull or task together (the data-t times of the segment buttons in index.html).
# Teaser: a 17.5-s montage of Attachment 1 cut the same way: a push, the slip on low-friction ground (Fig. 8(c)'s
# snapshots are frames 2180, 2193, and 2204), debris, then trot and pace on the treadmill.
set -eu
PDF=$1; M=$2; P=$(cd "$(dirname "$0")/.." && pwd); V=$P/assets/videos
mkdir -p "$P/assets/figures" "$V"
python3 "$P/tools/extract_figures.py" "$PDF" "$P/assets/figures" 4

# clip <attachment> <name> <first:end[:frames]>...: frames first..end-1 of each segment in order, the last one repeated
# until the segment is <frames> long; every segment starts on a keyframe
clip() {
  local a=$1 name=$2 f="" kf="" s b e n t=0 k=0; shift 2
  for s in "$@"; do
    IFS=: read -r b e n <<< "$s"; n=${n:-$((e - b))}
    f="$f[0:v]trim=start_frame=$b:end_frame=$e,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop=$((n - e + b))[s$k];"
    kf="$kf${kf:+,}$(printf '%d.%03d' $((t / 30)) $((t % 30 * 1000 / 30)))"; t=$((t + n)); k=$((k + 1))
  done
  for ((s = 0; s < k; s++)); do f="$f[s$s]"; done
  ffmpeg -v error -y -i "$M/Multimedia_Attachment_$a.mp4" -filter_complex "${f}concat=n=$k:v=1:a=0[v]" -map "[v]" -an \
         -c:v libx264 -crf 26 -preset slow -g 150 -force_key_frames "$kf" -pix_fmt yuv420p -r 30 -map_metadata -1 \
         -movflags +faststart "$V/$name.mp4"
  ffmpeg -v error -y -i "$V/$name.mp4" -frames:v 1 -vf scale=1280:-2 -q:v 3 "$V/${name}_poster.jpg"
}
# Attachment 1, hardware: trot 585, pace 707, debris 851, push 1232, low-friction trot 1689, low-friction gait-free 2694
clip 1 hw_gaits 585:707 707:851 2694:3236
clip 1 hw_debris 851:1232
clip 1 hw_push 1232:1689
clip 1 hw_lowfriction 1689:2694
# Attachment 2, command tracking: BPTT with 1, 2, and 4 environments from 602, PPO with 8 to 128 environments from 1592
clip 2 ppo_bptt 602:1592
clip 2 ppo_ppo 1592:2792
# Attachment 3, pulls: forward, rightward, and backward, each run with No Relaxation, Signorini-Relaxed, and Proposed;
# the Proposed segments (first pull at 0.25x, then the whole 10-s rollout) set the lengths
clip 3 pull_norel 632:763:463 1404:1535:524 2308:2439:474
clip 3 pull_sig 763:911:463 1535:1754:524 2439:2590:474
clip 3 pull_proposed 911:1374 1754:2278 2590:3064
# Attachment 4, CITO: yaw rotation, translation, and pitch rotation, with the methods in the same order
clip 4 cito_norel 632:710:102 920:1028:132 1298:1418:323
clip 4 cito_sig 710:788:102 1028:1136:132 1418:1718:323
clip 4 cito_proposed 788:890 1136:1268 1718:2041
# Teaser: push, low-friction slip, debris, trot, pace
clip 1 teaser 1244:1340 2118:2268 1107:1207 600:690 735:825
echo "media rebuilt in $P/assets"
