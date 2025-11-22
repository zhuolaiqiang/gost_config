#!/usr/bin/env bash
set -e

CONFIG_PATH=${1:-outline_config.yml}
METRICS_ADDR=${METRICS_ADDR:-127.0.0.1:9091}
REPLAY_HISTORY=${REPLAY_HISTORY:-10000}
SS_PORT=${SS_PORT:-9000}

if [ ! -f "$CONFIG_PATH" ]; then
  echo "Config file not found: $CONFIG_PATH" >&2
  exit 1
fi

ABS_CONFIG=$(realpath "$CONFIG_PATH" 2>/dev/null || readlink -f "$CONFIG_PATH")
CONFIG_DIR="/etc/outline"
LOG_DIR="/var/log/outline"

sudo mkdir -p "$CONFIG_DIR" "$LOG_DIR"
sudo cp "$ABS_CONFIG" "$CONFIG_DIR/config.yml"
sudo chown root:root "$CONFIG_DIR/config.yml"
sudo chmod 0644 "$CONFIG_DIR/config.yml"
sudo sed -i.bak -E "s/^(\s*port:\s*).*/\1${SS_PORT}/" "$CONFIG_DIR/config.yml" || true
sudo touch "$LOG_DIR/outline-ss-server.log"
sudo chmod 0644 "$LOG_DIR/outline-ss-server.log"

install_outline_from_source() {
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  if ! command -v git >/dev/null 2>&1; then
    if command -v apt >/dev/null 2>&1; then sudo apt update -y || true; sudo apt install -y git; elif command -v apt-get >/dev/null 2>&1; then sudo apt-get update -y || true; sudo apt-get install -y git; elif command -v yum >/dev/null 2>&1; then sudo yum install -y git; elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y git; fi
  fi
  if ! command -v go >/dev/null 2>&1; then
    echo "Go toolchain is required. Please install Go (>=1.20) and retry." >&2
    exit 1
  fi
  urls=("https://github.com/Jigsaw-Code/outline-ss-server.git")
  if [ -n "$GITHUB_PROXY" ]; then urls+=("$GITHUB_PROXY/https://github.com/Jigsaw-Code/outline-ss-server.git"); fi
  urls+=("https://ghproxy.com/https://github.com/Jigsaw-Code/outline-ss-server.git")
  urls+=("https://gitclone.com/github.com/Jigsaw-Code/outline-ss-server.git")
  srcdir="$tmpdir/src"
  mkdir -p "$srcdir"
  success=""
  for u in "${urls[@]}"; do
    git clone --depth 1 "$u" "$srcdir/outline-ss-server" && success=1 && break
  done
  if [ -z "$success" ]; then echo "Failed to clone outline-ss-server source." >&2; exit 1; fi
  cd "$srcdir/outline-ss-server/cmd/outline-ss-server"
  go build -o outline-ss-server
  sudo install -m 0755 outline-ss-server /usr/local/bin/outline-ss-server
}

if ! command -v outline-ss-server >/dev/null 2>&1; then
  install_outline_from_source
fi

if ! command -v outline-ss-server >/dev/null 2>&1; then
  echo "Failed to install outline-ss-server." >&2
  exit 1
fi

SERVICE_FILE="/etc/systemd/system/outline-ss-server.service"
sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Outline Shadowsocks Server
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/bin/sh -lc '/usr/local/bin/outline-ss-server -config $CONFIG_DIR/config.yml -metrics $METRICS_ADDR -replay_history=$REPLAY_HISTORY >> $LOG_DIR/outline-ss-server.log 2>&1'
Restart=always
RestartSec=3
LimitNOFILE=1048576
TasksMax=infinity
WorkingDirectory=$CONFIG_DIR

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now outline-ss-server
sudo systemctl restart outline-ss-server || true
sudo systemctl status outline-ss-server --no-pager -n 0 || true

echo "outline-ss-server deployed. Config: $CONFIG_DIR/config.yml, Metrics: $METRICS_ADDR, Log: $LOG_DIR/outline-ss-server.log"
