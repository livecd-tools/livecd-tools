#!/bin/bash
# Transfer a Live image so that it's bootable off of a USB/SD device.
# Copyright 2007  Red Hat, Inc.
# Jeremy Katz <katzj@redhat.com>
#
# overlay/persistence enhancements by Douglas McClendon <dmc@viros.org>
# GPT+MBR hybrid enhancements by Stewart Adam <s.adam@diffingo.com>
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Library General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.


export PATH=/sbin:/usr/sbin:$PATH

usage() {
    echo "$0 [--timeout <time>] [--totaltimeout <time>] [--format] [--reset-mbr] [--noverify] [--overlay-size-mb <size>] [--home-size-mb <size>] [--unencrypted-home] [--skipcopy] [--efi] <source> <target device>"
    exit 1
}

cleanup() {
    sleep 2
    [ -d "$SRCMNT" ] && umount $SRCMNT && rmdir $SRCMNT
    [ -d "$TGTMNT" ] && umount $TGTMNT && rmdir $TGTMNT
}

exitclean() {
    echo "Cleaning up to exit..."
    cleanup
    exit 1
}

isdevloop() {
    [ x"${1#/dev/loop}" != x"$1" ]
}

getdisk() {
    DEV=$1

    if isdevloop "$DEV"; then
        device="$DEV"
        return
    fi

    p=$(udevadm info -q path -n $DEV)
    if [ -e /sys/$p/device ]; then
        device=$(basename /sys/$p)
    else
        device=$(basename $(readlink -f /sys/$p/../))
    fi
    if [ ! -e /sys/block/$device -o ! -e /dev/$device ]; then
        echo "Error finding block device of $DEV.  Aborting!"
        exitclean
    fi

    device="/dev/$device"
    # FIXME: weird dev names could mess this up I guess
    p=/dev/$(basename $p)
    partnum=${p##$device}
}

getpartition() {
    DEV=$1
    pa=$( < /proc/partitions )
    pa=${pa##*$DEV}
    partnum=${pa%% *}
}

resetMBR() {
    if isdevloop "$DEV"; then
        return
    fi
    getdisk $1
    # if efi, we need to use the hybrid MBR
    if [ -n "$efi" ]; then
        if [ -f /usr/lib/syslinux/gptmbr.bin ]; then
            gptmbr='/usr/lib/syslinux/gptmbr.bin'
        elif [ -f /usr/share/syslinux/gptmbr.bin ]; then
            gptmbr='/usr/share/syslinux/gptmbr.bin'
        else
            echo "Could not find gptmbr.bin (syslinux)"
            exitclean
        fi
        # our magic number is LBA-2, offset 16 - (512+512+16)/$bs
        dd if=$device bs=16 skip=65 count=1 | cat $gptmbr - > $device
    else
        if [ -f /usr/lib/syslinux/mbr.bin ]; then
            cat /usr/lib/syslinux/mbr.bin > $device
        elif [ -f /usr/share/syslinux/mbr.bin ]; then
            cat /usr/share/syslinux/mbr.bin > $device
        else
            echo "Could not find mbr.bin (syslinux)"
            exitclean
        fi
    fi
}

checkMBR() {
    if isdevloop "$DEV"; then
        return 0
    fi
    getdisk $1

    bs=$(mktemp /tmp/bs.XXXXXX)
    dd if=$device of=$bs bs=512 count=1 2>/dev/null || exit 2

    mbrword=$(hexdump -n 2 $bs |head -n 1|awk {'print $2;'})
    rm -f $bs
    if [ "$mbrword" = "0000" ]; then
        echo "MBR appears to be blank."
        echo "Do you want to replace the MBR on this device?"
        echo "Press Enter to continue or ctrl-c to abort"
        read
        resetMBR $1
    fi

    return 0
}

checkPartActive() {
    dev=$1
    getdisk $dev

    # if we're installing to whole-disk and not a partition, then we
    # don't need to worry about being active
    if [ "$dev" = "$device" ]; then
        return
    fi
    if isdevloop "$DEV"; then
        return
    fi

    if [ "$(/sbin/fdisk -l $device 2>/dev/null |grep $dev |awk {'print $2;'})" != "*" ]; then
        echo "Partition isn't marked bootable!"
        echo "You can mark the partition as bootable with "
        echo "    # /sbin/parted $device"
        echo "    (parted) toggle N boot"
        echo "    (parted) quit"
        exitclean
    fi
}

checkLVM() {
    dev=$1

    if [ -x /sbin/pvs -a \
        "$(/sbin/pvs -o vg_name --noheadings $dev* 2>/dev/null)" ]; then
        echo "Device, $dev, contains a volume group and cannot be formated!"
        echo "You can remove the volume group using vgremove."
        exitclean
    fi
    return 0
}

createGPTLayout() {
    dev=$1
    getdisk $dev

    echo "WARNING: THIS WILL DESTROY ANY DATA ON $device!!!"
    echo "Press Enter to continue or ctrl-c to abort"
    read
    umount ${device}* &> /dev/null
    /sbin/parted --script $device mklabel gpt
    partinfo=$(LC_ALL=C /sbin/parted --script -m $device "unit b print" |grep ^$device:)
    size=$(echo $partinfo |cut -d : -f 2 |sed -e 's/B$//')
    /sbin/parted --script $device unit b mkpart '"EFI System Partition"' fat32 1048576 $(($size - 1048576)) set 1 boot on
    # Sometimes automount can be _really_ annoying.
    echo "Waiting for devices to settle..."
    /sbin/udevadm settle
    sleep 5
    getpartition ${device#/dev/}
    TGTDEV=${device}${partnum}
    umount $TGTDEV &> /dev/null
    /sbin/mkdosfs -n LIVE $TGTDEV
    TGTLABEL="UUID=$(/sbin/blkid -s UUID -o value $TGTDEV)"
}

createMSDOSLayout() {
    dev=$1
    getdisk $dev

    echo "WARNING: THIS WILL DESTROY ANY DATA ON $device!!!"
    echo "Press Enter to continue or ctrl-c to abort"
    read
    umount ${device}* &> /dev/null
    /sbin/parted --script $device mklabel msdos
    partinfo=$(LC_ALL=C /sbin/parted --script -m $device "unit b print" |grep ^$device:)
    size=$(echo $partinfo |cut -d : -f 2 |sed -e 's/B$//')
    /sbin/parted --script $device unit b mkpart primary fat32 1048576 $(($size - 1048576)) set 1 boot on
    # Sometimes automount can be _really_ annoying.
    echo "Waiting for devices to settle..."
    /sbin/udevadm settle
    sleep 5
    if ! isdevloop "$DEV"; then
        getpartition ${device#/dev/}
        TGTDEV=${device}${partnum}
    else
        TGTDEV=${device}
    fi
    umount $TGTDEV &> /dev/null
    /sbin/mkdosfs -n LIVE $TGTDEV
    TGTLABEL="UUID=$(/sbin/blkid -s UUID -o value $TGTDEV)"
}

createEXTFSLayout() {
    dev=$1
    getdisk $dev

    echo "WARNING: THIS WILL DESTROY ANY DATA ON $device!!!"
    echo "Press Enter to continue or ctrl-c to abort"
    read
    umount ${device}* &> /dev/null
    /sbin/parted --script $device mklabel msdos
    partinfo=$(LC_ALL=C /sbin/parted --script -m $device "unit b print" |grep ^$device:)
    size=$(echo $partinfo |cut -d : -f 2 |sed -e 's/B$//')
    /sbin/parted --script $device unit b mkpart primary ext2 1048576 $(($size - 1048576)) set 1 boot on
    # Sometimes automount can be _really_ annoying.
    echo "Waiting for devices to settle..."
    /sbin/udevadm settle
    sleep 5
    getpartition ${device#/dev/}
    TGTDEV=${device}${partnum}
    umount $TGTDEV &> /dev/null
    /sbin/mkfs.ext4 -L LIVE $TGTDEV
    TGTLABEL="UUID=$(/sbin/blkid -s UUID -o value $TGTDEV)"
}

checkGPT() {
    dev=$1
    getdisk $dev

    if [ "$(/sbin/fdisk -l $device 2>/dev/null |grep -c GPT)" -eq "0" ]; then
        echo "EFI boot requires a GPT partition table."
        echo "This can be done manually or you can run with --format"
        exitclean
    fi

    partinfo=$(LC_ALL=C /sbin/parted --script -m $device "print" |grep ^$partnum:)
    volname=$(echo $partinfo |cut -d : -f 6)
    flags=$(echo $partinfo |cut -d : -f 7)
    if [ "$volname" != "EFI System Partition" ]; then
        echo "Partition name must be 'EFI System Partition'"
        echo "This can be set in parted or you can run with --reset-mbr"
        exitclean
    fi
    if [ "$(echo $flags |grep -c boot)" = "0" ]; then
        echo "Partition isn't marked bootable!"
        echo "You can mark the partition as bootable with "
        echo "    # /sbin/parted $device"
        echo "    (parted) toggle N boot"
        echo "    (parted) quit"
        exitclean
    fi
}

checkFilesystem() {
    dev=$1

    TGTFS=$(/sbin/blkid -s TYPE -o value $dev)
    if [ "$TGTFS" != "vfat" ] && [ "$TGTFS" != "msdos" ]; then
        if [ "$TGTFS" != "ext2" ] && [ "$TGTFS" != "ext3" ] && [ "$TGTFS" != "ext4" ] && [ "$TGTFS" != "btrfs" ]; then
            echo "Target filesystem must be vfat, ext[234] or btrfs"
            exitclean
        fi
    fi


    TGTLABEL=$(/sbin/blkid -s UUID -o value $dev)
    if [ -n "$TGTLABEL" ]; then
        TGTLABEL="UUID=$TGTLABEL"
    else
        TGTLABEL=$(/sbin/blkid -s LABEL -o value $dev)
        if [ -n "$TGTLABEL" ]; then
            TGTLABEL="LABEL=$TGTLABEL"
        else
            echo "Need to have a filesystem label or UUID for your target device"
            if [ "$TGTFS" = "vfat" -o "$TGTFS" = "msdos" ]; then
                echo "Label can be set with /sbin/dosfslabel"
            elif [ "$TGTFS" = "ext2" -o "$TGTFS" = "ext3" -o "$TGTFS" = "ext4" ]; then
                echo "Label can be set with /sbin/e2label"
            elif [ "$TGTFS" = "btrfs" ]; then
                echo "Eventually you'll be able to use /sbin/btrfs filesystem label to add a label."
            fi
            exitclean
        fi
    fi

    if [ "$TGTFS" = "vfat" -o "$TGTFS" = "msdos" ]; then
        mountopts="-o shortname=winnt,umask=0077"
    fi
}

checkSyslinuxVersion() {
    if [ ! -x /usr/bin/syslinux ]; then
        echo "You need to have syslinux installed to run this script"
        exit 1
    fi
    if ! syslinux 2>&1 | grep -qe -d; then
        SYSLINUXPATH=""
    elif [ -n "$multi" ]; then
        SYSLINUXPATH="$LIVEOS/syslinux"
    else
        SYSLINUXPATH="syslinux"
    fi
}

checkMounted() {
    dev=$1
    if grep -q "^$dev " /proc/mounts ; then
        echo "$dev is mounted, please unmount for safety"
        exitclean
    fi
    if grep -q "^$dev " /proc/swaps; then
        echo "$dev is in use as a swap device, please disable swap"
        exitclean
    fi
}

checkint() {
    if ! test $1 -gt 0 2>/dev/null ; then
        usage
    fi
}

if [ $(id -u) != 0 ]; then
    echo "You need to be root to run this script"
    exit 1
fi

detectsrctype() {
    if [[ -e $SRCMNT/$LIVEOS/squashfs.img ]]; then
        srctype=live
        return
    fi
    if [ -e $SRCMNT/images/install.img -o $SRCMNT/isolinux/initrd.img ]; then
        imgtype=install
        if [ -e $SRCMNT/Packages ]; then
            srctype=installer
        else
            srctype=netinst
        fi
        if [ ! -e $SRCMNT/images/install.img ]; then
            echo "$SRC uses initrd.img w/o install.img"
            imgtype=initrd
        fi
        return
    fi
    echo "ERROR: $SRC does not appear to be a Live image or DVD installer."
    exitclean
}

cp_p() {
    strace -q -ewrite cp -- "${1}" "${2}" 2>&1 \
        | awk '{
        count += $NF
        if (count % 10 == 0) {
            percent = count / total_size * 100
            printf "%3d%% [", percent
            for (i=0;i<=percent;i++)
                printf "="
                printf ">"
            for (i=percent;i<100;i++)
                printf " "
                printf "]\r"
            }
        }
        END { print "" }' total_size=$(stat -c '%s' "${1}") count=0
}

copyFile() {
    if [ -x /usr/bin/gvfs-copy ]; then
        gvfs-copy -p "$1" "$2"
        return
    fi
    if [ -x /usr/bin/strace -a -x /bin/awk ]; then
        cp_p "$1" "$2"
        return
    fi
    cp "$1" "$2"
}

cryptedhome=1
keephome=1
homesizemb=0
swapsizemb=0
overlaysizemb=0
srctype=
imgtype=
LIVEOS=LiveOS

HOMEFILE="home.img"
while [ $# -gt 2 ]; do
    case $1 in
        --overlay-size-mb)
            checkint $2
            overlaysizemb=$2
            shift
            ;;
        --home-size-mb)
            checkint $2
            homesizemb=$2
            shift
            ;;
        --swap-size-mb)
            checkint $2
            swapsizemb=$2
            shift
            ;;
        --crypted-home)
            cryptedhome=1
            ;;
        --unencrypted-home)
            cryptedhome=""
            ;;
        --delete-home)
            keephome=""
            ;;
        --noverify)
            noverify=1
            ;;
        --reset-mbr|--resetmbr)
            resetmbr=1
            ;;
        --efi|--mactel)
            efi=1
            ;;
        --format)
            format=1
            ;;
        --skipcopy)
            skipcopy=1
            ;;
        --xo)
            xo=1
            skipcompress=1
            ;;
        --xo-no-home)
            xonohome=1
            ;;
        --compress)
            skipcompress=""
            ;;
        --skipcompress)
            skipcompress=1
            ;;
        --extra-kernel-args)
            kernelargs=$2
            shift
            ;;
        --force)
            force=1
            ;;
        --livedir)
            LIVEOS=$2
            shift
            ;;
        --multi)
            multi=1
            ;;
        --timeout)
            checkint $2
            timeout=$2
            shift
            ;;
        --totaltimeout)
            checkint $2
            totaltimeout=$2
            shift
            ;;
        *)
            echo "invalid arg -- $1"
            usage
            ;;
    esac
    shift
