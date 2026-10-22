#!/bin/sh
if [ -d /run/systemd/system ]; then
	systemctl daemon-reload >/dev/null 2>&1 || true
	systemctl enable mae-routingd >/dev/null 2>&1 || true
	systemctl restart mae-routingd >/dev/null 2>&1 || true
fi
echo "MAE Routing installed. Join your network with: sudo mae-routing up --org <network-name>"
