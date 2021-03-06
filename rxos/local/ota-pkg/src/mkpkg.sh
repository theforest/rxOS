#!/bin/bash
#
# Create .pkg file for OTA updates and flashing firmware updates.
#
# This file is part of rxOS.
# rxOS is free software licensend under the
# GNU GPL version 3 or any later version.
#
# (c) 2016 Outernet Inc
# Some right reserved.

set -e

SCRIPTDIR="$BR2_EXTERNAL/scripts"
. "$SCRIPTDIR/helpers.sh"
. "$SCRIPTDIR/args.sh"

GITVER="$(cd "$BR2_EXTERNAL"; git rev-parse --short HEAD)"
DATE="$(date +%Y%m%d%H%M)"
[ "$VERSIONED_PKG" = y ] && SUFFIX=nv
FULL_VERSION="v${VERSION}-${DATE}${SUFFIX}+$GITVER"

PKGFILE="$BINARIES_DIR/${PLATFORM}-${SUBPLATFORM}-${FULL_VERSION}"
INSTALLER="$BINARIES_DIR/installer.sh"
BOOT_PACKAGING_CANDIDATES="
zImage
kernel.img
sun5i-r8-chip.dtb
u-boot-dtb.bin
uboot-env.bin
pre-install.sh
post-install.sh
"
FULL_PACKAGING_CANDIDATES="
zImage
kernel.img
sun5i-r8-chip.dtb
u-boot-dtb.bin
uboot-env.bin
rootfs.ubifs
rootfs.squashfs
pre-install.sh
post-install.sh
"
MINI_PACKAGING_CANDIDATES="
rootfs.ubifs
rootfs.squashfs
pre-install.sh
post-install.sh
"
KEY="$BINARIES_DIR/signature.pem"
PWFILE="$BR2_EXTERNAL/../.password"

create_pkg() {
  pkgname="$1"
  include="$2"
  submsg "Enumerating package files"
  mkpkg_args="${INSTALLER}:run.sh"
  for filename in $include; do
    if [ -f "$BINARIES_DIR/$filename" ]; then
      mkpkg_args="$mkpkg_args ${BINARIES_DIR}/$filename"
    fi
  done
  mkpkg_args="-o $pkgname $mkpkg_args"
  if [ -f "$KEY" ]; then
    mkpkg_args="-k $KEY -p $PASSWORD $mkpkg_args"
  fi
  submsg "Writing the package file"
  mkpkg $mkpkg_args
}

if [ -f "$KEY" ]
then
  msg "Package signing"
  if [ -f "$PWFILE" ]; then
    PASSWORD="$(cat "$PWFILE")"
    echo "Read password from password file"
  else
    read -r -s -p "Package key password: " PASSWORD
    echo
  fi
fi

msg "Creating boot OTA update pkg"
create_pkg "${PKGFILE}-boot.pkg" "$BOOT_PACKAGING_CANDIDATES"

msg "Creating full OTA update pkg"
create_pkg "${PKGFILE}-full.pkg" "$FULL_PACKAGING_CANDIDATES"

msg "Creating rootfs-only OTA update pkg"
create_pkg "${PKGFILE}-rootfs.pkg" "$MINI_PACKAGING_CANDIDATES"
