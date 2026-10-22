#!/bin/bash
# Build the MAE Routing Windows client (amd64) from the branded tailscale fork, then the NSIS installer.
#   mae/build-windows.sh [build-number]
# Output: mae/out/win/{maeroutingd.exe,mae-routing.exe,MAERouting.exe,wintun.dll}
#         mae/out/MAERouting-<version>-<build>-setup.exe
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/.." && pwd)
OUT=$HERE/out/win
BUILD=${1:-1}
UPSTREAM=$(cat "$SRC/VERSION.txt")             # e.g. 1.104.2
VERSION="$UPSTREAM-mae$BUILD"
export PATH=$PATH:/usr/local/go/bin
export GOOS=windows GOARCH=amd64 CGO_ENABLED=0
TAGS=ts_omit_logtail,ts_omit_clientupdate        # no log upload to Tailscale Inc, no self-update from pkgs.tailscale.com
LDFLAGS="-s -w -X tailscale.com/version.longStamp=$VERSION -X tailscale.com/version.shortStamp=$UPSTREAM"

mkdir -p "$OUT"
cd "$SRC"
python3 "$HERE/apply-branding.py" "$SRC" >/dev/null
echo "building $VERSION"
go build -trimpath -tags "$TAGS" -ldflags "$LDFLAGS" -o "$OUT/maeroutingd.exe" ./cmd/tailscaled
go build -trimpath -tags "$TAGS" -ldflags "$LDFLAGS" -o "$OUT/mae-routing.exe" ./cmd/tailscale
go build -trimpath -tags "$TAGS" -ldflags "$LDFLAGS -H windowsgui" -o "$OUT/MAERouting.exe" ./cmd/mae-routing-gui

# wintun.dll (signed by WireGuard LLC), pinned to the release tailscale tests against
WINTUN_URL=$(sed -n 's/.*URL = "\(.*\)" + Version + "\(.*\)"/\1/p' tsconst/wintun/wintun.go)
WVER=$(sed -n 's/.*Version = "\(.*\)"/\1/p' tsconst/wintun/wintun.go)
WSHA=$(sed -n 's/.*SHA256 = "\(.*\)"/\1/p' tsconst/wintun/wintun.go)
if [ ! -f "$HERE/out/wintun-$WVER.zip" ]; then
  curl -fsSL -o "$HERE/out/wintun-$WVER.zip" "https://www.wintun.net/builds/wintun-$WVER.zip"
fi
echo "$WSHA  $HERE/out/wintun-$WVER.zip" | sha256sum -c --quiet
unzip -o -q -j "$HERE/out/wintun-$WVER.zip" "wintun/bin/amd64/wintun.dll" -d "$OUT"
cp "$SRC/LICENSE" "$OUT/THIRD-PARTY-NOTICES.txt"
unzip -o -q -j "$HERE/out/wintun-$WVER.zip" "wintun/LICENSE.txt" -d "$HERE/out" && mv "$HERE/out/LICENSE.txt" "$OUT/LICENSE-wintun.txt"
ls -la "$OUT"

if command -v makensis >/dev/null; then
  makensis -V2 -DVERSION="$UPSTREAM" -DBUILD="$BUILD" -DSRCDIR="$OUT" -DASSETS="$HERE/out" \
    -DOUTFILE="$HERE/out/MAERouting-$UPSTREAM-$BUILD-setup.exe" "$HERE/installer.nsi"
  sha256sum "$HERE/out/MAERouting-$UPSTREAM-$BUILD-setup.exe"
fi
