# MAE Routing client

MAE Routing (https://routing.maesuaisystem.com) is a private network for organisations: every computer,
server and phone of a company joins one encrypted WireGuard mesh, from anywhere, without opening ports.
This repository is the client for Windows, Linux and Docker. Licence: BSD-3-Clause, see `LICENSE`.

## Install

Linux (x86_64, arm64, armv7, i386; systemd or OpenRC):

    curl -fsSL https://routing.maesuaisystem.com/install.sh | sudo sh -s -- --org <network-name>

Windows 10/11: https://routing.maesuaisystem.com/download/MAERouting-setup-latest.exe

Docker:

    docker run -d --name mae-routing -e MAE_ORG=<network-name> -e MAE_AUTHKEY=<auth-key> \
      -v mae-routing:/var/lib/mae-routing ghcr.io/maxspeedcom/mae-routing

## Build

| Path | What |
| --- | --- |
| `mae/apply-branding.py` | all MAE Routing source edits (idempotent) |
| `cmd/mae-routing-gui` | Windows tray app `MAERouting.exe` |
| `mae/build-windows.sh` | Windows service, CLI, tray app and installer |
| `mae/build-linux.sh` | `mae-routing` + `mae-routingd`: .tgz, .deb, .rpm, `install.sh` |
| `mae/docker/`, `.github/workflows/mae-docker.yml` | container image for amd64, arm64, armv7 |
