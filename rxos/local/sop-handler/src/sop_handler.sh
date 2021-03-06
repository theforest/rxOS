#!/bin/sh

# (C) 2016 Outernet Inc

set -euf
renice -n 20

SOP_FILE="$1"

sopmpt="/tmp/sopmpt" # sop mount point

tmploc_parent="/mnt/downloads/.soptmp"
[ -d "$tmploc_parent" ] || mkdir -p "$tmploc_parent"
tmploc=$(mktemp -d -p "$tmploc_parent" )

# manifest is formatted like this:
# install_method filename installparam1 installparam2 ...

# example manifest:
# part_cp zImage /boot
# part_cp sun5i-r8-chip.dtb /boot
# mtd_nandwrite uboot.bin uboot
# part_cp sunxi-spl-with-ecc.bin /boot
# part_cp rootfs.tar /boot
# sop_store_key

clean_exit() {
    rm -rf "$tmploc_parent"
    echo "Exit with errors"
    exit $1
}

sign_verify() {
    src_sop=$(basename "$SOP_FILE")
    extract_compressed_fs "$SOP_FILE" "$tmploc/$src_sop"
    tail -c 64 "$tmploc/$src_sop" >  "$tmploc/${src_sop}.sig"
    head -c -64 "$tmploc/$src_sop" | sha1sum | head -c 40 >> "$tmploc/${src_sop}.sig"
    if tweetnacl-verify %SOPSIGNPUBKEY% "$tmploc/${src_sop}.sig" - > /dev/null
    then
        echo SOP verified
    else
        echo SOP failed verification
        clean_exit 1
    fi
    rm -f "$tmploc/$src_sop" "$tmploc/${src_sop}.sig"
}

sop_validate() {
    sign_verify
}

part_cp() {
    loc="$2"
    fn="$1"
    partmode=$(mount | grep "$loc" | tr '(' , | cut -d , -f 2)
    [ "$partmode" = "ro" ] && mount -o remount,rw "$loc"
    cp "$sopmpt/images/$fn" "$loc"/"$fn"
    sync; sync; sync;
    [ "$partmode" = "ro" ] && mount -o remount,ro "$loc"
    echo
}

free_space() {
    part="$1"
    echo $(( $(df -m "$part" | tail -n 1 | sed 's/  */ /g' | cut -d " " -f 4) * 1024 * 1024))
}

mtd_nandwrite() {
    part_name="$2"
    fn="$1"
    part_dev="/dev/$(cat /proc/mtd | grep $part_name | cut -d : -f 1 | head -n 1 )"
    flash_erase "$part_dev" 0 0
    nandwrite -p "$part_dev" "$sopmpt/images/$fn"
}

sop_store_key() {
    loc="/boot"
    fn="$SOP_FILE"
    partmode=$(mount | grep "$loc" | tr '(' , | cut -d , -f 2)
    [ "$partmode" = "ro" ] && mount -o remount,rw "$loc"
    fsize=$(stat -c %s "$fn")
    base_fn="$(basename $fn)"
    stored_fn="${base_fn/.sop/.ksop}"
    cp "$fn" "$loc/$stored_fn"
    sync; sync; sync;
    [ "$partmode" = "ro" ] && mount -o remount,ro "$loc"
    echo
}

sop_store_dlt() {
    loc="/boot"
    fn="$SOP_FILE"
    partmode=$(mount | grep "$loc" | tr '(' , | cut -d , -f 2)
    [ "$partmode" = "ro" ] && mount -o remount,rw "$loc"
    fsize=$(stat -c %s "$fn")
    base_fn="$(basename $fn)"
    cp "$fn" "$loc/$base_fn"
    sync; sync; sync;
    [ "$partmode" = "ro" ] && mount -o remount,ro "$loc"
    echo
}

conf_clean() {
    find /mnt/conf -type f | grep -v skylark_config | xargs -r -I {} rm -rf "{}"
}

factory_reset() {
    rm -rf /mnt/conf
}

