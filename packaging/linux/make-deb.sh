#!/usr/bin/env bash
# Build a Debian package from an already-exported Kainat System Settings binary.
#
#   packaging/linux/make-deb.sh <binary> <version> [output-dir]
#
# The package installs:
#   /usr/lib/kainat-system-settings/kainat-system-settings   the ELF + embedded PCK
#   /usr/bin/kainat-system-settings                          symlink, so the app is on PATH
#   /usr/share/applications/kainat-system-settings.desktop   launcher entry
#   /usr/share/icons/hicolor/scalable/apps/…svg              icon
#   /usr/share/doc/kainat-system-settings/copyright
#
# Needs dpkg-deb (dpkg). No fakeroot: --root-owner-group does the job.
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
[ -r "$BIN" ] || { echo "error: binary is not readable: $BIN" >&2; exit 1; }
command -v dpkg-deb >/dev/null || { echo "error: dpkg-deb is required" >&2; exit 1; }

PKG=kainat-system-settings
ARCH=amd64
HOMEPAGE="https://github.com/KAINAT-OS/kainat-system-settings"
MAINTAINER="Kainat OS <68397736+kainatquaderee@users.noreply.github.com>"

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
DESKTOP=$HERE/$PKG.desktop
ICON=$ROOT/icon.svg

[ -f "$DESKTOP" ] || { echo "error: missing $DESKTOP" >&2; exit 1; }
[ -f "$ICON" ] || { echo "error: missing $ICON" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Dependencies
#
# The engine binary has very few DT_NEEDED entries (libc, libm, librt, libdl,
# libpthread) because Redot dlopen()s the platform libraries at runtime. That
# means dpkg-shlibdeps cannot see them, so they are listed explicitly below.
# The list was derived from the library names embedded in the export template
# (`strings <binary> | grep -oE 'lib.*\.so[.0-9]*'`) and checked against the
# package names in Debian trixie and Ubuntu noble.
# ---------------------------------------------------------------------------

# Hard requirements: without these the window cannot be created.
DEPENDS="libc6 (>= 2.28),
 libfontconfig1,
 libfreetype6,
 libx11-6,
 libxcursor1,
 libxext6,
 libxinerama1,
 libxi6,
 libxrandr2,
 libxrender1,
 libxkbcommon0,
 libgl1,
 libegl1,
 libgles2,
 libdbus-1-3,
 libudev1,
 bash,
 pkexec | policykit-1"

# Installed by default with the package: audio, Wayland, Vulkan, speech and the
# Plasma pieces the "open the KDE module" rows hand off to.
RECOMMENDS="libpulse0,
 libasound2t64 | libasound2,
 wireplumber | pulseaudio,
 libwayland-client0,
 libwayland-cursor0,
 libwayland-egl1,
 libdecor-0-0,
 libvulkan1,
 libspeechd2,
 systemsettings,
 plasma-workspace,
 xdg-utils"

# Every panel probes for its tools and shows an "Install …" row when one is
# missing, so these are optional: suggested, never required.
SUGGESTS="network-manager,
 modemmanager,
 bluez,
 ufw,
 cups,
 cups-client,
 samba,
 samba-common-bin,
 timeshift,
 smartmontools,
 fwupd,
 power-profiles-daemon,
 flatpak,
 snapd,
 wine,
 winetricks,
 openssh-client,
 openvpn,
 wireguard-tools,
 kscreen,
 libkscreen-bin,
 kde-cli-tools,
 libkf6config-bin,
 qdbus-qt6,
 efibootmgr,
 grub2-common,
 systemd,
 systemd-timesyncd,
 lm-sensors,
 x11-xserver-utils,
 x11-xkb-utils"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

APPDIR=$STAGE/$PKG
install -Dm755 "$BIN" "$APPDIR/usr/lib/$PKG/$PKG"
install -d "$APPDIR/usr/bin"
ln -s "../lib/$PKG/$PKG" "$APPDIR/usr/bin/$PKG"
install -Dm644 "$DESKTOP" "$APPDIR/usr/share/applications/$PKG.desktop"
install -Dm644 "$ICON" "$APPDIR/usr/share/icons/hicolor/scalable/apps/$PKG.svg"
install -Dm644 /dev/stdin "$APPDIR/usr/share/doc/$PKG/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: $PKG
Source: $HOMEPAGE

Files: *
Copyright: Kainat OS contributors
License: see $HOMEPAGE
EOF

# Refresh desktop/icon caches after install and removal. Failures are ignored:
# a missing update-desktop-database must never make the package uninstallable.
install -Dm755 /dev/stdin "$APPDIR/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
	update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
	gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
EOF
install -Dm755 /dev/stdin "$APPDIR/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
	update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
	gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
EOF

INSTALLED_SIZE=$(du -sk "$APPDIR" | cut -f1)

install -Dm644 /dev/stdin "$APPDIR/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Architecture: $ARCH
Maintainer: $MAINTAINER
Installed-Size: $INSTALLED_SIZE
Depends: $(printf '%s' "$DEPENDS" | tr -d '\n')
Recommends: $(printf '%s' "$RECOMMENDS" | tr -d '\n')
Suggests: $(printf '%s' "$SUGGESTS" | tr -d '\n')
Section: admin
Priority: optional
Homepage: $HOMEPAGE
Description: graphical administration tool for Kainat OS
 Kainat System Settings is a native desktop application that covers the whole
 system administration surface of Kainat OS without a terminal: appearance,
 displays, accessibility, input methods, sound, Bluetooth, printers, hardware,
 network, VPN, SSH, file sharing, firewall, applications, updates, drivers,
 services, disks, backups, boot and kernel, troubleshooting, power, date and
 time, language, sessions and users.
 .
 Complex tasks open the matching KDE settings module, and any missing optional
 tool is replaced by an "Install" row instead of an error.
EOF

mkdir -p "$OUT"
DEB=$OUT/${PKG}_${VERSION}_${ARCH}.deb
dpkg-deb --build --root-owner-group "$APPDIR" "$DEB" >/dev/null
echo "$DEB"
