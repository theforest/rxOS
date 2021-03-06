#!/bin/sh
#
# This script programs the CHIP's NAND flash using sunxi-tools' `fel` utiltiy,
# and U-Boot itself.
# The following tools must be present on the system:
#
# - fel (sunxi-tools)
#
# The end result is the following flash layout:
#
# ========  ========  ============  ====================================
# mtdpart   size MB   name          description
# --------  --------  ------------  ------------------------------------
# 0         4         spl           Master SPL binary
# 1         4         spl-backup    Backup SPL binary
# 3         4         uboot         U-Boot binary
# 4         4         env           U-Boot environment
# 5         400       swap          (reserved)
# 6         -         UBI           Partition that stores ubi volumes.
# ========  ========  ============  ====================================
#
# The flashing works roughly like this:
#
# CHIP is put into FEL mode by jumping the FEL pin (3rd on U14L) to ground
# (first or last on U14L) during power-on. This allows the user to execute
# arbitrary bare-metal code on the Allwinner CPU. The `fel` tool is used to
# execute the SPL generated by the build (sunxi-spl.bin), which activates the
# DRAM. Once DRAM is active, the payload can be uploaded.
#
# One of the files that are transferred to the board's memory is a specially
# crafted U-Boot script that performs the transfer of the payload from memory
# to NAND flash. After all payloads are transferred to DRAM, the U-Boot binary
# in the memory is executed, which in turns runs the prepared U-Boot script.
#
# This file is part of rxOS.
# rxOS is free sofware licensed under the
# GNU GPL version 3 or any later version.
#
# (c) 2016 Outernet Inc
# Some rights reserved.

set -e

SCRIPTDIR="$(dirname "$0")"

# Prefer host dirs
HOST_DIR="$SCRIPTDIR/../out/host"
if [ -d "$HOST_DIR" ]; then
  export PATH="$HOST_DIR/usr/bin:$HOST_DIR/usr/sbin:$PATH"
fi

# Relevant paths
BINARIES_DIR="$(pwd)"
TMPDIR=

# Execution parameters
CHIP_DEVID="0525:a4a7"
FASTBOOT_ID="0x1f3a"
START="$(date '+%s')"
KEEP_TMPDIR=n

# Memory locations
SPL_ADDR1=0x43200000
SPL_ADDR2=0x43a00000
UBOOT_ADDR=0x4a000000
#UBOOT_ENV_ADDR=0x4b000000
UBOOT_SCRIPT_ADDR=0x43100000
EMPTY_UBIFS_MEM_ADDR=0x4b000000
LINUX_UBIFS_MEM_ADDR=0x4e000000

# Command aliases
FEL="fel"

# Abort with an error message
abort() {
  local msg="$*"
  echo "ERROR: $msg"
  exit 1
}

# Print usage
usage() {
  cat <<EOF
Usage: $0 [-htkp] [-b PATH] [-D DEVID]

Options:
  -h  Show this message and exit
  -b  Location of the directory containing the images
      (defaults to current directory)
  -D  Select a particular device instead of auto-detecting

Parameters:
  PATH    Path containing the binaries and images
  DEVID   Device ID in <busid>:<devnum> format

This program is part of rxOS.
rxOS is free software licensed under the
GNU GPL version 3 or any later version.

(c) 2016 Outernet Inc
Some rights reserved.
EOF
}

# Check whether a command exists
has_command() {
  local command="$1"
  which "$command" > /dev/null 2>&1
}

# Check whether a device with specific device ID exists
has_dev() {
  local devid="$1"
  lsusb | grep -q "$devid" > /dev/null 2>&1
}

# Check that the specified path exists and abort if it does not.
check_file() {
  local path="$1"
  [ -f "$path" ] || abort "File not found: '$path'
Is the build finished?"
}

# Keep executing a specified command until it succeeds or times out
#
# Arguments:
#
#   pause:    pause duration in seconds
#   message:  message shown before the command executes
#   command:  command that checks status
#
# This function performs 30 loops before timing out. In each loop, it pauses
# for the number of seconds specified by the first argument.
#
# The command must be quoted.
with_timeout() {
  local pause="$1"
  local msg="$2"
  local cmd="$3"
  echo -n "${msg}..."
  for i in `seq 1 30`; do
    $cmd > /dev/null 2>&1 && echo "OK" && return 0
    sleep "$pause"
    echo -n "."
  done
  echo "TIMEOUT"
  return 1
}

