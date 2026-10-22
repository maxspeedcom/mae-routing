#!/bin/sh
# deb: "remove"/"upgrade"; rpm: 0 = remove, 1 = upgrade
case "$1" in
	remove|0) [ -d /run/systemd/system ] && systemctl disable --now mae-routingd >/dev/null 2>&1 || true ;;
esac
