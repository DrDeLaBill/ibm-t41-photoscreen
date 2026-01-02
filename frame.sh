#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# load env
if [ -f /etc/photoscreen.env ]; then
  . /etc/photoscreen.env
elif [ -f "$SCRIPT_DIR/.env" ]; then
  . "$SCRIPT_DIR/.env"
else
  echo "No /etc/photoscreen.env or local .env found"
  exit 1
fi

# Prepare console
# Switch to tty1, clear it and disable cursor / blank
TERM_TTY="/dev/tty1"
# Try to switch to tty1 if running from systemd (optional)
if [ -e "$TERM_TTY" ]; then
  /usr/bin/chvt 1 || true
  /bin/kill -SIGSTOP $$ || true 2>/dev/null || true
fi

# Hide cursor and disable blanking
setterm -cursor off >/dev/tty1 2>/dev/null || true
setterm -blank 0 >/dev/tty1 2>/dev/null || true

# Build playlist (temporary file)
PLAYLIST_TMP="/tmp/photo_playlist.txt"
rm -f "$PLAYLIST_TMP"
touch "$PLAYLIST_TMP"
chown "$RUN_USER":"$RUN_USER" "$PLAYLIST_TMP"

# Find all converted folders with suffix _<height>
shopt -s nullglob
for d in "$CONVERTED_BASE"/*_"$SCREEN_HEIGHT"; do
  [ -d "$d" ] || continue
  # append all mp4 files; shuffle later
  find "$d" -maxdepth 1 -type f -iname '*.mp4' -print >> "$PLAYLIST_TMP"
done
shopt -u nullglob

# If empty, exit with message
if [ ! -s "$PLAYLIST_TMP" ]; then
  echo "No media files found in ${CONVERTED_BASE}/*_${SCREEN_HEIGHT}. Place videos there or run update_playlists."
  exit 1
fi

# Shuffle playlist
SHUFFLED="/tmp/photo_playlist_shuf.txt"
shuf "$PLAYLIST_TMP" > "$SHUFFLED" || cp "$PLAYLIST_TMP" "$SHUFFLED"

# Run looped playback with mplayer
# We'll run as RUN_USER (use su -c)
PLAYER_CMD="mplayer -vo fbdev2 -ao alsa -fs -loop 0 -really-quiet -playlist $SHUFFLED"
echo "Starting player: $PLAYER_CMD"

# Run in an infinite restart loop — systemd also restarts on failure, but add robustness
while true; do
  # run as specific user
  if [ "$(id -un)" = "$RUN_USER" ]; then
    eval "$PLAYER_CMD"
    STATUS=$?
  else
    su - "$RUN_USER" -c "$PLAYER_CMD"
    STATUS=$?
  fi

  echo "Player exited with status $STATUS at $(date). Restarting in 5s..." >> "${LOG_DIR:-/tmp}/photoscreen.log" 2>&1
  sleep 5
done