done

SRC=$(readlink -f "$1")
TGTDEV=$(readlink -f "$2")

if [ -z "$SRC" ]; then
    usage
fi

if [ ! -b "$SRC" -a ! -f "$SRC" ]; then
    usage
fi

# FIXME: If --format is given, we shouldn't care and just use /dev/foo1
if [ -z "$TGTDEV" -o ! -b "$TGTDEV" ]; then
    usage
fi

if [ -z "$noverify" ]; then
    # verify the image
    echo "Verifying image..."
    checkisomd5 --verbose "$SRC"
    if [ $? -ne 0 ]; then
        echo "Are you SURE you want to continue?"
        echo "Press Enter to continue or ctrl-c to abort"
        read
    fi
fi

#checkFilesystem $TGTDEV
# do some basic sanity checks.
checkMounted $TGTDEV
if [ -n "$format" -a -z "$skipcopy" ]; then
    checkLVM $TGTDEV
    # checks for a valid filesystem
    if [ -n "$efi" ]; then
        createGPTLayout $TGTDEV
    elif [ "$TGTFS" == "vfat" -o "$TGTFS" == "msdos" ]; then
        createMSDOSLayout $TGTDEV
    else
        createEXTFSLayout $TGTDEV
    fi
fi

checkFilesystem $TGTDEV
if [ -n "$efi" ]; then
    checkGPT $TGTDEV
