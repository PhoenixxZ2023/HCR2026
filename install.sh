#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
install_binary=/usr/local/bin/hcr-server
unit_file=/etc/systemd/system/hcr-server.service
port=80
target=127.0.0.1:22
transport=plain
max_download_frame=6144
download_poll_timeout=8s
session_timeout=2m
session_stats_interval=0
max_connections=2048
max_sessions=32
max_sessions_per_ip=16
tls_cert="${script_dir}/fullchain.pem"
tls_key="${script_dir}/privkey.pem"
action=install

usage() {
    echo 'Usage: sudo ./install.sh [options]'
    echo '  --port N'
    echo '  --target HOST:PORT'
    echo '  --transport plain|tls|auto'
    echo '  --tls-cert FILE'
    echo '  --tls-key FILE'
    echo '  --max-download-frame N'
    echo '  --download-poll-timeout DURATION'
    echo '  --session-timeout DURATION'
    echo '  --session-stats-interval DURATION'
    echo '  --max-connections N'
    echo '  --max-sessions N'
    echo '  --max-sessions-per-ip N'
    echo '  --check'
    echo '  --uninstall'
    echo '  --help'
}

fail() { echo "HCR installer: $*" >&2; exit 1; }

while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --uninstall) action=uninstall; shift ;;
        --check) action=check; shift ;;
        --port|--target|--transport|--tls-cert|--tls-key|--max-download-frame|--download-poll-timeout|--session-timeout|--session-stats-interval|--max-connections|--max-sessions|--max-sessions-per-ip)
            (($# >= 2)) || fail "$1 requires a value"
            case "$1" in
                --port) port="$2" ;;
                --target) target="$2" ;;
                --transport) transport="$2" ;;
                --tls-cert) tls_cert="$2" ;;
                --tls-key) tls_key="$2" ;;
                --max-download-frame) max_download_frame="$2" ;;
                --download-poll-timeout) download_poll_timeout="$2" ;;
                --session-timeout) session_timeout="$2" ;;
                --session-stats-interval) session_stats_interval="$2" ;;
                --max-connections) max_connections="$2" ;;
                --max-sessions) max_sessions="$2" ;;
                --max-sessions-per-ip) max_sessions_per_ip="$2" ;;
            esac
            shift 2 ;;
        *) fail "unknown option: $1" ;;
    esac
done

((EUID == 0)) || fail 'run as root'

if [[ "$action" == uninstall ]]; then
    systemctl disable --now hcr-server.service 2>/dev/null || true
    if [[ -f "$unit_file" ]] && grep -q '^ExecStart=/usr/local/bin/hcr-server ' "$unit_file"; then
        rm -f -- "$unit_file"
    fi
    rm -f -- "$install_binary"
    systemctl daemon-reload
    echo 'HCR uninstalled.'
    exit 0
fi

case "$(uname -m)" in
    x86_64|amd64) package_binary="${script_dir}/bin/hcr-server-linux-amd64" ;;
    aarch64|arm64) package_binary="${script_dir}/bin/hcr-server-linux-arm64" ;;
    *) fail "unsupported architecture: $(uname -m)" ;;
esac

[[ -x "$package_binary" ]] || fail "missing executable $package_binary"
[[ "$port" =~ ^[0-9]+$ ]] && ((10#$port >= 1 && 10#$port <= 65535)) || fail 'invalid port'
port="$((10#$port))"
[[ "$target" =~ ^[A-Za-z0-9.-]+:[0-9]+$ || "$target" =~ ^\[[0-9A-Fa-f:]+\]:[0-9]+$ ]] || fail 'invalid target address'
[[ "$transport" == plain || "$transport" == tls || "$transport" == auto ]] || fail 'invalid transport'
[[ "$max_download_frame" =~ ^[0-9]+$ ]] && ((10#$max_download_frame >= 1 && 10#$max_download_frame <= 262140)) || fail 'invalid frame size'
max_download_frame="$((10#$max_download_frame))"
[[ "$download_poll_timeout" =~ ^[0-9]+(ms|s|m|h)$ ]] || fail 'invalid download poll timeout'
[[ "$session_timeout" =~ ^[0-9]+(ms|s|m|h)$ ]] || fail 'invalid session timeout'
[[ "$session_stats_interval" == 0 || "$session_stats_interval" =~ ^[0-9]+(ms|s|m|h)$ ]] || fail 'invalid statistics interval'
for limit in "$max_connections" "$max_sessions" "$max_sessions_per_ip"; do
    [[ "$limit" =~ ^[0-9]+$ ]] && ((10#$limit >= 1 && 10#$limit <= 100000)) || fail 'invalid limit'
done
max_connections="$((10#$max_connections))"
max_sessions="$((10#$max_sessions))"
max_sessions_per_ip="$((10#$max_sessions_per_ip))"
((max_sessions_per_ip <= max_sessions)) || fail 'per-IP session limit exceeds global limit'

tls_args=''
if [[ "$transport" != plain ]]; then
    [[ -r "$tls_cert" && -r "$tls_key" ]] || fail 'TLS certificate or key is not readable'
    [[ "$tls_cert" =~ ^/[-A-Za-z0-9._/]+$ && "$tls_key" =~ ^/[-A-Za-z0-9._/]+$ ]] || fail 'unsupported TLS path'
    tls_args=" --tls-cert ${tls_cert} --tls-key ${tls_key}"
fi

if [[ "$action" == check ]]; then
    echo "Valid configuration: architecture=$(uname -m) port=$port target=$target transport=$transport"
    exit 0
fi

install -m 0755 "$package_binary" "$install_binary"
temporary_unit="$(mktemp /etc/systemd/system/.hcr-server.XXXXXX.service)"
trap 'rm -f -- "$temporary_unit"' EXIT
cat >"$temporary_unit" <<EOF
[Unit]
Description=HCR TCP relay
After=network-online.target ssh.service sshd.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=${install_binary} --listen :${port} --target ${target} --transport ${transport} --max-download-frame ${max_download_frame} --download-poll-timeout ${download_poll_timeout} --session-timeout ${session_timeout} --session-stats-interval ${session_stats_interval} --max-connections ${max_connections} --max-sessions ${max_sessions} --max-sessions-per-ip ${max_sessions_per_ip}${tls_args}
Restart=on-failure
RestartSec=2s
LimitNOFILE=131072
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$temporary_unit"
mv -f -- "$temporary_unit" "$unit_file"
trap - EXIT
systemctl daemon-reload
systemctl enable hcr-server.service >/dev/null
systemctl restart hcr-server.service
systemctl is-active --quiet hcr-server.service || fail 'service failed to start; inspect journalctl -u hcr-server'
echo "HCR active on port $port, target $target, transport $transport"
