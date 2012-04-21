#!/bin/bash
# Convert a live CD iso so that it's bootable off of a USB stick
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
    echo "$0 [--timeout <time>] [--totaltimeout <time>] [--format] [--reset-mbr] [--noverify] [--overlay-size-mb <size>] [--home-size-mb <size>] [--unencrypted-home] [--skipcopy] [--efi] <isopath> <usbstick device>"
    exit 1
}

cleanup() {
    sleep 2
    [ -d "$CDMNT" ] && umount $CDMNT && rmdir $CDMNT
    [ -d "$USBMNT" ] && umount $USBMNT && rmdir $USBMNT
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
    if [ $? -gt 0 ]; then
        echo "Error getting udev path to $DEV"
        exitclean
    fi
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
    if [ -n "$efi" ];then
        if [ -f /usr/lib/syslinux/gptmbr.bin ]; then
            cat /usr/lib/syslinux/gptmbr.bin > $device
        elif [ -f /usr/share/syslinux/gptmbr.bin ]; then
            cat /usr/share/syslinux/gptmbr.bin > $device
        else
            echo "Could not find gptmbr.bin (syslinux)"
            exitclean
        fi
        # Make it bootable on EFI and BIOS
        parted -s $device set $partnum legacy_boot on
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
    wipefs -a ${device}
    /sbin/parted --script $device mklabel gpt
    partinfo=$(LC_ALL=C /sbin/parted --script -m $device "unit b print" |grep ^$device:)
    size=$(echo $partinfo |cut -d : -f 2 |sed -e 's/B$//')
    /sbin/parted --script $device unit b mkpart '"EFI System Partition"' fat32 1048576 $(($size - 1048576)) set 1 boot on
    # Sometimes automount can be _really_ annoying.
    echo "Waiting for devices to settle..."
    /sbin/udevadm settle
    sleep 5
    getpartition ${device#/dev/}
    USBDEV=${device}${partnum}
    umount $USBDEV &> /dev/null
    /sbin/mkdosfs -n LIVE $USBDEV
    USBLABEL="UUID=$(/sbin/blkid -s UUID -o value $USBDEV)"
}

createMSDOSLayout() {
    dev=$1
    getdisk $dev

    echo "WARNING: THIS WILL DESTROY ANY DATA ON $device!!!"
    echo "Press Enter to continue or ctrl-c to abort"
    read
    umount ${device}* &> /dev/null
    wipefs -a ${device}
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
        USBDEV=${device}${partnum}
    else
        USBDEV=${device}
    fi
    umount $USBDEV &> /dev/null
    /sbin/mkdosfs -n LIVE $USBDEV
    USBLABEL="UUID=$(/sbin/blkid -s UUID -o value $USBDEV)"
}

createEXTFSLayout() {
    dev=$1
    getdisk $dev

    echo "WARNING: THIS WILL DESTROY ANY DATA ON $device!!!"
    echo "Press Enter to continue or ctrl-c to abort"
    read
    umount ${device}* &> /dev/null
    wipefs -a ${device}
    /sbin/parted --script $device mklabel msdos
    partinfo=$(LC_ALL=C /sbin/parted --script -m $device "unit b print" |grep ^$device:)
    size=$(echo $partinfo |cut -d : -f 2 |sed -e 's/B$//')
    /sbin/parted --script $device unit b mkpart primary ext2 1048576 $(($size - 1048576)) set 1 boot on
    # Sometimes automount can be _really_ annoying.
    echo "Waiting for devices to settle..."
    /sbin/udevadm settle
    sleep 5
    getpartition ${device#/dev/}
    USBDEV=${device}${partnum}
    umount $USBDEV &> /dev/null
    /sbin/mkfs.ext3 -L LIVE $USBDEV
    USBLABEL="UUID=$(/sbin/blkid -s UUID -o value $USBDEV)"
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

    USBFS=$(/sbin/blkid -s TYPE -o value $dev)
    if [ "$USBFS" != "vfat" ] && [ "$USBFS" != "msdos" ]; then
        if [ "$USBFS" != "ext2" ] && [ "$USBFS" != "ext3" ]; then
	    echo "USB filesystem must be vfat, ext[23]"
	    exitclean
        fi
    fi


    USBLABEL=$(/sbin/blkid -s UUID -o value $dev)
    if [ -n "$USBLABEL" ]; then
	USBLABEL="UUID=$USBLABEL" ;
    else
	USBLABEL=$(/sbin/blkid -s LABEL -o value $dev)
	if [ -n "$USBLABEL" ]; then
	    USBLABEL="LABEL=$USBLABEL"
	else
	    echo "Need to have a filesystem label or UUID for your USB device"
	    if [ "$USBFS" = "vfat" -o "$USBFS" = "msdos" ]; then
		echo "Label can be set with /sbin/dosfslabel"
	    elif [ "$USBFS" = "ext2" -o "$USBFS" = "ext3" ]; then
		echo "Label can be set with /sbin/e2label"
	    elif [ "$USBFS" = "btrfs" ]; then
                echo "Eventually you'll be able to use /sbin/btrfs filesystem label to add a label."
	    fi
	    exitclean
	fi
    fi

    if [ "$USBFS" = "vfat" -o "$USBFS" = "msdos" ]; then
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

detectisotype() {
    if [ -e $CDMNT/LiveOS/squashfs.img ]; then
        isotype=live
        return
    fi
    if [ -e $CDMNT/images/install.img -o $CDMNT/isolinux/initrd.img ]; then
        imgtype=install
        if [ -e $CDMNT/Packages ]; then
            isotype=installer
        else
            isotype=netinst
        fi
        if [ ! -e $CDMNT/images/install.img ]; then
            echo "$ISO uses initrd.img w/o install.img"
            imgtype=initrd
        fi
        return
    fi
    echo "ERROR: $ISO does not appear to be a Live image or DVD installer."
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
        if [ -x /usr/bin/rsync ]; then
            rsync -P "$1" "$2"
            return
        fi
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

shopt -s extglob

cryptedhome=1
keephome=1
homesizemb=0
swapsizemb=0
overlaysizemb=0
isotype=
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

ISO=$(readlink -f "$1")
USBDEV=$(readlink -f "$2")

if [ -z "$ISO" ]; then
    echo "Missing source"
    usage
fi

if [ ! -b "$ISO" -a ! -f "$ISO" ]; then
    echo "$ISO is not a file or block device"
    usage
fi

# FIXME: If --format is given, we shouldn't care and just use /dev/foo1
if [ -z "$USBDEV" ]; then
    echo "Missing target device"
    usage
fi

if [ ! -b "$USBDEV" ]; then
    echo "$USBDEV is not a block device"
    usage
fi

if [ -z "$noverify" ]; then
    # verify the image
    echo "Verifying image..."
    checkisomd5 --verbose "$ISO"
    if [ $? -ne 0 ]; then
	echo "Are you SURE you want to continue?"
	echo "Press Enter to continue or ctrl-c to abort"
	read
    fi
fi

#checkFilesystem $USBDEV
# do some basic sanity checks.
checkMounted $USBDEV
if [ -n "$format" -a -z "$skipcopy" ];then
    checkLVM $USBDEV
    # checks for a valid filesystem
    if [ -n "$efi" ];then
        createGPTLayout $USBDEV
    elif [ "$USBFS" == "vfat" -o "$USBFS" == "msdos" ]; then
        createMSDOSLayout $USBDEV
    else
        createEXTFSLayout $USBDEV
    fi
fi

checkFilesystem $USBDEV
if [ -n "$efi" ]; then
    checkGPT $USBDEV
fi

checkSyslinuxVersion
# Because we can't set boot flag for EFI Protective on msdos partition tables
[ -z "$efi" ] && checkPartActive $USBDEV
[ -n "$resetmbr" ] && resetMBR $USBDEV
checkMBR $USBDEV


if [ "$overlaysizemb" -gt 0 -a "$USBFS" = "vfat" ]; then
    if [ "$overlaysizemb" -gt 2047 ]; then
        echo "Can't have an overlay of 2048MB or greater on VFAT"
        exitclean
    fi
fi

if [ "$homesizemb" -gt 0 -a "$USBFS" = "vfat" ]; then
    if [ "$homesizemb" -gt 2047 ]; then
        echo "Can't have a home overlay greater than 2048MB on VFAT"
        exitclean
    fi
fi

if [ "$swapsizemb" -gt 0 -a "$USBFS" = "vfat" ]; then
    if [ "$swapsizemb" -gt 2047 ]; then
        echo "Can't have a swap file greater than 2048MB on VFAT"
        exitclean
    fi
fi

# FIXME: would be better if we had better mountpoints
CDMNT=$(mktemp -d /media/cdtmp.XXXXXX)
if [ -b $ISO ]; then
    mount -o ro "$ISO" $CDMNT || exitclean
elif [ -f $ISO ]; then
    mount -o loop,ro "$ISO" $CDMNT || exitclean
else
    echo "$ISO is not a file or block device."
    exitclean
fi
USBMNT=$(mktemp -d /media/usbdev.XXXXXX)
mount $mountopts $USBDEV $USBMNT || exitclean

trap exitclean SIGINT SIGTERM

detectisotype

if [ -f "$USBMNT/$LIVEOS/$HOMEFILE" -a -n "$keephome" -a "$homesizemb" -gt 0 ]; then
    echo "ERROR: Requested keeping existing /home and specified a size for /home"
    echo "Please either don't specify a size or specify --delete-home"
    exitclean
fi

if [ -n "$efi" ]; then
    if [ -d $CDMNT/EFI/BOOT ]; then
        EFI_BOOT="/EFI/BOOT"
    elif [ -d $CDMNT/EFI/boot ]; then
        EFI_BOOT="/EFI/boot"
    else
        echo "ERROR: This live image does not support EFI booting"
        exitclean
    fi
fi

# let's try to make sure there's enough room on the stick
if [ -d $CDMNT/LiveOS ]; then
    check=$CDMNT/LiveOS
else
    check=$CDMNT
fi
if [ -d $USBMNT/$LIVEOS ]; then
    tbd=$(du -s -B 1M $USBMNT/$LIVEOS | awk {'print $1;'})
    [ -f $USBMNT/$LIVEOS/$HOMEFILE ] && homesz=$(du -s -B 1M $USBMNT/$LIVEOS/$HOMEFILE | awk {'print $1;'})
    [ -n "$homesz" -a -n "$keephome" ] && tbd=$(($tbd - $homesz))
else
    tbd=0
fi
livesize=$(du -s -B 1M $check | awk {'print $1;'})
if [ -n "$skipcompress" ]; then
    if [ -e $CDMNT/LiveOS/squashfs.img ]; then
	if mount -o loop $CDMNT/LiveOS/squashfs.img $CDMNT; then
	    livesize=$(du -s -B 1M $CDMNT/LiveOS/ext3fs.img | awk {'print $1;'})
	    umount $CDMNT
	else
	    echo "WARNING: --skipcompress or --xo was specified but the currently"
	    echo "running kernel can not mount the squashfs from the ISO file to extract"
	    echo "it. The compressed squashfs will be copied to the USB stick."
	    skipcompress=""
	fi
    fi
fi
free=$(df  -B1M $USBDEV  |tail -n 1 |awk {'print $4;'})

if [ "$isotype" = "live" ]; then
    tba=$(($overlaysizemb + $homesizemb + $livesize + $swapsizemb))
    if [ $tba -gt $(($free + $tbd)) ]; then
        echo "Unable to fit live image + overlay on available space on USB stick"
        echo "+ Size of live image:  $livesize"
        [ "$overlaysizemb" -gt 0 ] && echo "+ Overlay size:  $overlaysizemb"
        [ "$homesizemb" -gt 0 ] && echo "+ Home overlay size:  $homesizemb"
        [ "$swapsizemb" -gt 0 ] && echo "+ Swap overlay size:  $swapsizemb"
        echo "---------------------------"
        echo "= Requested:  $tba"
        echo "- Available:  $(($free + $tbd))"
        echo "---------------------------"
        echo "= To fit, free or decrease requested size total by:  $(($tba - $free - $tbd))"
        exitclean
    fi
fi

# Verify available space for DVD installer
if [ "$isotype" = "installer" ]; then
    if [ -z "$skipcopy" ]; then
        isosize=$(du -s -B 1M $ISO | awk {'print $1;'})
    else
        isosize=0
    fi
    if [ "$imgtype" = "install" ]; then
        imgpath=images/install.img
    else
        imgpath=isolinux/initrd.img
    fi
    installimgsize=$(du -s -B 1M $CDMNT/$imgpath | awk {'print $1;'})

    tbd=0
    if [ -e $USBMNT/$imgpath ]; then
        tbd=$(du -s -B 1M $USBMNT/$imgpath | awk {'print $1;'})
    fi
    if [ -e $USBMNT/$(basename $ISO) ]; then
        tbd=$(($tbd + $(du -s -B 1M $USBMNT/$(basename $ISO) | awk {'print $1;'})))
    fi
    echo "Size of DVD image: $isosize"
    echo "Size of $imgpath: $installimgsize"
    echo "Available space: $(($free + $tbd))"
    if [ $(($isosize + $installimgsize)) -gt $(($free + $tbd)) ]; then
        echo "ERROR: Unable to fit DVD image + install.img on available space on USB stick"
        exitclean
    fi
fi

if [ -z "$skipcopy" ] && [ "$isotype" = "live" ]; then
    if [ -d $USBMNT/$LIVEOS -a -z "$force" ]; then
        echo "Already set up as live image."
        if [ -z "$keephome" -a -e $USBMNT/$LIVEOS/$HOMEFILE ]; then
            echo "WARNING: Persistent /home will be deleted!!!"
            echo "Press Enter to continue or ctrl-c to abort"
            read
        else
            echo "Deleting old OS in fifteen seconds..."
            sleep 15

            [ -e "$USBMNT/$LIVEOS/$HOMEFILE" -a -n "$keephome" ] && mv $USBMNT/$LIVEOS/$HOMEFILE $USBMNT/$HOMEFILE
        fi

        rm -rf $USBMNT/$LIVEOS
    fi
fi

# Bootloader is always reconfigured, so keep these out of the if skipcopy stuff.
[ ! -d $USBMNT/$SYSLINUXPATH ] && mkdir -p $USBMNT/$SYSLINUXPATH
[ -n "$efi" -a ! -d $USBMNT$EFI_BOOT ] && mkdir -p $USBMNT$EFI_BOOT

# Live image copy
set -o pipefail
if [ "$isotype" = "live" -a -z "$skipcopy" ]; then
    echo "Copying live image to USB stick"
    [ ! -d $USBMNT/$LIVEOS ] && mkdir $USBMNT/$LIVEOS
    [ -n "$keephome" -a -f "$USBMNT/$HOMEFILE" ] && mv $USBMNT/$HOMEFILE $USBMNT/$LIVEOS/$HOMEFILE
    if [ -n "$skipcompress" -a -f $CDMNT/LiveOS/squashfs.img ]; then
        mount -o loop $CDMNT/LiveOS/squashfs.img $CDMNT || exitclean
        copyFile $CDMNT/LiveOS/ext3fs.img $USBMNT/$LIVEOS/ext3fs.img || {
            umount $CDMNT ; exitclean ; }
        umount $CDMNT
    elif [ -f $CDMNT/LiveOS/squashfs.img ]; then
        copyFile $CDMNT/LiveOS/squashfs.img $USBMNT/$LIVEOS/squashfs.img || exitclean
    elif [ -f $CDMNT/LiveOS/ext3fs.img ]; then
        copyFile $CDMNT/LiveOS/ext3fs.img $USBMNT/$LIVEOS/ext3fs.img || exitclean
    fi
    if [ -f $CDMNT/LiveOS/osmin.img ]; then
        copyFile $CDMNT/LiveOS/osmin.img $USBMNT/$LIVEOS/osmin.img || exitclean
    fi
    sync
fi

# DVD installer copy
if [ \( "$isotype" = "installer" -o "$isotype" = "netinst" \) ]; then
    echo "Copying DVD image to USB stick"
    mkdir -p $USBMNT/images/
    if [ "$imgtype" = "install" ]; then
        for img in install.img updates.img product.img; do
            if [ -e $CDMNT/images/$img ]; then
                copyFile $CDMNT/images/$img $USBMNT/images/$img || exitclean
            fi
        done
    fi
    if [ "$isotype" = "installer" -a -z "$skipcopy" ]; then
        copyFile $ISO $USBMNT/
    fi
    sync
fi

cp $CDMNT/isolinux/* $USBMNT/$SYSLINUXPATH
BOOTCONFIG=$USBMNT/$SYSLINUXPATH/isolinux.cfg
# Set this to nothing so sed doesn't care
BOOTCONFIG_EFI=
if [ -n "$efi" ]; then
    cp $CDMNT$EFI_BOOT/* $USBMNT$EFI_BOOT

    # FIXME
    # There is a problem here. On older LiveCD's the files are boot?*.conf
    # They really should be renamed to BOOT?*.conf

    # this is a little ugly, but it gets the "interesting" named config file
    BOOTCONFIG_EFI=$USBMNT$EFI_BOOT/+(BOOT|boot)?*.conf
    rm -f $USBMNT$EFI_BOOT/grub.conf
fi

echo "Updating boot config file"
# adjust label and fstype
if [ -n "$LANG" ]; then
	kernelargs="$kernelargs LANG=$LANG"
fi
sed -i -e "s/CDLABEL=[^ ]*/$USBLABEL/" -e "s/rootfstype=[^ ]*/rootfstype=$USBFS/" -e "s/LABEL=[^ ]*/$USBLABEL/" $BOOTCONFIG  $BOOTCONFIG_EFI
if [ -n "$kernelargs" ]; then sed -i -e "s/liveimg/liveimg ${kernelargs}/" $BOOTCONFIG $BOOTCONFIG_EFI ; fi
if [ "$LIVEOS" != "LiveOS" ]; then sed -i -e "s;liveimg;liveimg live_dir=$LIVEOS;" $BOOTCONFIG $BOOTCONFIG_EFI ; fi

if [ -n "$efi" ]; then
    sed -i -e "s;/isolinux/;/$SYSLINUXPATH/;g" $BOOTCONFIG_EFI
    sed -i -e "s;/images/pxeboot/;/$SYSLINUXPATH/;g" $BOOTCONFIG_EFI
fi

# DVD Installer
if [ "$isotype" = "installer" ]; then
    sed -i -e "s;initrd=initrd.img;initrd=initrd.img ${LANG:+LANG=$LANG} repo=hd:$USBLABEL:/;g" $BOOTCONFIG
    sed -i -e "s;stage2=\S*;;g" $BOOTCONFIG
    if [ -n "$efi" ]; then
        # Images are in $SYSLINUXPATH now
        sed -i -e "s;/images/pxeboot/;/$SYSLINUXPATH/;g" -e "s;vmlinuz;vmlinuz ${LANG:+LANG=$LANG} repo=hd:$USBLABEL:/;g" $BOOTCONFIG_EFI
    fi
fi

# DVD Installer for netinst
if [ "$isotype" = "netinst" ]; then
    if [ "$imgtype" = "install" ]; then
        sed -i -e "s;stage2=\S*;stage2=hd:$USBLABEL:/images/install.img;g" $BOOTCONFIG
    else
        # The initrd has everything, so no stage2
        sed -i -e "s;stage2=\S*;;g" $BOOTCONFIG
    fi
    if [ -n "$efi" ]; then
        # Images are in $SYSLINUXPATH now
        sed -ie "s;/images/pxeboot/;/$SYSLINUXPATH/;g" $BOOTCONFIG_EFI
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
if [ -e "$CDMNT/.discinfo" ]; then
    METHODSTR=repo
else
    METHODSTR=stage2
fi

if [ "$overlaysizemb" -gt 0 ]; then
    echo "Initializing persistent overlay file"
    OVERFILE="overlay-$( /sbin/blkid -s LABEL -o value $USBDEV )-$( /sbin/blkid -s UUID -o value $USBDEV )"
    if [ -z "$skipcopy" ]; then
        if [ "$USBFS" = "vfat" ]; then
            # vfat can't handle sparse files
            dd if=/dev/zero of=$USBMNT/$LIVEOS/$OVERFILE count=$overlaysizemb bs=1M
        else
            dd if=/dev/null of=$USBMNT/$LIVEOS/$OVERFILE count=1 bs=1M seek=$overlaysizemb
        fi
    fi
    sed -i -e "s/liveimg/liveimg overlay=${USBLABEL}/" $BOOTCONFIG $BOOTCONFIG_EFI
    sed -i -e "s/\ ro\ /\ rw\ /" $BOOTCONFIG  $BOOTCONFIG_EFI
fi

if [ "$swapsizemb" -gt 0 -a -z "$skipcopy" ]; then
    echo "Initializing swap file"
    dd if=/dev/zero of=$USBMNT/$LIVEOS/swap.img count=$swapsizemb bs=1M
    mkswap -f $USBMNT/$LIVEOS/swap.img
fi

if [ "$homesizemb" -gt 0 -a -z "$skipcopy" ]; then
    echo "Initializing persistent /home"
    homesource=/dev/zero
    [ -n "$cryptedhome" ] && homesource=/dev/urandom
    if [ "$USBFS" = "vfat" ]; then
	# vfat can't handle sparse files
	dd if=${homesource} of=$USBMNT/$LIVEOS/$HOMEFILE count=$homesizemb bs=1M
    else
	dd if=/dev/null of=$USBMNT/$LIVEOS/$HOMEFILE count=1 bs=1M seek=$homesizemb
    fi
    if [ -n "$cryptedhome" ]; then
	loop=$(losetup -f)
	losetup $loop $USBMNT/$LIVEOS/$HOMEFILE
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
	mke2fs -F -j $USBMNT/$LIVEOS/$HOMEFILE
	tune2fs -c0 -i0 -ouser_xattr,acl $USBMNT/$LIVEOS/$HOMEFILE
    fi
fi

# create the forth files for booting on the XO if requested
# we'd do this unconditionally, but you have to have a kernel that will
# boot on the XO anyway.
if [ -n "$xo" ]; then
    echo "Setting up /boot/olpc.fth file"
    args=$(grep "^ *append" $USBMNT/$SYSLINUXPATH/isolinux.cfg |head -n1 |sed -e 's/.*initrd=[^ ]*//')
    if [ -z "$xonohome" -a ! -f $USBMNT/$LIVEOS/$HOMEFILE ]; then
	args="$args persistenthome=mtd0"
    fi
    args="$args reset_overlay"
    xosyspath=$(echo $SYSLINUXPATH | sed -e 's;/;\\;')
    if [ ! -d $USBMNT/boot ]; then mkdir -p $USBMNT/boot ; fi
    cat > $USBMNT/boot/olpc.fth <<EOF
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
        if [ -f "$USBMNT$EFI_BOOT/boot.conf" ]; then
            cp -f $USBMNT$EFI_BOOT/BOOTia32.conf $USBMNT$EFI_BOOT/BOOT.conf
        fi
    fi

    # this is a bit of a kludge, but syslinux doesn't guarantee the API for its com32 modules :/
    if [ -f $USBMNT/$SYSLINUXPATH/vesamenu.c32 -a -f /usr/share/syslinux/vesamenu.c32 ]; then
        cp /usr/share/syslinux/vesamenu.c32 $USBMNT/$SYSLINUXPATH/vesamenu.c32
    elif [ -f $USBMNT/$SYSLINUXPATH/vesamenu.c32 -a -f /usr/lib/syslinux/vesamenu.c32 ]; then
        cp /usr/lib/syslinux/vesamenu.c32 $USBMNT/$SYSLINUXPATH/vesamenu.c32
    elif [ -f $USBMNT/$SYSLINUXPATH/menu.c32 -a -f /usr/share/syslinux/menu.c32 ]; then
        cp /usr/share/syslinux/menu.c32 $USBMNT/$SYSLINUXPATH/menu.c32
    elif [ -f $USBMNT/$SYSLINUXPATH/menu.c32 -a -f /usr/lib/syslinux/menu.c32 ]; then
        cp /usr/lib/syslinux/menu.c32 $USBMNT/$SYSLINUXPATH/menu.c32
    fi

    if [ "$USBFS" == "vfat" -o "$USBFS" == "msdos" ]; then
        # syslinux expects the config to be named syslinux.cfg
        # and has to run with the file system unmounted
        mv $USBMNT/$SYSLINUXPATH/isolinux.cfg $USBMNT/$SYSLINUXPATH/syslinux.cfg
        # deal with mtools complaining about ldlinux.sys
        if [ -f $USBMNT/$SYSLINUXPATH/ldlinux.sys ] ; then rm -f $USBMNT/$SYSLINUXPATH/ldlinux.sys ; fi
        cleanup
        if [ -n "$SYSLINUXPATH" ]; then
            syslinux -d $SYSLINUXPATH $USBDEV
        else
            syslinux $USBDEV
        fi
    elif [ "$USBFS" == "ext2" -o "$USBFS" == "ext3" ]; then
        # extlinux expects the config to be named extlinux.conf
        # and has to be run with the file system mounted
        mv $USBMNT/$SYSLINUXPATH/isolinux.cfg $USBMNT/$SYSLINUXPATH/extlinux.conf
        extlinux -i $USBMNT/$SYSLINUXPATH
        # Starting with syslinux 4 ldlinux.sys is used on all file systems.
        if [ -f "$USBMNT/$SYSLINUXPATH/extlinux.sys" ]; then
            chattr -i $USBMNT/$SYSLINUXPATH/extlinux.sys
        elif [ -f "$USBMNT/$SYSLINUXPATH/ldlinux.sys" ]; then
            chattr -i $USBMNT/$SYSLINUXPATH/ldlinux.sys
        fi
        cleanup
    fi
else
    # we need to do some more config file tweaks for multi-image mode
    sed -i -e "s;kernel vm;kernel /$LIVEOS/syslinux/vm;" $USBMNT/$SYSLINUXPATH/isolinux.cfg
    sed -i -e "s;initrd=i;initrd=/$LIVEOS/syslinux/i;" $USBMNT/$SYSLINUXPATH/isolinux.cfg
    mv $USBMNT/$SYSLINUXPATH/isolinux.cfg $USBMNT/$SYSLINUXPATH/syslinux.cfg
    cleanup
fi

echo "USB stick set up as live image!"