fi

checkSyslinuxVersion
# Because we can't set boot flag for EFI Protective on msdos partition tables
[ -z "$efi" ] && checkPartActive $TGTDEV
[ -n "$resetmbr" ] && resetMBR $TGTDEV
checkMBR $TGTDEV


if [ "$overlaysizemb" -gt 0 -a "$TGTFS" = "vfat" ]; then
    if [ "$overlaysizemb" -gt 2047 ]; then
        echo "Can't have an overlay of 2048MB or greater on VFAT"
        exitclean
    fi
fi

if [ "$homesizemb" -gt 0 -a "$TGTFS" = "vfat" ]; then
    if [ "$homesizemb" -gt 2047 ]; then
        echo "Can't have a home overlay greater than 2048MB on VFAT"
        exitclean
    fi
fi

if [ "$swapsizemb" -gt 0 -a "$TGTFS" = "vfat" ]; then
    if [ "$swapsizemb" -gt 2047 ]; then
        echo "Can't have a swap file greater than 2048MB on VFAT"
        exitclean
    fi
fi

# FIXME: would be better if we had better mountpoints
SRCMNT=$(mktemp -d /media/srctmp.XXXXXX)
mount -o loop,ro "$SRC" $SRCMNT || exitclean
TGTMNT=$(mktemp -d /media/tgttmp.XXXXXX)
mount $mountopts $TGTDEV $TGTMNT || exitclean

