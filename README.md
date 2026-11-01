# MAE Routing client

MAE Routing (https://routing.maesuaisystem.com) is a private network for organisations: the computers, servers and
containers of a company join one encrypted WireGuard mesh, from anywhere, without opening ports.
This repository is the client for Windows, Linux and Docker. It is a fork of
[Tailscale](https://github.com/tailscale/tailscale) with its own Windows app, branding and build scripts.
Licence: BSD-3-Clause, see `LICENSE`.

## Install

Windows 10/11 (64-bit): https://routing.maesuaisystem.com/download/MAERouting-setup-latest.exe
(after that the app updates itself)

Linux (x86_64, arm64, armv7, i386; systemd or OpenRC):

    curl -fsSL https://routing.maesuaisystem.com/install.sh | sudo sh -s -- --org <network-name>

Docker:

    docker run -d --name mae-routing -e MAE_ORG=<network-name> -e MAE_AUTHKEY=<auth-key> \
      -v mae-routing:/var/lib/mae-routing ghcr.io/maxspeedcom/mae-routing

Step-by-step guide: https://routing.maesuaisystem.com/install

## Uninstall

- Windows: Settings > Apps > Installed apps > MAE Routing > Uninstall
- Linux: `curl -fsSL https://routing.maesuaisystem.com/install.sh | sudo sh -s -- --uninstall` (add `--purge` to delete the machine's keys)
- Docker: `docker rm -f mae-routing` (and `docker volume rm mae-routing` to delete the keys)

## Build

| Path | What |
| --- | --- |
| `mae/apply-branding.py` | all MAE Routing source edits (idempotent) |
| `cmd/mae-routing-gui` | Windows tray app `MAERouting.exe` |
| `mae/build-windows.sh`, `mae/make-installer.sh` | Windows service, CLI, tray app, then the NSIS installer |
| `.github/workflows/mae-windows.yml` | Windows release build on GitHub Actions (signing steps run only when configured) |
| `mae/build-linux.sh` | `mae-routing` + `mae-routingd`: .tgz, .deb, .rpm, `install.sh` |
| `mae/docker/`, `.github/workflows/mae-docker.yml` | container image for amd64, arm64, armv7 |

## Code signing policy

The Windows releases are not code-signed yet, so Windows SmartScreen warns the first time the installer runs.
After that the app updates itself and checks every update against the SHA-256 published on the website.

- The Windows programs `MAERouting.exe`, `maeroutingd.exe`, `mae-routing.exe` and the installer
  `MAERouting-<version>-setup.exe` are built from this repository by `.github/workflows/mae-windows.yml`;
  each GitHub release has the installer and its SHA-256.
  `wintun.dll` is shipped exactly as released and signed by WireGuard LLC.
- Committers, reviewers and approvers: [@maxspeedcom](https://github.com/maxspeedcom) (Maesuai System).
  Changes from outside the team are reviewed before they are merged, and every release is approved by hand before it
  is published.
- Details: https://routing.maesuaisystem.com/code-signing

## Privacy

This program connects only to systems the user chooses: the coordination server of the network the user signs in to
(`<network>.routing.maesuaisystem.com`), the relay servers that server lists, and the other machines of that network.
It does not send telemetry, crash reports or usage statistics to Maesuai System or to anyone else.
Privacy policy of the service: https://routing.maesuaisystem.com/privacy