psop_apply() {
    loc="/boot"
    #psops are named: prefix.stamp.to.stamp.psop
    prefix=$(basename "$SOP_FILE" | cut -d . -f 1)
    src_sop_stamp=$(basename "$SOP_FILE" | cut -d . -f 2)
    src_sop="$prefix$src_sop_stamp.sop"
    src_ksop="$prefix$src_sop_stamp.ksop"
    dest_sop_stamp=$(basename "$SOP_FILE" | cut -d . -f 4)
    dest_sop="$prefix$dest_sop_stamp.sop"

    if [ "$src_sop_stamp" -ge "$dest_sop_stamp" ]
    then
        echo "update is same stamp or older than current images. rejecting."
        clean_exit 1
    fi

    if [ -f "/boot/$dest_sop" ]
    then
        echo "update is same stamp or older than current images. rejecting."
        clean_exit 1
    fi

    if [ -f "$loc/$src_sop" ]
    then
        src_sop="$src_sop"
    fi

    if [ -f "$loc/$src_ksop" ]
    then
        src_sop="$src_ksop"
    fi

    if [ -f "$loc/$src_sop" ]
    then
        echo "Applying PSOP to $loc/$src_sop"
        # extract src sop to temp location
        extract_compressed_fs "$loc/$src_sop" "$tmploc/$src_sop"
        if [ ! -f "$tmploc/$src_sop" ]
        then
            echo "Extracing of src sop $src_sop failed"
            clean_exit 1
        fi
        bspatch "$tmploc/$src_sop" "$tmploc/$dest_sop.uncmpr" "$SOP_FILE"
        if [ -f "$tmploc/$dest_sop.uncmpr" ]
        then
            rm -f "$tmploc/$src_sop"
            echo "Patched."
            create_compressed_fs -q -B 64K  "$tmploc/$dest_sop.uncmpr" "$tmploc/$dest_sop"
            if [ -f "$tmploc/$dest_sop" ]
            then
                echo "Created compressed sop"
                rm -f "$tmploc/$dest_sop.uncmpr"
            else
                echo "failed to create compressed sop"
                clean_exit 1
            fi
            echo "Activating patched SOP"
            mv "$tmploc/$dest_sop" $(dirname "$SOP_FILE")/${dest_sop}
        else
            echo "Patching failed"
	        clean_exit 1
        fi
    else
	    echo "Could not find source SOP $loc/$src_sop to apply partial sop $SOP_FILE"
	    clean_exit 1
    fi
    echo "Cleaning up $SOP_FILE"
    rm -f "$SOP_FILE"
}

sop_apply() {
    base_sop=$(basename  "$SOP_FILE")
    if [ -f "/boot/$base_sop" ]
    then
        echo "update is same stamp or older than current images. rejecting."
        clean_exit 1
    fi

    sop_validate
    [ -d "$sopmpt" ] && rm -rf "$sopmpt"
    mkdir "$sopmpt"
    losetup /dev/cloop1 "$SOP_FILE"
    mount -o ro /dev/cloop1 "$sopmpt"
    source "${sopmpt}/images/manifest"
    umount "$sopmpt"
    rm "$SOP_FILE"
    rmdir "$sopmpt"
}

xzsop_apply() {
    base_fn="$(basename ${SOP_FILE})"
    unxz_sop_fn="$tmploc/${base_fn/.xz}"
    unxz -c "$SOP_FILE" > "$unxz_sop_fn"
    rm "$SOP_FILE"
    mv  "$unxz_sop_fn" "$(dirname $SOP_FILE)"
}

if [ ! -f "$SOP_FILE" ]
then
    exit 0
fi

reboot=""

if echo "$SOP_FILE" | grep -q -v "skylark-${RXOS_SUBPLATFORM}"
then
    echo "ignoring update as subplatform doesnt match"
    rm "$SOP_FILE"
    exit 0
fi

if [ $(expr "$SOP_FILE" : ".*\.psop$") -gt 0 ]
then
    psop_apply
elif [ $(expr "$SOP_FILE" : ".*\.xz.sop$") -gt 0 ]
then
    xzsop_apply
else
    sop_apply
    reboot="yes"
fi

rm -rf "$tmploc_parent"

sync; sync; sync

if [ -n "$reboot" ]
then
    echo rebooting in 60 seconds as update applied
    sleep 60
    reboot
fi