trap exitclean SIGINT SIGTERM

detectsrctype

if [ -f "$TGTMNT/$LIVEOS/$HOMEFILE" -a -n "$keephome" -a "$homesizemb" -gt 0 ]; then
    echo "ERROR: Requested keeping existing /home and specified a size for /home"
    echo "Please either don't specify a size or specify --delete-home"
    exitclean
fi

if [ -n "$efi" -a ! -d $SRCMNT/EFI/boot ]; then
    echo "ERROR: This live image does not support EFI booting"
    exitclean
fi

# let's try to make sure there's enough room on the target device
if [[ -d $TGTMNT/$LIVEOS ]]; then
    tbd=($(du -B 1M $TGTMNT/$LIVEOS))
    if [[ -s $TGTMNT/$LIVEOS/$HOMEFILE ]] && [[ -n $keephome ]]; then
        homesize=($(du -B 1M $TGTMNT/$LIVEOS/$HOMEFILE))
        ((tbd -= homesize))
    fi
else
    tbd=0
fi

if [[ live == $srctype ]]; then
   targets="$TGTMNT/$SYSLINUXPATH"
   [[ -n $efi ]] && targets+=" $TGTMNT/EFI/boot"
   [[ -n $xo ]] && targets+=" $TGTMNT/boot/olpc.fth"
   duTable=($(du -c -B 1M $targets 2> /dev/null))
   ((tbd += ${duTable[*]: -2:1}))
fi

if [[ -n $skipcompress ]] && [[ -s $SRCMNT/$LIVEOS/squashfs.img ]]; then
    if mount -o loop $SRCMNT/$LIVEOS/squashfs.img $SRCMNT; then
        livesize=($(du -B 1M --apparent-size $SRCMNT/LiveOS/ext3fs.img))
        umount $SRCMNT
    else
        echo "WARNING: --skipcompress or --xo was specified but the
        currently-running kernel can not mount the SquashFS from the source
        file to extract it. Instead, the compressed SquashFS will be copied
        to the target device."
        skipcompress=""
    fi
