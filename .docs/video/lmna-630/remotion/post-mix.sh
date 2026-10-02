#!/bin/zsh
# Post-mix for a rendered cut: music bed ducked under the voice, then two-pass
# loudness to -14 LUFS / -1 dBTP (the ship gate; v4 went out at -22.5 LUFS).
# LRA target 20: branded intro/outro are near-silent and push measured LRA to ~15; a lower target flips loudnorm into dynamic mode, which let true peaks reach +1.6 dBTP (2026-09-24).
# AAC at 320k: ffmpeg native AAC at 192k overshot sharp clicks by 8 dB (limited -3.6 dBFS became +5.2), 2026-09-24.
#   ./post-mix.sh in.mp4 out.mp4 [bed.wav]
set -euo pipefail
IN=$1; OUT=$2; BED=${3:-public/sfx/bed-serene-view.wav}
# James, 2026-09-24: NO music by default. BED_VOL>0 (e.g. 0.08) brings a ducked bed back.
BV=${BED_VOL:-0}
D=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IN")
FADE=$(python3 -c "print(max(0, $D - 3))")
MIX="[0:a]asplit=2[v][key];[1:a]volume=$BV,atrim=0:$D,afade=t=in:d=2,afade=t=out:st=$FADE:d=3[bed];[bed][key]sidechaincompress=threshold=0.015:ratio=10:attack=15:release=450[duck];[v][duck]amix=inputs=2:normalize=0:duration=first"

if [ "$BV" = "0" ]; then MIX="[0:a]anull"; BEDIN=(); else BEDIN=(-stream_loop -1 -i "$BED"); fi
# pass 1: measure
M=$(ffmpeg -hide_banner -nostats -i "$IN" "${BEDIN[@]}" -filter_complex "$MIX,loudnorm=I=-14:TP=-1:LRA=20:print_format=json" -f null - 2>&1 | sed -n '/^{/,/^}/p')
g() { echo "$M" | python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }
# pass 2: apply with the measured values
ffmpeg -v error -y -i "$IN" "${BEDIN[@]}" -filter_complex \
  "$MIX,loudnorm=I=-14:TP=-1:LRA=20:measured_I=$(g input_i):measured_TP=$(g input_tp):measured_LRA=$(g input_lra):measured_thresh=$(g input_thresh):offset=$(g target_offset):linear=true,aresample=192000,alimiter=limit=0.66:level=false:attack=1:release=60,aresample=48000[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 320k -movflags +faststart "$OUT"
ffmpeg -hide_banner -nostats -i "$OUT" -af ebur128=peak=true -f null - 2>&1 | grep -E "^\s+(I:|LRA:|Peak:)" | tr -s ' '
