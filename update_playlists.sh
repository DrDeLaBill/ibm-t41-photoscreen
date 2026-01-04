#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# load env from /etc/photoscreen.env if available otherwise from local .env
if [ -f /etc/photoscreen.env ]; then
  . /etc/photoscreen.env
elif [ -f "$SCRIPT_DIR/.env" ]; then
  . "$SCRIPT_DIR/.env"
else
  echo "No .env found"
  exit 1
fi

# ensure dirs
mkdir -p "$RAW_DIR" "$LOG_DIR"
chown -R "$RUN_USER":"$RUN_USER" "$BASE_DIR"

DATE=$(date +%F)
LOGFILE="$LOG_DIR/yt-dlp-$DATE.log"
YTDLP_ARCHIVE="${YTDLP_ARCHIVE:-$BASE_DIR/.archive.txt}"

# split PLAYLIST_URLS by |
IFS='|' read -r -a URLS <<< "$PLAYLIST_URLS"

# iterate
for url in "${URLS[@]}"; do
  # basic trim
  url="$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ -z "$url" ]; then
    continue
  fi

  echo "=== $(date) Starting download for $url" | tee -a "$LOGFILE"

  # download into RAW_DIR; let yt-dlp create folder by playlist title
  # output: RAW_DIR/%(playlist_title)s/%(upload_date)s - %(title)s.%(ext)s
  yt-dlp \
    --proxy "${PROXY:-}" \
    --cookies "${COOKIES_PATH:-}" \
    --add-header "Accept-Language: en-US,en;q=0.9" \
    --impersonate chrome-107 \
    --sleep-requests 10 \
    --sleep-interval 15 \
    --max-sleep-interval 30 \
    --concurrent-fragments 10 \
    --download-archive "$YTDLP_ARCHIVE" \
    -f "bestvideo[height<=${SCREEN_HEIGHT}]+bestaudio/best[height<=${SCREEN_HEIGHT}]" \
    -o "$RAW_DIR/%(playlist_title)s/%(upload_date)s - %(title)s.%(ext)s" \
    "$url" >> "$LOGFILE" 2>&1 || echo "yt-dlp returned non-zero for $url (continuing), check $LOGFILE" | tee -a "$LOGFILE"

  echo "=== $(date) Finished download attempt for $url" | tee -a "$LOGFILE"
done

# After download, transcode newly downloaded files per playlist into CONVERTED folders
# For each playlist folder in RAW_DIR:
for playlist_dir in "$RAW_DIR"/*; do
  [ -d "$playlist_dir" ] || continue
  playlist_name="$(basename "$playlist_dir")"
  target_dir="$CONVERTED_BASE/${playlist_name}_$SCREEN_HEIGHT"
  mkdir -p "$target_dir"
  echo "Processing playlist '$playlist_name' -> $target_dir" | tee -a "$LOGFILE"

  # find video files (common extensions)
  shopt -s nullglob
  for src in "$playlist_dir"/*.{mp4,mkv,webm,m4v,flv,avi}; do
    [ -e "$src" ] || continue
    filename="$(basename "$src")"
    dest="$target_dir/${filename%.*}.mp4"
    # if destination exists, skip
    if [ -f "$dest" ]; then
      echo "Skipping already converted $dest" >> "$LOGFILE"
      continue
    fi

    echo "Transcoding $src -> $dest" | tee -a "$LOGFILE"
    # transcode: scale height to SCREEN_HEIGHT, keep aspect (-2), force fps TARGET_FPS, audio -> mp3
    ffmpeg \
      -i "$src" \
      -vf " \
        scale=-2:${SCREEN_HEIGHT}, \
        eq=contrast=0.9:brightness=0.02:saturation=0.6, \
        hue=s=0, \
        noise=alls=12:allf=t, \
        tblend=all_mode=average, \
        fps=${TARGET_FPS} \
      " \
      -pix_fmt yuv420p \
      -profile:v baseline \
      -level 3.0 \
      -x264-params ref=1:bframes=0:cabac=0 \
      -preset veryfast \
      -crf 23 \
      -c:a libmp3lame -ar 44100 -ac 2 -b:a 128k \
      -y -hide_banner -loglevel error \
      -c:v libx264 \
      "$dest" >> "$LOGFILE" 2>&1 || echo "ffmpeg failed for $src (see $LOGFILE)" | tee -a "$LOGFILE"
  done
  shopt -u nullglob
done

echo "Update completed at $(date)" | tee -a "$LOGFILE"