fi
if [[ live == $srctype ]]; then
    thisScriptpath=$(readlink -f "$0")
    sources="$SRCMNT/$LIVEOS/ext3fs.img $SRCMNT/$LIVEOS/osmin.img"
    [[ -z $skipcompress ]] && sources+=" $SRCMNT/$LIVEOS/squashfs.img"
    sources+=" $SRCMNT/isolinux $SRCMNT/syslinux"
    [[ -n $efi ]] && sources+=" $SRCMNT/EFI/boot"
    duTable=($(du -c -B 1M "$thisScriptpath" $sources 2> /dev/null))
    ((livesize += ${duTable[*]: -2:1}))
fi

freespace=($(df -B 1M --total $TGTDEV))
freespace=${freespace[*]: -2:1}

if [[ live == $srctype ]]; then
    tba=$((overlaysizemb + homesizemb + livesize + swapsizemb))
    if ((tba > freespace + tbd)); then
        needed=$((tba - freespace - tbd))
        printf "\n  The live image + overlay, home, & swap space, if requested,
        \r  will NOT fit in the space available on the target device.\n
        \r  + Size of live image: %10s  MiB\n" $livesize
        (($overlaysizemb > 0)) && \
            printf "  + Overlay size: %16s\n" $overlaysizemb
        (($homesizemb > 0)) && \
            printf "  + Home directory size: %9s\n" $homesizemb
        (($swapsizemb > 0)) && \
            printf "  + Swap overlay size: %11s\n" $swapsizemb
        printf "  = Total requested space:  %6s  MiB\n" $tba
        printf "  - Space available:  %12s\n" $((freespace + tbd))
        printf "    ==============================\n"
        printf "    Space needed:  %15s  MiB\n\n" $needed
        printf "  To fit the installation on this device,
        \r  free space on the target, or decrease the
        \r  requested size total by:  %6s  MiB\n\n" $needed
        exitclean
    fi
fi

# Verify available space for DVD installer
if [ "$srctype" = "installer" ]; then
    srcsize=$(du -s -B 1M $SRC | awk {'print $1;'})
    if [ "$imgtype" = "install" ]; then
        imgpath=images/install.img
    else
        imgpath=isolinux/initrd.img
    fi
    installimgsize=$(du -s -B 1M $SRCMNT/$imgpath | awk {'print $1;'})

    tbd=0
    if [ -e $TGTMNT/$imgpath ]; then
        tbd=$(du -s -B 1M $TGTMNT/$imgpath | awk {'print $1;'})
    fi
    if [ -e $TGTMNT/$(basename $SRC) ]; then
        tbd=$(($tbd + $(du -s -B 1M $TGTMNT/$(basename $SRC) | awk {'print $1;'})))
    fi
    echo "Size of DVD image: $srcsize"
    echo "Size of $imgpath: $installimgsize"
    echo "Available space: $((freespace + tbd))"
    if (( ((srcsize + installimgsize)) > ((freespace + tbd)) )); then
        echo "ERROR: Unable to fit DVD image + install.img on available space on the target device."
        exitclean
    fi
fi

if [ -z "$skipcopy" ] && [ "$srctype" = "live" ]; then
    if [ -d $TGTMNT/$LIVEOS -a -z "$force" ]; then
        echo "Already set up as live image."
        if [ -z "$keephome" -a -e $TGTMNT/$LIVEOS/$HOMEFILE ]; then
            echo "WARNING: Persistent /home will be deleted!!!"
            echo "Press Enter to continue or ctrl-c to abort"
            read
        else
            echo "Deleting old OS in fifteen seconds..."
            sleep 15

            [ -e "$TGTMNT/$LIVEOS/$HOMEFILE" -a -n "$keephome" ] && mv $TGTMNT/$LIVEOS/$HOMEFILE $TGTMNT/$HOMEFILE
        fi

        rm -rf $TGTMNT/$LIVEOS
    fi
fi

# Bootloader is always reconfigured, so keep these out of the if skipcopy stuff.
[ ! -d $TGTMNT/$SYSLINUXPATH ] && mkdir -p $TGTMNT/$SYSLINUXPATH
[ -n "$efi" -a ! -d $TGTMNT/EFI/boot ] && mkdir -p $TGTMNT/EFI/boot

# Live image copy
set -o pipefail
if [ "$srctype" = "live" -a -z "$skipcopy" ]; then
    echo "Copying live image to target device."
    [ ! -d $TGTMNT/$LIVEOS ] && mkdir $TGTMNT/$LIVEOS
    [ -n "$keephome" -a -f "$TGTMNT/$HOMEFILE" ] && mv $TGTMNT/$HOMEFILE $TGTMNT/$LIVEOS/$HOMEFILE
    if [ -n "$skipcompress" -a -f $SRCMNT/$LIVEOS/squashfs.img ]; then
        mount -o loop $SRCMNT/$LIVEOS/squashfs.img $SRCMNT || exitclean
        copyFile $SRCMNT/LiveOS/ext3fs.img $TGTMNT/$LIVEOS/ext3fs.img || {
            umount $SRCMNT ; exitclean ; }
        umount $SRCMNT
    elif [ -f $SRCMNT/$LIVEOS/squashfs.img ]; then
        copyFile $SRCMNT/$LIVEOS/squashfs.img $TGTMNT/$LIVEOS/squashfs.img || exitclean
    elif [ -f $SRCMNT/$LIVEOS/ext3fs.img ]; then
        copyFile $SRCMNT/$LIVEOS/ext3fs.img $TGTMNT/$LIVEOS/ext3fs.img || exitclean
    fi
    if [ -f $SRCMNT/$LIVEOS/osmin.img ]; then
        copyFile $SRCMNT/$LIVEOS/osmin.img $TGTMNT/$LIVEOS/osmin.img || exitclean
    fi
    sync
