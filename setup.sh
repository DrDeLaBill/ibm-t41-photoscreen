#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo ./setup.sh"
  exit 1
fi

SERVICE_DIR="/etc/systemd/system"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env not found in $SCRIPT_DIR. Please create it and edit variables."
  exit 1
fi

# Загрузим .env, но в безопасном режиме:
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

# Проверка, что мы в репозитории
for f in frame.sh update_playlists.sh requirements.txt; do
  if [ ! -f "$REPO_DIR/$f" ]; then
    echo "Missing $f. Run setup.sh from repo root."
    exit 1
  fi
done

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

echo "[1/7]Setup: creating directories..."
mkdir -p "$BASE_DIR" "$RAW_DIR" "$LOG_DIR"
chown -R "$RUN_USER":"$RUN_USER" "$BASE_DIR"

echo "[2/7] Installing system packages..."
apt update
apt install -y \
  python3 python3-pip \
  ffmpeg mplayer \
  curl ca-certificates \
  ntfs-3g

echo "[3/7] Installing Python dependencies..."
pip3 install --upgrade pip
pip3 install -r "$REPO_DIR/requirements.txt"

echo "[4/7] Making scripts executable..."
chmod +x "$REPO_DIR/frame.sh"
chmod +x "$REPO_DIR/update_playlists.sh"

echo "[5/7] Creating symlinks in /usr/local/bin..."
ln -sf "$REPO_DIR/frame.sh" /usr/local/bin/frame.sh
ln -sf "$REPO_DIR/update_playlists.sh" /usr/local/bin/update_playlists.sh

echo "[6/7] Installing systemd services..."
cat > "$SERVICE_DIR/update-playlists.service" <<EOF
[Unit]
Description=Update playlists (yt-dlp + ffmpeg)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=$ENV_FILE
User=$RUN_USER
ExecStart=/usr/local/bin/update_playlists.sh
WorkingDirectory=/home/$RUN_USER
EOF
cat > "$SERVICE_DIR/update-playlists.timer" <<EOF
[Unit]
Description=Daily update playlists timer

[Timer]
OnCalendar=*-*-* 03:15:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
cat > "$SERVICE_DIR/photoscreen.service" <<EOF
[Unit]
Description=Photo screen player
After=multi-user.target

[Service]
Type=simple
EnvironmentFile=$ENV_FILE
User=$RUN_USER
ExecStart=/usr/local/bin/frame.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload

echo "[7/7] Enabling services..."
systemctl enable photoscreen.service
systemctl enable update-playlists.timer

echo "Setup completed successfully."
echo "Reboot recommended."
