# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A single-file bash installer (`install_mihomo.sh`) for [mihomo](https://github.com/MetaCubeX/mihomo) (a Clash-compatible proxy core) on RHEL/OpenCloudOS/Debian-family systems (x86_64 only). It installs the binary, generates config, sets up a systemd service, and optionally installs the metacubexd web UI.

## Running the Installer

```bash
sudo SUB_URL="YOUR_SUB_URL" SECRET="YOUR_SECRET" INSTALL_UI=1 ./install_mihomo.sh
```

**Environment variables:**

| Variable | Default | Description |
|---|---|---|
| `SUB_URL` | (required) | Clash-compatible proxy subscription URL |
| `SECRET` | random 24-char string | API authentication secret |
| `MIXED_PORT` | `7890` | HTTP+SOCKS mixed proxy port |
| `CTRL_ADDR` | `127.0.0.1:9090` | External controller address |
| `INSTALL_UI` | `0` | Set to `1` to install metacubexd web UI |
| `FORCE_CONFIG` | `0` | Set to `1` to overwrite existing config |

## Script Architecture

`install_mihomo.sh` runs these functions in sequence from `main()`:

1. **`require_root()`** — Exits if not running as root/sudo
2. **`install_deps()`** — Installs `curl`, `gzip`, `jq`, `ca-certificates` (and `git` if UI needed) via `dnf`/`yum`/`apt-get`
3. **`download_mihomo()`** — Queries GitHub API for latest MetaCubeX/mihomo release, selects the `mihomo-linux-amd64-{v1|v2|v3}.gz` asset matching CPU level, installs to `/usr/local/bin/mihomo`
4. **`write_config()`** — Writes `/etc/mihomo/config.yaml` (skips if exists unless `FORCE_CONFIG=1`); sets up proxy groups (AUTO url-test + PROXY select) and geo-based routing rules
5. **`install_ui()`** — Shallow-clones metacubexd gh-pages branch to `/etc/mihomo/ui/` (only when `INSTALL_UI=1`)
6. **`install_service()`** — Writes and enables `/etc/systemd/system/mihomo.service`, then starts it
7. **`final_tips()`** — Prints proxy endpoint, API endpoint, and SSH tunnel instructions for UI access

**Key helpers:**
- `have_cmd()` — checks if a command exists in PATH
- `detect_cpu_level()` — uses `ld-linux-x86-64.so.2` to determine x86-64 microarchitecture level (v1/v2/v3)
- `backup_file()` — backs up existing files with a timestamp suffix before overwriting

## Files Written to the System

- `/usr/local/bin/mihomo` — the mihomo binary
- `/etc/mihomo/config.yaml` — main config (mode 600)
- `/etc/mihomo/proxy_providers/` — directory for subscription provider configs
- `/etc/mihomo/ui/` — metacubexd web UI (optional)
- `/etc/systemd/system/mihomo.service` — systemd unit

## Linting

There is no CI or test suite. To lint the shell script manually:

```bash
shellcheck install_mihomo.sh
```
