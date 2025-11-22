#!/usr/bin/env bash
set -e

CONFIG_PATH=${1:-gost_config}
if [ ! -f "$CONFIG_PATH" ] && [ -f "${CONFIG_PATH}.json" ]; then
  CONFIG_PATH="${CONFIG_PATH}.json"
fi

if [ ! -f "$CONFIG_PATH" ]; then
  echo "Config file not found: $CONFIG_PATH" >&2
  exit 1
fi

ABS_CONFIG=$(realpath "$CONFIG_PATH")
CONFIG_NAME=$(basename "$ABS_CONFIG")
CONFIG_DIR="/etc/gost"

sudo mkdir -p "$CONFIG_DIR"
sudo cp "$ABS_CONFIG" "$CONFIG_DIR/$CONFIG_NAME"
sudo chown root:root "$CONFIG_DIR/$CONFIG_NAME"
sudo chmod 0644 "$CONFIG_DIR/$CONFIG_NAME"

LOG_DIR="/var/log/gost"
sudo mkdir -p "$LOG_DIR"
sudo touch "$LOG_DIR/gost.log"
sudo chown root:root "$LOG_DIR/gost.log"
sudo chmod 0644 "$LOG_DIR/gost.log"

if grep -q '"services"' "$ABS_CONFIG"; then
  TARGET_VERSION=v3
else
  TARGET_VERSION=v2
fi

install_v3() {
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  curl -fsSL https://raw.githubusercontent.com/go-gost/gost/master/install.sh -o "$tmpdir/install.sh"
  sudo bash "$tmpdir/install.sh" -b /usr/local/bin
}

install_v2() {
  if ! command -v snap >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y snapd
  fi
  sudo snap install gost || true
}

if ! command -v gost >/dev/null 2>&1; then
  if [ "$TARGET_VERSION" = "v3" ]; then
    install_v3
  else
    install_v2
  fi
fi

GOST_BIN=$(command -v gost)

SERVICE_FILE="/etc/systemd/system/gost.service"
sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=GO Simple Tunnel (gost)
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=$GOST_BIN -C $CONFIG_DIR/$CONFIG_NAME
Restart=always
RestartSec=3
LimitNOFILE=65535
WorkingDirectory=$CONFIG_DIR

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now gost
sudo systemctl restart gost || true
sudo systemctl status gost --no-pager -n 0 || true