# Wait for CHIP in FEL mode to connected
wait_for_fel() {
  with_timeout 1 "[$(timestamp)] .... Waiting for CHIP in FEL mode" "$FEL ver"
}

# Print the amount of time elapsed since script was started
timestamp() {
  local current
  current="$(date '+%s')"
  printf '%4.0f' "$(($current - $START))"
}

# Print a section message
msg() {
  local msg="$1"
  echo "[$(timestamp)] ===> $msg"
}

# Print a subjection message
submsg() {
  local msg="$1"
  echo "[$(timestamp)] .... $msg"
}

###############################################################################
# SHOW STARTS HERE
###############################################################################

# Parse the command line options
while getopts "htkb:pND:E" opt; do
  case $opt in
    h)
      usage
      exit 0
      ;;
    b)
      BINARIES_DIR="$OPTARG"
      ;;
    D)
      has_command udevadm || abort "-D option requires udev"
      BUSNUM="$(echo "$OPTARG" | cut -d: -f1)"
      DEVNUM="$(echo "$OPTARG" | cut -d: -f2)"
      BUSNUM_CLEAN="$(echo "$BUSNUM" | sed 's/^0*//')"
      DEVNUM_CLEAN="$(echo "$DEVNUM" | sed 's/^0*//')"
      FEL="$FEL -d ${BUSNUM_CLEAN}:${DEVNUM_CLEAN}"
      BUSNUM="$(echo "$OPTARG" | cut -d: -f1)"
      DEVNUM="$(echo "$OPTARG" | cut -d: -f2)"
      DEVNAME="/dev/bus/usb/$BUSNUM/$DEVNUM"
      SYSPATH="$(udevadm info "$DEVNAME" | grep "P:" | awk '{print $2}')"
      PORT="usb:${SYSPATH##*/}"
      FASTBOOT="$FASTBOOT -s $PORT"
      echo "Using device $DEVNAME on port $PORT"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      echo
      usage
      exit 1
      ;;
  esac
done

# Source files
SPL="$BINARIES_DIR/sunxi-spl.bin"
SPL_ECC="$BINARIES_DIR/sunxi-spl-with-ecc.bin"
UBOOT="$BINARIES_DIR/uboot.bin"
UBOOT_SCR="$BINARIES_DIR/uboot.scr"
LINUX_UBIFS="$BINARIES_DIR/linux.ubifs"
EMPTY_UBIFS="$BINARIES_DIR/empty.ubifs"

# Check prereqisites
has_command fel || abort "Missing command 'fel'
Please install https://github.com/NextThingCo/sunxi-tools"

# Check that sources exist
check_file "$SPL"
check_file "${SPL_ECC}.1664"
check_file "${SPL_ECC}.1280"
check_file "$UBOOT"
check_file "$UBOOT_SCR"
check_file "$LINUX_UBIFS"
check_file "$EMPTY_UBIFS"


###############################################################################
# Uploading
###############################################################################

# Wait for chip in FEL mode to become available
wait_for_fel || abort "Unable to find CHIP in FEL mode"

submsg "Executing SPL"
$FEL spl "$SPL" || abort "Failed to execute SPL"

sleep 1

submsg "Uploading SPL 1664"
$FEL write "$SPL_ADDR1" "${SPL_ECC}.1664"

submsg "Uploading SPL 1280"
$FEL write "$SPL_ADDR2" "${SPL_ECC}.1280"

submsg "Uploading U-Boot"
$FEL write "$UBOOT_ADDR" "$UBOOT"

submsg "Uploading U-Boot script"
$FEL write "$UBOOT_SCRIPT_ADDR" "$UBOOT_SCR"

submsg "Uploading linux ubifs"
$FEL write "$EMPTY_UBIFS_MEM_ADDR" "$EMPTY_UBIFS"
$FEL write "$LINUX_UBIFS_MEM_ADDR" "$LINUX_UBIFS"

###############################################################################
# Executing flash
###############################################################################

msg "Executing flash"
$FEL exe "$UBOOT_ADDR"

cat <<EOF

!!! DO NOT DISCONNECT JUST YET. !!!

Your CHIP is now flashed. It will now boot and prepare the system.
Status LED will start blinking when it's ready. Only _then_ is it safe to
disconnect.

Please be patient. This can take 5-6 minutes.

EOF
