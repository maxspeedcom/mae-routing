#!/bin/sh
# MAE Routing container entrypoint: maps MAE_* settings onto containerboot's TS_* settings, then runs it.
#
#   MAE_ORG          network name (joins https://<MAE_ORG>.routing.maesuaisystem.com)        required
#   MAE_AUTHKEY      auth key from the admin console (Settings > Auth keys); without it the login URL is logged
#   MAE_HOSTNAME     device name in the network
#   MAE_ROUTES       subnets to advertise, e.g. 192.168.1.0/24,10.0.0.0/24
#   MAE_EXIT_NODE    true to offer this container as an exit node
#   MAE_ACCEPT_DNS   true/false: use the network's DNS settings (default false)
#   MAE_USERSPACE    true (default, no /dev/net/tun needed) or false (kernel TUN; needs NET_ADMIN + /dev/net/tun)
#   MAE_STATE_DIR    where keys are kept (default /var/lib/mae-routing; mount a volume here)
#   MAE_SOCKS5_SERVER, MAE_HTTP_PROXY   e.g. :1055 / :1080 to expose the network to other containers
#   MAE_EXTRA_ARGS   extra flags for "mae-routing up"
# Any TS_* variable understood by upstream containerboot still works.
set -eu

if [ -n "${MAE_ORG:-}" ]; then
	org=$(printf '%s' "$MAE_ORG" | tr 'A-Z' 'a-z')
	case "$org" in
		*[!a-z0-9-]*|"") echo "MAE_ORG must be the network name, e.g. MAE_ORG=maesuai" >&2; exit 64 ;;
	esac
	login="--login-server=https://${org}.routing.maesuaisystem.com"
elif [ -n "${MAE_LOGIN_SERVER:-}" ]; then
	login="--login-server=${MAE_LOGIN_SERVER}"
elif [ -z "${TS_EXTRA_ARGS:-}" ]; then
	echo "Set MAE_ORG to your network name, e.g. docker run -e MAE_ORG=maesuai -e MAE_AUTHKEY=hskey-auth-... ghcr.io/maxspeedcom/mae-routing" >&2
	exit 64
else
	login=""
fi

extra="$login ${MAE_EXTRA_ARGS:-}"
[ "${MAE_EXIT_NODE:-}" = true ] && extra="$extra --advertise-exit-node"
export TS_EXTRA_ARGS="$extra ${TS_EXTRA_ARGS:-}"
[ -n "${MAE_AUTHKEY:-}" ] && export TS_AUTHKEY="$MAE_AUTHKEY"
[ -n "${MAE_HOSTNAME:-}" ] && export TS_HOSTNAME="$MAE_HOSTNAME"
[ -n "${MAE_ROUTES:-}" ] && export TS_ROUTES="$MAE_ROUTES"
[ -n "${MAE_ACCEPT_DNS:-}" ] && export TS_ACCEPT_DNS="$MAE_ACCEPT_DNS"
[ -n "${MAE_USERSPACE:-}" ] && export TS_USERSPACE="$MAE_USERSPACE"
[ -n "${MAE_SOCKS5_SERVER:-}" ] && export TS_SOCKS5_SERVER="$MAE_SOCKS5_SERVER"
[ -n "${MAE_HTTP_PROXY:-}" ] && export TS_OUTBOUND_HTTP_PROXY_LISTEN="$MAE_HTTP_PROXY"
export TS_STATE_DIR="${MAE_STATE_DIR:-${TS_STATE_DIR:-/var/lib/mae-routing}}"
# same socket the CLI uses by default, so "docker exec <name> mae-routing status" just works
export TS_SOCKET="${TS_SOCKET:-/var/run/mae-routing/mae-routingd.sock}"
mkdir -p "$TS_STATE_DIR" "$(dirname "$TS_SOCKET")"
exec /usr/local/bin/containerboot "$@"
