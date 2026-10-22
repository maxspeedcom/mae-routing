#!/bin/bash
# Build MAE Routing for Linux (amd64, arm64, armv7, 386): tarballs, .deb, .rpm, SHA256SUMS and install.sh.
#   mae/build-linux.sh [build-number]
# Output: mae/out/linux/  (publish to CT 115 /opt/mae-routing/download/linux/ with publish-linux.sh)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/.." && pwd)
OUT=$HERE/out/linux
BUILD=${1:-1}
UPSTREAM=$(cat "$SRC/VERSION.txt")
VERSION="$UPSTREAM-$BUILD"                     # file names: mae-routing_1.104.2-1_amd64.tgz
export PATH=$PATH:/usr/local/go/bin:/root/go/bin
export CGO_ENABLED=0 GOOS=linux
TAGS=ts_omit_logtail,ts_omit_clientupdate
LDFLAGS="-s -w -X tailscale.com/version.longStamp=$UPSTREAM-mae$BUILD -X tailscale.com/version.shortStamp=$UPSTREAM"
command -v nfpm >/dev/null || go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.43.0

rm -rf "$OUT" && mkdir -p "$OUT"
cd "$SRC"
python3 "$HERE/apply-branding.py" "$SRC" >/dev/null
for ARCH in amd64 arm64 arm 386; do
  D="$OUT/mae-routing_${VERSION}_${ARCH}"
  mkdir -p "$D"
  echo "building linux/$ARCH"
  GOARCH=$ARCH GOARM=7 go build -trimpath -tags "$TAGS" -ldflags "$LDFLAGS" -o "$D/mae-routing" ./cmd/tailscale
  GOARCH=$ARCH GOARM=7 go build -trimpath -tags "$TAGS" -ldflags "$LDFLAGS" -o "$D/mae-routingd" ./cmd/tailscaled
  cp "$HERE/linux/mae-routingd.service" "$HERE/linux/mae-routingd.defaults" "$HERE/linux/mae-routingd.openrc" "$D/"
  cp "$SRC/LICENSE" "$D/THIRD-PARTY-NOTICES.txt"
  tar -C "$OUT" -czf "$OUT/mae-routing_${VERSION}_${ARCH}.tgz" "mae-routing_${VERSION}_${ARCH}"
  # packages use Debian/RPM arch names
  case $ARCH in arm) PARCH=armhf; RARCH=armv7hl ;; 386) PARCH=i386; RARCH=i386 ;; arm64) PARCH=arm64; RARCH=aarch64 ;; *) PARCH=amd64; RARCH=x86_64 ;; esac
  for fmt in deb rpm; do
    A=$PARCH; [ $fmt = rpm ] && A=$RARCH
    sed -e "s|\${ARCH}|$A|g" -e "s|\${VERSION}|$UPSTREAM|g" -e "s|\${BUILD}|$BUILD|g" -e "s|\${SRC}|$D|g" -e "s|\${SCRIPTS}|$HERE/linux|g" \
      "$HERE/linux/nfpm.yaml" > "$OUT/nfpm.yaml"
    nfpm package -f "$OUT/nfpm.yaml" -p $fmt -t "$OUT/" | grep -v '^using'
    rm "$OUT/nfpm.yaml"
  done
  rm -rf "$D"
done
# nfpm names: mae-routing_1.104.2-<build>_amd64.deb / mae-routing-1.104.2-<build>.x86_64.rpm
sed "s/__VERSION__/$VERSION/" "$HERE/linux/install.sh" > "$OUT/install.sh"
(cd "$OUT" && sha256sum *.tgz *.deb *.rpm > SHA256SUMS)
ls -la "$OUT"
