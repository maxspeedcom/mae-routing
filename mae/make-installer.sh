#!/bin/bash
# Wrap mae/out/win (programs, wintun.dll, licences) into the NSIS installer mae/out/MAERouting-<version>-<build>-setup.exe.
#   mae/make-installer.sh <build-number>
# Called by build-windows.sh, or by .github/workflows/mae-windows.yml after the programs have been signed.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/.." && pwd)
BUILD=${1:?build number}
UPSTREAM=$(cat "$SRC/VERSION.txt")
F="$HERE/out/MAERouting-$UPSTREAM-$BUILD-setup.exe"
makensis -V2 -DVERSION="$UPSTREAM" -DBUILD="$BUILD" -DSRCDIR="$HERE/out/win" -DASSETS="$HERE/out" -DOUTFILE="$F" "$HERE/installer.nsi"
sha256sum "$F"
