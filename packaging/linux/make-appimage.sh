#!/usr/bin/env bash
# Build an AppImage from an already-exported Kainat System Settings binary.
#
#   packaging/linux/make-appimage.sh <binary> <version> [output-dir]
#
# appimagetool is taken from $APPIMAGETOOL when set, otherwise from PATH, and
# otherwise downloaded once into ${XDG_CACHE_HOME:-~/.cache}/kainat-appimage.
# The AppImage runtime needs FUSE2 at *run* time; the build itself uses
# --appimage-extract-and-run so it works on machines without libfuse2.
set -euo pipefail

usage() {
	echo "usage: $0 <exported-binary> <version> [output-dir]" >&2
	exit 2
}

[ "$#" -ge 2 ] || usage
BIN=$1
VERSION=$2
OUT=${3:-dist}

[ -f "$BIN" ] || { echo "error: binary not found: $BIN" >&2; exit 1; }
[ -x "$BIN" ] || { echo "error: binary is not executable: $BIN" >&2; exit 1; }

PKG=kainat-system-settings
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
DESKTOP=$HERE/$PKG.desktop
ICON=$ROOT/icon.svg

[ -f "$DESKTOP" ] || { echo "error: missing $DESKTOP" >&2; exit 1; }
[ -f "$ICON" ] || { echo "error: missing $ICON" >&2; exit 1; }

resolve_tool() {
	if [ -n "${APPIMAGETOOL:-}" ]; then
		TOOL=$APPIMAGETOOL
	elif command -v appimagetool >/dev/null 2>&1; then
		TOOL=$(command -v appimagetool)
	else
		local cache="${XDG_CACHE_HOME:-$HOME/.cache}/kainat-appimage"
		mkdir -p "$cache"
		TOOL=$cache/appimagetool-x86_64.AppImage
		if [ ! -x "$TOOL" ]; then
			echo "Downloading appimagetool" >&2
			curl -fL --retry 3 --retry-delay 5 -o "$TOOL" \
				"https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
			chmod +x "$TOOL"
		fi
	fi
}

resolve_tool

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

APPDIR=$STAGE/AppDir
install -Dm755 "$BIN" "$APPDIR/usr/bin/$PKG"
install -Dm644 "$DESKTOP" "$APPDIR/usr/share/applications/$PKG.desktop"
install -Dm644 "$ICON" "$APPDIR/usr/share/icons/hicolor/scalable/apps/$PKG.svg"

# The AppImage spec wants the desktop file, the icon and AppRun at the root of
# AppDir. AppRun is a tiny launcher so the payload can stay under usr/.
install -Dm644 "$DESKTOP" "$APPDIR/$PKG.desktop"
install -Dm644 "$ICON" "$APPDIR/$PKG.svg"
ln -s "$PKG.svg" "$APPDIR/.DirIcon"
install -Dm755 /dev/stdin "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE=$(dirname "$(readlink -f "$0")")
exec "$HERE/usr/bin/kainat-system-settings" "$@"
EOF

mkdir -p "$OUT"
IMAGE=$OUT/${PKG}-${VERSION}-x86_64.AppImage
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 \
	"$TOOL" --no-appstream "$APPDIR" "$IMAGE" >/dev/null
chmod +x "$IMAGE"
echo "$IMAGE"