fi

# DVD installer copy
if [ \( "$srctype" = "installer" -o "$srctype" = "netinst" \) -a -z "$skipcopy" ]; then
    echo "Copying DVD image to target device."
    mkdir -p $TGTMNT/images/
    if [ "$imgtype" = "install" ]; then
        copyFile $SRCMNT/images/install.img $TGTMNT/images/install.img || exitclean
    fi
    if [ "$srctype" = "installer" ]; then
        cp $SRC $TGTMNT/
    fi
    sync
fi

# Adjust syslinux sources for replication of installed images
# between filesystem types.
if [[ -d $SRCMNT/isolinux/ ]]; then
    cp $SRCMNT/isolinux/* $TGTMNT/$SYSLINUXPATH
elif [[ -d $SRCMNT/syslinux/ ]]; then
    cp $SRCMNT/syslinux/* $TGTMNT/$SYSLINUXPATH
    if [[ -f $SRCMNT/syslinux/extlinux.conf ]]; then
        mv $TGTMNT/$SYSLINUXPATH/extlinux.conf \
            $TGTMNT/$SYSLINUXPATH/isolinux.cfg
    elif [[ -f $SRCMNT/syslinux/syslinux.cfg ]]; then
        mv $TGTMNT/$SYSLINUXPATH/syslinux.cfg $TGTMNT/$SYSLINUXPATH/isolinux.cfg
    fi
fi
BOOTCONFIG=$TGTMNT/$SYSLINUXPATH/isolinux.cfg
# Set this to nothing so sed doesn't care
BOOTCONFIG_EFI=
if [ -n "$efi" ]; then
    cp $SRCMNT/EFI/boot/* $TGTMNT/EFI/boot

    # this is a little ugly, but it gets the "interesting" named config file
    BOOTCONFIG_EFI=$TGTMNT/EFI/boot/boot?*.conf
    rm -f $TGTMNT/EFI/boot/grub.conf
fi

if [[ live == $srctype ]]; then
    # Copy this installer script.
    cp -fTp "$thisScriptpath" $TGTMNT/$LIVEOS/livecd-iso-to-disk &> /dev/null

    # When the source is an installed Live USB/SD image, restore the boot config
    # file to a base state before updating.
    if [[ -d $SRCMNT/syslinux/ ]]; then
        echo "Preparing boot config file."
        sed -i -e "s/root=live:[^ ]*/root=live:CDLABEL=name/"\
               -e "s/liveimg .* quiet/liveimg quiet/"\
                    $BOOTCONFIG $BOOTCONFIG_EFI
        sed -i -e "s/^timeout.*$/timeout\ 100/"\
               -e "/^totaltimeout.*$/d" $BOOTCONFIG
    fi
fi
echo "Updating boot config file"
# adjust label and fstype
if [ -n "$LANG" ]; then
    kernelargs="$kernelargs LANG=$LANG"
fi
sed -i -e "s/CDLABEL=[^ ]*/$TGTLABEL/" -e "s/rootfstype=[^ ]*/rootfstype=$TGTFS/" -e "s/LABEL=[^ ]*/$TGTLABEL/" $BOOTCONFIG  $BOOTCONFIG_EFI
if [ -n "$kernelargs" ]; then
    sed -i -e "s/liveimg/liveimg ${kernelargs}/" $BOOTCONFIG $BOOTCONFIG_EFI
fi
if [ "$LIVEOS" != "LiveOS" ]; then
    sed -i -e "s;liveimg;liveimg live_dir=$LIVEOS;" $BOOTCONFIG $BOOTCONFIG_EFI
fi

# DVD Installer
if [ "$srctype" = "installer" ]; then
    sed -i -e "s;initrd=initrd.img;initrd=initrd.img ${LANG:+LANG=$LANG} repo=hd:$TGTLABEL:/;g" $BOOTCONFIG $BOOTCONFIG_EFI
    sed -i -e "s;stage2=\S*;;g" $BOOTCONFIG $BOOTCONFIG_EFI
fi

# DVD Installer for netinst
if [ "$srctype" = "netinst" ]; then
    if [ "$imgtype" = "install" ]; then
        sed -i -e "s;stage2=\S*;stage2=hd:$TGTLABEL:/images/install.img;g" $BOOTCONFIG $BOOTCONFIG_EFI
    else
        # The initrd has everything, so no stage2
        sed -i -e "s;stage2=\S*;;g" $BOOTCONFIG $BOOTCONFIG_EFI
    fi
