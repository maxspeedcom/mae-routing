# MAE Routing client

MAE Routing (https://routing.maesuaisystem.com) is a private network for organisations. This repository is
the client: Tailscale v1.104.2 (BSD-3-Clause, © Tailscale Inc & contributors) rebranded so it never shares
files, services, registry keys, network adapters or firewall rules with a real Tailscale install, with log
upload and self-update removed, plus a Thai tray app for Windows.

| Path | What |
| --- | --- |
| `mae/apply-branding.py` | all source edits (idempotent; fails loudly if upstream code moved) |
| `cmd/mae-routing-gui` | Windows tray app (`MAERouting.exe`), sign-in by network name |
| `cmd/tailscale/cli/mae_org.go` | `mae-routing up --org NAME` = `--login-server https://NAME.routing.maesuaisystem.com` |
| `mae/build-windows.sh` | `maeroutingd.exe`, `mae-routing.exe`, `MAERouting.exe`, wintun.dll and the NSIS installer |
| `mae/build-linux.sh` | `mae-routing` + `mae-routingd` for amd64, arm64, armv7, 386: .tgz, .deb, .rpm, `install.sh` |
| `mae/docker/` + `.github/workflows/mae-docker.yml` | `ghcr.io/maxspeedcom/mae-routing` (amd64, arm64, armv7) |

Install on Linux: `curl -fsSL https://routing.maesuaisystem.com/install.sh | sh -s -- --org <network-name>`

Docker:

    docker run -d --name mae-routing -e MAE_ORG=<network-name> -e MAE_AUTHKEY=<auth-key> \
      -v mae-routing:/var/lib/mae-routing ghcr.io/maxspeedcom/mae-routing
