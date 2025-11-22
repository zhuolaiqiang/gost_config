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

ABS_CONFIG=$(realpath "$CONFIG_PATH" 2>/dev/null || readlink -f "$CONFIG_PATH")
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

SYSCTL_FILE="/etc/sysctl.d/99-gost-performance.conf"
sudo bash -c "cat > $SYSCTL_FILE" <<EOF
net.core.somaxconn=65535
net.core.netdev_max_backlog=250000
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=fq
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
EOF

# Always install v3; no v2 fallback

install_v3() {
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  if ! command -v curl >/dev/null 2>&1; then
    if command -v apt >/dev/null 2>&1; then
      sudo apt update -y || true
      sudo apt install -y curl
    elif command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -y || true
      sudo apt-get install -y curl
    else
      echo "Package manager not found (apt/apt-get). Please install curl manually." >&2
      exit 1
    fi
  fi
  if ! command -v tar >/dev/null 2>&1; then
    if command -v apt >/dev/null 2>&1; then
      sudo apt update -y || true
      sudo apt install -y tar
    elif command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -y || true
      sudo apt-get install -y tar
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y tar
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y tar
    fi
  fi
  os="linux"
  arch="amd64"
  case "$(uname -m)" in
    x86_64) arch="amd64";;
    aarch64|arm64) arch="arm64";;
    armv7l) arch="armv7";;
    *) arch="$(uname -m)";;
  esac
  api_url="https://api.github.com/repos/go-gost/gost/releases/latest"
  dl_url=$(curl -fsSL "$api_url" | grep -E 'browser_download_url' | grep -E "$os.*$arch.*(tar\\.gz|\\.tar\\.gz)" | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')
  if [ -z "$dl_url" ]; then
    echo "Failed to resolve latest release asset for linux amd64." >&2
    exit 1
  fi
  pkg="$tmpdir/gost.tar.gz"
  mirrors=()
  mirrors+=("$dl_url")
  if [ -n "$GITHUB_PROXY" ]; then
    mirrors+=("$GITHUB_PROXY/$dl_url")
  fi
  mirrors+=("$(echo "$dl_url" | sed 's#https://github.com/#https://download.fastgit.org/#')")
  mirrors+=("$(echo "$dl_url" | sed 's#https://github.com/#https://mirror.ghproxy.com/#')")
  if ! command -v aria2c >/dev/null 2>&1; then
    if command -v apt >/dev/null 2>&1; then
      sudo apt update -y || true
      sudo apt install -y aria2 || true
    elif command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -y || true
      sudo apt-get install -y aria2 || true
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y aria2 || true
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y aria2 || true
    fi
  fi
  success=""
  if command -v aria2c >/dev/null 2>&1; then
    for u in "${mirrors[@]}"; do
      aria2c -x 16 -s 16 -k 1M -o "$pkg" "$u" && success=1 && break
    done
  else
    for u in "${mirrors[@]}"; do
      curl -fSL --connect-timeout 10 --retry 5 --retry-delay 2 --retry-connrefused --speed-time 15 --speed-limit 1024 -o "$pkg" "$u" && success=1 && break
      if command -v wget >/dev/null 2>&1; then
        wget -O "$pkg" "$u" && success=1 && break
      fi
    done
  fi
  if [ -z "$success" ]; then
    echo "Download failed from all mirrors." >&2
    exit 1
  fi
  tar -xzf "$pkg" -C "$tmpdir"
  bin_path=$(find "$tmpdir" -type f -name gost -perm -111 | head -n1)
  if [ -z "$bin_path" ]; then
    bin_path=$(find "$tmpdir" -type f -name gost | head -n1)
    chmod +x "$bin_path" 2>/dev/null || true
  fi
  if [ -z "$bin_path" ]; then
    echo "gost binary not found in package." >&2
    exit 1
  fi
  sudo install -m 0755 "$bin_path" /usr/local/bin/gost
}

if ! command -v gost >/dev/null 2>&1; then
  install_v3
fi

if ! command -v gost >/dev/null 2>&1; then
  echo "Failed to install GOST v3. Aborting." >&2
  exit 1
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
LimitNOFILE=1048576
TasksMax=infinity
ExecStartPre=/sbin/sysctl -p $SYSCTL_FILE
WorkingDirectory=$CONFIG_DIR

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now gost
sudo systemctl restart gost || true
sudo systemctl status gost --no-pager -n 0 || true