fi

# Adjust the boot timeouts
if [ -n "$timeout" ]; then
    sed -i -e "s/^timeout.*$/timeout\ $timeout/" $BOOTCONFIG
fi
if [ -n "$totaltimeout" ]; then
    sed -i -e "/^timeout.*$/a\totaltimeout\ $totaltimeout" $BOOTCONFIG
fi

# Use repo if the .iso has the repository on it, otherwise use stage2 which
# will default to using the network mirror
if [ -e "$SRCMNT/.discinfo" ]; then
    METHODSTR=repo
else
    METHODSTR=stage2
fi

if [ "$overlaysizemb" -gt 0 ]; then
    echo "Initializing persistent overlay file"
    OVERFILE="overlay-$( /sbin/blkid -s LABEL -o value $TGTDEV )-$( /sbin/blkid -s UUID -o value $TGTDEV )"
    if [ -z "$skipcopy" ]; then
        if [ "$TGTFS" = "vfat" ]; then
            # vfat can't handle sparse files
            dd if=/dev/zero of=$TGTMNT/$LIVEOS/$OVERFILE count=$overlaysizemb bs=1M
        else
            dd if=/dev/null of=$TGTMNT/$LIVEOS/$OVERFILE count=1 bs=1M seek=$overlaysizemb
        fi
    fi
    sed -i -e "s/liveimg/liveimg overlay=${TGTLABEL}/" $BOOTCONFIG $BOOTCONFIG_EFI
    sed -i -e "s/\ ro\ /\ rw\ /" $BOOTCONFIG  $BOOTCONFIG_EFI
fi

if [ "$swapsizemb" -gt 0 -a -z "$skipcopy" ]; then
    echo "Initializing swap file"
    dd if=/dev/zero of=$TGTMNT/$LIVEOS/swap.img count=$swapsizemb bs=1M
    mkswap -f $TGTMNT/$LIVEOS/swap.img
fi

if [ "$homesizemb" -gt 0 -a -z "$skipcopy" ]; then
    echo "Initializing persistent /home"
    homesource=/dev/zero
    [ -n "$cryptedhome" ] && homesource=/dev/urandom
    if [ "$TGTFS" = "vfat" ]; then
        # vfat can't handle sparse files
        dd if=${homesource} of=$TGTMNT/$LIVEOS/$HOMEFILE count=$homesizemb bs=1M
    else
        dd if=/dev/null of=$TGTMNT/$LIVEOS/$HOMEFILE count=1 bs=1M seek=$homesizemb
    fi
    if [ -n "$cryptedhome" ]; then
        loop=$(losetup -f)
        losetup $loop $TGTMNT/$LIVEOS/$HOMEFILE
        setupworked=1
        until [ ${setupworked} == 0 ]; do
            echo "Encrypting persistent /home"
            cryptsetup luksFormat -y -q $loop
            setupworked=$?
        done
        setupworked=1
        until [ ${setupworked} == 0 ]; do
            echo "Please enter the password again to unlock the device"
            cryptsetup luksOpen $loop EncHomeFoo
            setupworked=$?
        done
        mke2fs -j /dev/mapper/EncHomeFoo
        tune2fs -c0 -i0 -ouser_xattr,acl /dev/mapper/EncHomeFoo
        sleep 2
        cryptsetup luksClose EncHomeFoo
        losetup -d $loop
    else
        echo "Formatting unencrypted /home"
        mke2fs -F -j $TGTMNT/$LIVEOS/$HOMEFILE
        tune2fs -c0 -i0 -ouser_xattr,acl $TGTMNT/$LIVEOS/$HOMEFILE
    fi
fi

# create the forth files for booting on the XO if requested
# we'd do this unconditionally, but you have to have a kernel that will
# boot on the XO anyway.
if [ -n "$xo" ]; then
    echo "Setting up /boot/olpc.fth file"
    args=$(grep "^ *append" $TGTMNT/$SYSLINUXPATH/isolinux.cfg |head -n1 |sed -e 's/.*initrd=[^ ]*//')
    if [ -z "$xonohome" -a ! -f $TGTMNT/$LIVEOS/$HOMEFILE ]; then
        args="$args persistenthome=mtd0"
    fi
    args="$args reset_overlay"
    xosyspath=$(echo $SYSLINUXPATH | sed -e 's;/;\\;')
    if [ ! -d $TGTMNT/boot ]; then
        mkdir -p $TGTMNT/boot
    fi
    cat > $TGTMNT/boot/olpc.fth <<EOF
\ Boot script for USB boot
hex  rom-pa fffc7 + 4 \$number drop  h# 2e19 < [if]
  patch 2drop erase claim-params
  : high-ramdisk  ( -- )
     cv-load-ramdisk
     h# 22c +lp l@ 1+   memory-limit  umin  /ramdisk - ffff.f000 and ( new-ramdisk-adr )
     ramdisk-adr over  /ramdisk move                    ( new-ramdisk-adr )
     to ramdisk-adr
  ;
  ' high-ramdisk to load-ramdisk
