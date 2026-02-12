#!/usr/bin/env bash
set -euo pipefail

# =========================
# mihomo install script (RHEL/OpenCloudOS, x86_64)
# Usage:
#   sudo SUB_URL="https://your-subscription-url" SECRET="change_me" INSTALL_UI=1 ./install_mihomo.sh
#
# Optional env:
#   SUB_URL        Clash 兼容订阅链接（建议必须填）
#   SECRET         API 密钥（默认随机生成）
#   MIXED_PORT     代理端口（默认 7890）
#   CTRL_ADDR      控制端口监听地址（默认 127.0.0.1:9090）
#   INSTALL_UI     1=安装 metacubexd 静态面板到 /etc/mihomo/ui（默认 0）
#   FORCE_CONFIG   1=覆盖生成 /etc/mihomo/config.yaml（默认 0）
# =========================

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Please run as root (use sudo)."
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

install_deps() {
  if have_cmd dnf; then
    dnf -y install curl gzip jq ca-certificates >/dev/null
    # git 仅在安装 UI 时需要
    if [[ "${INSTALL_UI:-0}" == "1" ]]; then dnf -y install git >/dev/null; fi
  elif have_cmd yum; then
    yum -y install curl gzip jq ca-certificates >/dev/null
    if [[ "${INSTALL_UI:-0}" == "1" ]]; then yum -y install git >/dev/null; fi
  elif have_cmd apt-get; then
    apt-get update -y >/dev/null
    apt-get install -y curl gzip jq ca-certificates >/dev/null
    if [[ "${INSTALL_UI:-0}" == "1" ]]; then apt-get install -y git >/dev/null; fi
  else
    echo "No supported package manager found (dnf/yum/apt-get)."
    exit 1
  fi
}

detect_cpu_level() {
  local level="v1"
  # 优先用 glibc micro-arch level 判断（最靠谱）
  if [[ -x /lib64/ld-linux-x86-64.so.2 ]]; then
    if /lib64/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -q "x86-64-v3 (supported"; then
      level="v3"
    elif /lib64/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -q "x86-64-v2 (supported"; then
      level="v2"
    fi
  fi
  echo "$level"
}

download_mihomo() {
  local arch
  arch="$(uname -m)"
  if [[ "$arch" != "x86_64" ]]; then
    echo "This script currently targets x86_64. Detected: $arch"
    exit 1
  fi

  local level
  level="$(detect_cpu_level)"
  echo "[+] CPU level => $level"

  echo "[+] Fetching latest release info from GitHub API..."
  local json
  json="$(curl -fsSL --connect-timeout 10 --max-time 30 \
    https://api.github.com/repos/MetaCubeX/mihomo/releases/latest)"

  local url
  url="$(echo "$json" | jq -r '.assets[].browser_download_url' \
    | grep -E "mihomo-linux-amd64-${level}.*\.gz$" | head -n1 || true)"

  if [[ -z "$url" ]]; then
    echo "[-] Cannot find asset for mihomo-linux-amd64-${level}*.gz"
    echo "    Try checking releases manually: https://github.com/MetaCubeX/mihomo/releases"
    exit 1
  fi

  echo "[+] Downloading: $url"
  local tmpdir="/tmp/mihomo_install.$$"
  mkdir -p "$tmpdir"

  curl -L --fail --connect-timeout 10 --max-time 120 "$url" -o "$tmpdir/mihomo.gz"
  gzip -dc "$tmpdir/mihomo.gz" > "$tmpdir/mihomo"
  chmod +x "$tmpdir/mihomo"

  mv "$tmpdir/mihomo" /usr/local/bin/mihomo
  rm -rf "$tmpdir"

  echo "[+] mihomo installed to /usr/local/bin/mihomo"
  /usr/local/bin/mihomo -v || true
}

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    cp -a "$f" "${f}.bak_${ts}"
    echo "[i] Backup: $f -> ${f}.bak_${ts}"
  fi
}

