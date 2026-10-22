#!/bin/sh
# MAE Routing for Linux — installer
#
#   curl -fsSL https://routing.maesuaisystem.com/install.sh | sh
#   curl -fsSL https://routing.maesuaisystem.com/install.sh | sh -s -- --org maesuai --auth-key hskey-auth-...
#
# Options:
#   --org NAME              join the network NAME.routing.maesuaisystem.com after installing
#   --auth-key KEY          sign in without a browser (create keys in the admin console > Settings)
#   --hostname NAME         device name in the network
#   --advertise-routes LIST e.g. 192.168.1.0/24 (subnet router)
#   --advertise-exit-node   offer this machine as an exit node
#   --uninstall [--purge]   remove MAE Routing (--purge also deletes this machine's keys)
#
# Works on any Linux with systemd or OpenRC: Debian, Ubuntu, RHEL/Rocky/Alma, Fedora, Arch, SUSE, Alpine,
# Raspberry Pi OS, Proxmox. CPU: x86_64, arm64, armv7, i386.
# Runs next to other mesh VPN clients: MAE Routing uses 10.77.0.0/16, UDP 41642, route table 77, chains mr-*.
set -eu

VERSION="__VERSION__"
BASE="${MAE_ROUTING_BASE:-https://routing.maesuaisystem.com/download/linux}"
ORG="" AUTHKEY="" HOSTNAME_ARG="" ROUTES="" EXITNODE="" UNINSTALL="" PURGE=""

say() { printf '%s\n' "$*"; }
die() { printf 'mae-routing install: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
	case "$1" in
		--org) ORG="${2:-}"; shift ;;
		--org=*) ORG="${1#*=}" ;;
		--auth-key|--authkey) AUTHKEY="${2:-}"; shift ;;
		--auth-key=*|--authkey=*) AUTHKEY="${1#*=}" ;;
		--hostname) HOSTNAME_ARG="${2:-}"; shift ;;
		--hostname=*) HOSTNAME_ARG="${1#*=}" ;;
		--advertise-routes) ROUTES="${2:-}"; shift ;;
		--advertise-routes=*) ROUTES="${1#*=}" ;;
		--advertise-exit-node) EXITNODE=1 ;;
		--force) ;;   # accepted for compatibility
		--uninstall) UNINSTALL=1 ;;
		--purge) PURGE=1 ;;
		-h|--help) sed -n '2,20p' "$0" 2>/dev/null || true; exit 0 ;;
		*) die "unknown option: $1" ;;
	esac
	shift
done

# ---- root
if [ "$(id -u)" != 0 ]; then
	if command -v sudo >/dev/null 2>&1; then
		say "Root is needed; re-running with sudo..."
		if [ -f "$0" ] && [ "$0" != "sh" ]; then
			exec sudo sh "$0" "$@"
		fi
		die "run it as root: curl -fsSL https://routing.maesuaisystem.com/install.sh | sudo sh"
	fi
	die "please run as root"
fi

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
	INIT=systemd
elif command -v openrc-run >/dev/null 2>&1 || [ -x /sbin/openrc-run ]; then
	INIT=openrc
else
	INIT=none
fi

stop_service() {
	case "$INIT" in
		systemd) systemctl disable --now mae-routingd >/dev/null 2>&1 || true ;;
		openrc) rc-service mae-routingd stop >/dev/null 2>&1 || true; rc-update del mae-routingd default >/dev/null 2>&1 || true ;;
	esac
}

# ---- uninstall
if [ -n "$UNINSTALL" ]; then
	stop_service
	[ -x /usr/sbin/mae-routingd ] && /usr/sbin/mae-routingd --cleanup >/dev/null 2>&1 || true
	rm -f /usr/bin/mae-routing /usr/sbin/mae-routingd /etc/systemd/system/mae-routingd.service /etc/init.d/mae-routingd
	[ "$INIT" = systemd ] && systemctl daemon-reload || true
	if [ -n "$PURGE" ]; then
		rm -rf /var/lib/mae-routing /etc/default/mae-routingd
		say "MAE Routing removed (keys and settings deleted)."
	else
		say "MAE Routing removed. Keys kept in /var/lib/mae-routing (use --purge to delete)."
	fi
	exit 0