[then]

: set-bootpath-dev  ( -- )
   " /chosen" find-package  if                       ( phandle )
      " bootpath" rot  get-package-property  0=  if  ( propval$ )
         get-encoded-string                          ( bootpath$ )
         [char] \ left-parse-string  2nip            ( dn$ )
         dn-buf place                                ( )
      then
   then

   " /sd"  dn-buf  count  sindex  0>=   if
          " sd:"
   else
          " u:"
   then
   " BOOTPATHDEV" \$set-macro
;

set-bootpath-dev
" $args" to boot-file
" \${BOOTPATHDEV}$xosyspath\initrd0.img" expand$ to ramdisk
" \${BOOTPATHDEV}$xosyspath\vmlinuz0" expand$ to boot-device
unfreeze
boot
EOF

fi

if [ -z "$multi" ]; then
    echo "Installing boot loader"
    if [ -n "$efi" ]; then
        # replace the ia32 hack
        if [ -f "$TGTMNT/EFI/boot/boot.conf" ]; then
            cp -f $TGTMNT/EFI/boot/bootia32.conf $TGTMNT/EFI/boot/boot.conf
        fi
    fi

    # this is a bit of a kludge, but syslinux doesn't guarantee the API for its com32 modules :/
    if [ -f $TGTMNT/$SYSLINUXPATH/vesamenu.c32 -a -f /usr/share/syslinux/vesamenu.c32 ]; then
        cp /usr/share/syslinux/vesamenu.c32 $TGTMNT/$SYSLINUXPATH/vesamenu.c32
    elif [ -f $TGTMNT/$SYSLINUXPATH/vesamenu.c32 -a -f /usr/lib/syslinux/vesamenu.c32 ]; then
        cp /usr/lib/syslinux/vesamenu.c32 $TGTMNT/$SYSLINUXPATH/vesamenu.c32
    elif [ -f $TGTMNT/$SYSLINUXPATH/menu.c32 -a -f /usr/share/syslinux/menu.c32 ]; then
        cp /usr/share/syslinux/menu.c32 $TGTMNT/$SYSLINUXPATH/menu.c32
    elif [ -f $TGTMNT/$SYSLINUXPATH/menu.c32 -a -f /usr/lib/syslinux/menu.c32 ]; then
        cp /usr/lib/syslinux/menu.c32 $TGTMNT/$SYSLINUXPATH/menu.c32
    fi

    if [ "$TGTFS" == "vfat" -o "$TGTFS" == "msdos" ]; then
        # syslinux expects the config to be named syslinux.cfg
        # and has to run with the file system unmounted
        mv $TGTMNT/$SYSLINUXPATH/isolinux.cfg $TGTMNT/$SYSLINUXPATH/syslinux.cfg
        # deal with mtools complaining about ldlinux.sys
        if [ -f $TGTMNT/$SYSLINUXPATH/ldlinux.sys ]; then
            rm -f $TGTMNT/$SYSLINUXPATH/ldlinux.sys
        fi
        cleanup
        if [ -n "$SYSLINUXPATH" ]; then
            syslinux -d $SYSLINUXPATH $TGTDEV
        else
            syslinux $TGTDEV
        fi
    elif [ "$TGTFS" == "ext2" -o "$TGTFS" == "ext3" -o "$TGTFS" == "ext4" -o "$TGTFS" == "btrfs" ]; then
        # extlinux expects the config to be named extlinux.conf
        # and has to be run with the file system mounted
        mv $TGTMNT/$SYSLINUXPATH/isolinux.cfg $TGTMNT/$SYSLINUXPATH/extlinux.conf
        extlinux -i $TGTMNT/$SYSLINUXPATH
        # Starting with syslinux 4 ldlinux.sys is used on all file systems.
        if [ -f "$TGTMNT/$SYSLINUXPATH/extlinux.sys" ]; then
            chattr -i $TGTMNT/$SYSLINUXPATH/extlinux.sys
        elif [ -f "$TGTMNT/$SYSLINUXPATH/ldlinux.sys" ]; then
            chattr -i $TGTMNT/$SYSLINUXPATH/ldlinux.sys
        fi
        cleanup
    fi
else
    # we need to do some more config file tweaks for multi-image mode
    sed -i -e "s;kernel vm;kernel /$LIVEOS/syslinux/vm;" $TGTMNT/$SYSLINUXPATH/isolinux.cfg
    sed -i -e "s;initrd=i;initrd=/$LIVEOS/syslinux/i;" $TGTMNT/$SYSLINUXPATH/isolinux.cfg
    mv $TGTMNT/$SYSLINUXPATH/isolinux.cfg $TGTMNT/$SYSLINUXPATH/syslinux.cfg
    cleanup
fi

echo "Target device is now set up with a Live image!"