write_config() {
  mkdir -p /etc/mihomo/proxy_providers

  local cfg="/etc/mihomo/config.yaml"
  if [[ -f "$cfg" && "${FORCE_CONFIG:-0}" != "1" ]]; then
    echo "[i] Config exists: $cfg (skip). Set FORCE_CONFIG=1 to overwrite."
    return
  fi

  backup_file "$cfg"

  local mixed_port="${MIXED_PORT:-7890}"
  local ctrl_addr="${CTRL_ADDR:-127.0.0.1:9090}"

  local secret="${SECRET:-}"
  if [[ -z "$secret" ]]; then
    # 生成 24 字符随机 secret
    secret="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true)"
  fi

  local sub_url="${SUB_URL:-}"
  if [[ -z "$sub_url" ]]; then
    sub_url="https://example.com/your-subscription-url"
    echo "[!] SUB_URL not provided. Writing placeholder URL into config."
  fi

  local ui_line=""
  if [[ "${INSTALL_UI:-0}" == "1" ]]; then
    ui_line=$'\nexternal-ui: /etc/mihomo/ui\n'
  fi

  cat >"$cfg" <<EOF
# mihomo basic config
mixed-port: ${mixed_port}
allow-lan: false
mode: rule
log-level: info

external-controller: ${ctrl_addr}
secret: "${secret}"${ui_line}
# ---- Geo resources (use JSDelivr-CF mirror to avoid GitHub timeout) ----
geodata-mode: true
geo-auto-update: true
geo-update-interval: 24
geox-url:
  geoip: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
  geosite: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
  mmdb: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"

# ---- Subscription (proxy provider) ----
proxy-providers:
  airport:
    type: http
    url: "${sub_url}"
    interval: 3600
    path: ./proxy_providers/airport.yaml
    health-check:
      enable: true
      url: https://www.gstatic.com/generate_204
      interval: 300
      timeout: 5000
      lazy: true
      expected-status: 204

# ---- Proxy groups ----
proxy-groups:
  - name: "AUTO"
    type: url-test
    use:
      - airport
    url: https://www.gstatic.com/generate_204
    interval: 300
    tolerance: 50

  - name: "PROXY"
    type: select
    proxies:
      - AUTO
      - DIRECT
    use:
      - airport

# ---- Rules ----
rules:
  - DOMAIN-SUFFIX,local,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOF

  chmod 600 "$cfg"

  echo "[+] Wrote config: $cfg"
  echo "[i] API secret => ${secret}"
}

install_service() {
  local svc="/etc/systemd/system/mihomo.service"
  backup_file "$svc"

  cat >"$svc" <<'EOF'
[Unit]
Description=mihomo (Clash compatible core)
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=2
LimitNOFILE=1000000
WorkingDirectory=/etc/mihomo
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now mihomo
  echo "[+] systemd service enabled: mihomo"
  systemctl --no-pager --full status mihomo || true
}

install_ui() {
  if [[ "${INSTALL_UI:-0}" != "1" ]]; then
    return
  fi

  if ! have_cmd git; then
    echo "[-] git not found; UI install skipped."
    return
  fi

  echo "[+] Installing metacubexd (gh-pages) to /etc/mihomo/ui ..."
  rm -rf /etc/mihomo/ui

  # 浅克隆更快
  if git clone --depth 1 -b gh-pages https://github.com/MetaCubeX/metacubexd.git /etc/mihomo/ui; then
    echo "[+] UI installed at /etc/mihomo/ui"
  else
    echo "[-] UI clone failed (network/proxy). You can retry later with proxy-enabled git."
    return
  fi

  # 确保 config 里有 external-ui
  if ! grep -qE '^\s*external-ui:\s*/etc/mihomo/ui\s*$' /etc/mihomo/config.yaml 2>/dev/null; then
    echo "[i] Adding external-ui to config..."
    # 插到 secret 后面（简单处理：追加也可用）
    printf '\nexternal-ui: /etc/mihomo/ui\n' >> /etc/mihomo/config.yaml
  fi

  systemctl restart mihomo
  echo "[+] mihomo restarted with UI enabled."
}

final_tips() {
  local mixed_port="${MIXED_PORT:-7890}"
  local ctrl_addr="${CTRL_ADDR:-127.0.0.1:9090}"

  echo
  echo "==================== DONE ===================="
  echo "Proxy:  http+socks mixed => 127.0.0.1:${mixed_port}"
  echo "API:    ${ctrl_addr}"
  echo
  echo "Test proxy:"
  echo "  curl -x http://127.0.0.1:${mixed_port} -s https://ifconfig.me ; echo"
  echo
  if [[ "${INSTALL_UI:-0}" == "1" ]]; then
    echo "Web UI (recommended via SSH tunnel, on your local PC):"
    echo "  ssh -L 9090:127.0.0.1:9090 root@<server_ip>"
    echo "  then open: http://127.0.0.1:9090/ui/"
  fi
  echo "=============================================="
}

main() {
  require_root
  install_deps
  download_mihomo
  write_config
  install_ui
  install_service
  final_tips
}

main "$@"
