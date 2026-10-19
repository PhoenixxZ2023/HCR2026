# HCR Forjado

This package contains the HCR Android client, statically compiled Linux server binaries for AMD64 and ARM64, the server source, and an installer.

## Package contents

- `HCR-Client.apk`: Android HCR-only VPN client.
- `install.sh`: architecture-detecting systemd installer.
- `bin/hcr-server-linux-amd64`: server for Intel/AMD 64-bit VPS systems.
- `bin/hcr-server-linux-arm64`: server for ARM64 VPS systems.
- `source`: buildable Go server source.

## Requirements

- A Linux VPS using systemd.
- Root access.
- OpenSSH listening on the target address, normally `127.0.0.1:22`.
- The selected public TCP port allowed by the VPS firewall and provider firewall.
- An Android ARM64 or ARMv7 device for the included APK.

## Install on port 80

Extract the ZIP on the VPS and run:

```bash
chmod +x install.sh
sudo ./install.sh --port 80 --target 127.0.0.1:22 --transport plain
```

The installer detects AMD64 or ARM64, copies the correct server to `/usr/local/bin/hcr-server`, creates `/etc/systemd/system/hcr-server.service`, enables it at boot, and starts it.

Check it:

```bash
systemctl status hcr-server --no-pager
journalctl -u hcr-server -n 100 --no-pager
ss -ltnp | grep ':80'
```

If port 80 is already occupied, stop the conflicting service or select another port.

## Recommended installation profile

```bash
sudo ./install.sh \
  --port 80 \
  --target 127.0.0.1:22 \
  --transport plain \
  --max-download-frame 6144 \
  --download-poll-timeout 8s \
  --session-timeout 2m \
  --session-stats-interval 10s \
  --max-connections 2048 \
  --max-sessions 128 \
  --max-sessions-per-ip 128
```

## Change the public port

Rerun the installer with the new port. It replaces the service configuration and restarts HCR:

```bash
sudo ./install.sh --port 8080 --target 127.0.0.1:22 --transport plain
```

Then change the port in HCR Client to `8080` and allow it in the firewall.

Examples for common firewalls:

```bash
ufw allow 80/tcp
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --reload
```

## Change the SSH target

Forward HCR to an SSH server on another local port:

```bash
sudo ./install.sh --port 80 --target 127.0.0.1:2222 --transport plain
```

Forward to another private host:

```bash
sudo ./install.sh --port 80 --target 10.0.0.20:22 --transport plain
```

The target must be reachable from the VPS.

## Create an SSH test user

```bash
sudo useradd -m -s /bin/bash hcrtest
sudo passwd hcrtest
```

Use the VPS host, HCR public port, `hcrtest`, and the chosen password in the Android client. The account does not need sudo access.

## Android client

Install `HCR-Client.apk`, approve the Android VPN prompt, and enter:

- Server: VPS domain or IP.
- Port: the HCR public port, normally `80`.
- User: an SSH/PAM user on the target SSH server.
- Password: that SSH user's password.
- DNS: `1.1.1.1` or another DNS server supporting TCP port 53.

Tap Connect. A successful startup reaches `VPN connected and routing traffic`. The client explicitly protects its outer HCR sockets from VPN recursion and preserves HCR byte offsets during temporary network failures.

## Service controls

```bash
systemctl start hcr-server
systemctl stop hcr-server
systemctl restart hcr-server
systemctl status hcr-server --no-pager
journalctl -u hcr-server -f
```

Validate installer arguments without changing the service:

```bash
sudo ./install.sh --check --port 80 --target 127.0.0.1:22 --transport plain
```

Uninstall:

```bash
sudo ./install.sh --uninstall
```

## TLS mode

Plain mode is intended for the HCR Client included here. To run the server with TLS:

```bash
sudo ./install.sh \
  --port 443 \
  --target 127.0.0.1:22 \
  --transport tls \
  --tls-cert /etc/letsencrypt/live/example.com/fullchain.pem \
  --tls-key /etc/letsencrypt/live/example.com/privkey.pem
```

`auto` accepts both plain and TLS connections but still requires the certificate and key options. The included Android client currently uses plain HCR.

## Installer options

| Option | Default | Meaning |
|---|---:|---|
| `--port N` | `80` | Public HCR TCP port. |
| `--target HOST:PORT` | `127.0.0.1:22` | TCP destination carried through HCR. |
| `--transport MODE` | `plain` | `plain`, `tls`, or `auto`. |
| `--tls-cert FILE` | package `fullchain.pem` | TLS certificate chain. |
| `--tls-key FILE` | package `privkey.pem` | TLS private key. |
| `--max-download-frame N` | `6144` | Maximum bytes read from the target per replay frame. |
| `--download-poll-timeout DURATION` | `8s` | Long-poll duration when no downstream data is available. |
| `--session-timeout DURATION` | `2m` | Time before an inactive HCR session is removed. |
| `--session-stats-interval DURATION` | `0` | Aggregate statistics interval; `0` disables it. |
| `--max-connections N` | `2048` | Maximum simultaneous request connections. |
| `--max-sessions N` | `32` | Maximum active HCR sessions. |
| `--max-sessions-per-ip N` | `16` | Maximum sessions attributed to one source IP. |
| `--check` | off | Validate configuration without installing. |
| `--uninstall` | off | Stop and remove the installed service and binary. |
| `--help` | off | Print installer help. |

Durations accept Go duration suffixes such as `500ms`, `8s`, `2m`, and `1h`.

## HCR server binary options

Run the correct architecture binary directly or use `hcr-server --help` after installation.

| Option | Binary default | Meaning |
|---|---:|---|
| `--listen ADDRESS` | `:8080` | Local address and TCP port to bind. |
| `--target ADDRESS` | `127.0.0.1:22` | Target TCP service. |
| `--transport MODE` | `auto` | `plain`, `tls`, or `auto`. |
| `--tls-cert FILE` | empty | TLS certificate chain. |
| `--tls-key FILE` | empty | TLS private key. |
| `--max-download-frame N` | `6144` | Maximum target-read frame size. |
| `--download-poll-timeout DURATION` | `8s` | Empty downstream long-poll timeout. |
| `--session-timeout DURATION` | `2m` | Inactive session lifetime. |
| `--session-stats-interval DURATION` | `0` | Statistics log interval; `0` disables it. |
| `--max-connections N` | `2048` | Concurrent request connection limit. |
| `--max-sessions N` | `32` | Global active session limit. |
| `--max-sessions-per-ip N` | `16` | Active session limit per source IP. |

Direct example:

```bash
./bin/hcr-server-linux-amd64 \
  --listen :80 \
  --target 127.0.0.1:22 \
  --transport plain \
  --max-download-frame 6144 \
  --download-poll-timeout 8s \
  --session-timeout 2m
```

Use `hcr-server-linux-arm64` instead on ARM64.

## Build from source

Install Go, then run:

```bash
cd source
go test ./...
./build.sh
```

The build script produces `source/hcr-server` for the current Linux architecture.

Cross-compile manually:

```bash
cd source
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags '-s -w' -o hcr-server-amd64 ./cmd/hcr-server
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags '-s -w' -o hcr-server-arm64 ./cmd/hcr-server
```

## Troubleshooting

If the service does not start, check whether the port is already in use:

```bash
ss -ltnp
journalctl -u hcr-server -n 200 --no-pager
```

If SSH authentication fails, test the same account locally on the VPS:

```bash
ssh USER@127.0.0.1 -p 22
```

If the Android client connects but traffic does not move, confirm the APK is version 1.0.2 or newer and look for `HCR outer sockets protected from VPN recursion` in its log.