fi

# ---- platform
case "$(uname -s)" in Linux) ;; *) die "this installer is for Linux; see https://routing.maesuaisystem.com/#download" ;; esac
case "$(uname -m)" in
	x86_64|amd64) ARCH=amd64 ;;
	aarch64|arm64) ARCH=arm64 ;;
	armv7l|armv7*|armv6l|armhf) ARCH=arm ;;
	i386|i486|i586|i686) ARCH=386 ;;
	*) die "unsupported CPU $(uname -m); supported: x86_64, arm64, armv7, i386" ;;
esac


fetch() { # url dest
	if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 -o "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1"
	else die "need curl or wget"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PKG="mae-routing_${VERSION}_${ARCH}.tgz"
say "Downloading MAE Routing ${VERSION} (${ARCH})..."
fetch "$BASE/$PKG" "$TMP/$PKG"
fetch "$BASE/SHA256SUMS" "$TMP/SHA256SUMS"
WANT=$(grep " $PKG\$" "$TMP/SHA256SUMS" | cut -d' ' -f1)
if command -v sha256sum >/dev/null 2>&1; then GOT=$(sha256sum "$TMP/$PKG" | cut -d' ' -f1)
else GOT=$(shasum -a 256 "$TMP/$PKG" | cut -d' ' -f1); fi
[ -n "$WANT" ] && [ "$WANT" = "$GOT" ] || die "checksum mismatch for $PKG"
tar -xzf "$TMP/$PKG" -C "$TMP"
D="$TMP/mae-routing_${VERSION}_${ARCH}"

stop_service
install -m 0755 "$D/mae-routing" /usr/bin/mae-routing
install -m 0755 "$D/mae-routingd" /usr/sbin/mae-routingd
mkdir -p /var/lib/mae-routing && chmod 0700 /var/lib/mae-routing
if [ ! -f /etc/default/mae-routingd ]; then
	mkdir -p /etc/default
	install -m 0644 "$D/mae-routingd.defaults" /etc/default/mae-routingd
	if [ ! -c /dev/net/tun ]; then
		# containers without a TUN device (e.g. LXC without /dev/net/tun): userspace networking still works
		sed -i 's|^FLAGS=""|FLAGS="--tun=userspace-networking"|' /etc/default/mae-routingd
		say "No /dev/net/tun here: using userspace networking."
	fi
fi

case "$INIT" in
	systemd)
		install -m 0644 "$D/mae-routingd.service" /etc/systemd/system/mae-routingd.service
		systemctl daemon-reload
		systemctl enable --now mae-routingd >/dev/null 2>&1 || systemctl restart mae-routingd
		;;
	openrc)
		install -m 0755 "$D/mae-routingd.openrc" /etc/init.d/mae-routingd
		rc-update add mae-routingd default >/dev/null 2>&1 || true
		rc-service mae-routingd restart >/dev/null 2>&1 || rc-service mae-routingd start
		;;
	none)
		say "No systemd or OpenRC found: start the daemon yourself, e.g."
		say "  mae-routingd --state=/var/lib/mae-routing/mae-routingd.state --socket=/run/mae-routing/mae-routingd.sock &"
		;;
esac

i=0
while [ ! -S /run/mae-routing/mae-routingd.sock ] && [ ! -S /var/run/mae-routing/mae-routingd.sock ] && [ $i -lt 20 ]; do
	sleep 1; i=$((i + 1))
done

say "MAE Routing ${VERSION} installed."
if [ -n "$ORG" ]; then
	set -- up --org "$ORG"
	[ -n "$AUTHKEY" ] && set -- "$@" --auth-key "$AUTHKEY"
	[ -n "$HOSTNAME_ARG" ] && set -- "$@" --hostname "$HOSTNAME_ARG"
	[ -n "$ROUTES" ] && set -- "$@" --advertise-routes "$ROUTES"
	[ -n "$EXITNODE" ] && set -- "$@" --advertise-exit-node
	mae-routing "$@"
	say ""
	mae-routing status 2>/dev/null | head -5 || true
else
	say "Next: join your organisation's network:"
	say "  sudo mae-routing up --org <network-name>"
	say "No network yet? Create one free at https://routing.maesuaisystem.com/signup"
fi
