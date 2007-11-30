#!/bin/bash
# Convert a live CD iso so that it's bootable off of a USB stick
# Copyright 2007  Red Hat, Inc.
# Jeremy Katz <katzj@redhat.com>
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
    echo "$0 [--reset-mbr] [--noverify] <isopath> <usbstick device>"
    exit 1
}

cleanup() {
    [ -d "$CDMNT" ] && umount $CDMNT && rmdir $CDMNT
    [ -d "$USBMNT" ] && umount $USBMNT && rmdir $USBMNT
}

exitclean() {
    echo "Cleaning up to exit..."
    cleanup
    exit 1
}

getdisk() {
    DEV=$1

    p=$(udevinfo -q path -n $DEV)
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
}

resetMBR() {
    getdisk $1
    if [ -f /usr/lib/syslinux/mbr.bin ]; then
	cat /usr/lib/syslinux/mbr.bin > $device
    elif [ -f /usr/share/syslinux/mbr.bin ]; then
	cat /usr/share/syslinux/mbr.bin > $device
    else
	exitclean
    fi
}

checkMBR() {
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

    if [ "$(/sbin/fdisk -l $device 2>/dev/null |grep $dev |awk {'print $2;'})" != "*" ]; then
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

    USBFS=$(/lib/udev/vol_id -t $dev)
    if [ "$USBFS" != "vfat" -a "$USBFS" != "msdos" -a "$USBFS" != "ext2" -a "$USBFS" != "ext3" ]; then
	echo "USB filesystem must be vfat or ext[23]"
	exitclean
    fi

    USBLABEL=$(/lib/udev/vol_id -u $dev)
    if [ -n "$USBLABEL" ]; then 
	USBLABEL="UUID=$USBLABEL" ; 
    else
	USBLABEL=$(/lib/udev/vol_id -l $dev)
	if [ -n "$USBLABEL" ]; then 
	    USBLABEL="LABEL=$USBLABEL" 
	else
	    echo "Need to have a filesystem label or UUID for your USB device"
	    if [ "$USBFS" = "vfat" -o "$USBFS" = "msdos" ]; then
		echo "Label can be set with /sbin/dosfslabel"
	    elif [ "$USBFS" = "ext2" -o "$USBFS" = "ext3" ]; then
		echo "Label can be set with /sbin/e2label"
	    fi
	    exitclean
	fi
    fi
}

checkSyslinuxVersion() {
    if [ ! -x /usr/bin/syslinux ]; then
	echo "You need to have syslinux installed to run this script"
	exit 1
    fi
    if ! syslinux 2>&1 | grep -qe -d; then
	SYSLINUXPATH=""
    else
	SYSLINUXPATH="syslinux"
    fi
}

if [ $(id -u) != 0 ]; then 
    echo "You need to be root to run this script"
    exit 1
fi

while [ $# -gt 2 ]; do
    case $1 in
	--noverify)
	    noverify=1
	    ;;
	--reset-mbr|--resetmbr)
	    resetmbr=1
	    ;;
	*)
	    usage
	    ;;
    esac
    shift
done

ISO=$1
USBDEV=$2

if [ -z "$ISO" -o ! -e "$ISO" ]; then
    usage
fi

if [ -z "$USBDEV" -o ! -b "$USBDEV" ]; then
    usage
fi

if [ -z "$noverify" ]; then
    # verify the image
    echo "Verifying image..."
    checkisomd5 --verbose $ISO
    if [ $? -ne 0 ]; then
	echo "Are you SURE you want to continue?"
	echo "Press Enter to continue or ctrl-c to abort"
	read
    fi
fi

# do some basic sanity checks.  
checkSyslinuxVersion 
checkFilesystem $USBDEV
checkPartActive $USBDEV
checkMBR $USBDEV
[ -n $resetmbr ] && resetMBR $USBDEV

# FIXME: would be better if we had better mountpoints
CDMNT=$(mktemp -d /media/cdtmp.XXXXXX)
mount -o loop $ISO $CDMNT || exitclean
USBMNT=$(mktemp -d /media/usbdev.XXXXXX)
mount $USBDEV $USBMNT || exitclean

trap exitclean SIGINT SIGTERM

if [ -d $USBMNT/LiveOS ]; then
    echo "Already set up as live image.  Deleting old in fifteen seconds..."
    sleep 15

    rm -rf $USBMNT/LiveOS
fi

echo "Copying live image to USB stick"
if [ ! -d $USBMNT/$SYSLINUXPATH ]; then mkdir $USBMNT/$SYSLINUXPATH ; fi
if [ ! -d $USBMNT/LiveOS ]; then mkdir $USBMNT/LiveOS ; fi
# cases without /LiveOS are legacy detection, remove for F10
if [ -f $CDMNT/LiveOS/squashfs.img ]; then
    cp $CDMNT/LiveOS/squashfs.img $USBMNT/LiveOS/squashfs.img || exitclean
elif [ -f $CDMNT/squashfs.img ]; then
    cp $CDMNT/squashfs.img $USBMNT/LiveOS/squashfs.img || exitclean 
elif [ -f $CDMNT/LiveOS/ext3fs.img ]; then
    cp $CDMNT/LiveOS/ext3fs.img $USBMNT/LiveOS/ext3fs.img || exitclean
elif [ -f $CDMNT/ext3fs.img ]; then
    cp $CDMNT/ext3fs.img $USBMNT/LiveOS/ext3fs.img || exitclean 
fi
if [ -f $CDMNT/osmin.img ]; then
    cp $CDMNT/osmin.img $USBMNT/LiveOS/osmin.img || exitclean
fi

cp $CDMNT/isolinux/* $USBMNT/$SYSLINUXPATH

echo "Updating boot config file"
# adjust label and fstype
sed -i -e "s/CDLABEL=[^ ]*/$USBLABEL/" -e "s/rootfstype=[^ ]*/rootfstype=$USBFS/" $USBMNT/$SYSLINUXPATH/isolinux.cfg

echo "Installing boot loader"
if [ "$USBFS" = "vfat" -o "$USBFS" = "msdos" ]; then
    # syslinux expects the config to be named syslinux.cfg 
    # and has to run with the file system unmounted
    mv $USBMNT/$SYSLINUXPATH/isolinux.cfg $USBMNT/$SYSLINUXPATH/syslinux.cfg
    cleanup
    if [ -n "$SYSLINUXPATH" ]; then
	syslinux -d $SYSLINUXPATH $USBDEV
    else
	syslinux $USBDEV
    fi
elif [ "$USBFS" = "ext2" -o "$USBFS" = "ext3" ]; then
    # extlinux expects the config to be named extlinux.conf
    # and has to be run with the file system mounted
    mv $USBMNT/$SYSLINUXPATH/isolinux.cfg $USBMNT/$SYSLINUXPATH/extlinux.conf
    extlinux -i $USBMNT/syslinux
    cleanup
fi

echo "USB stick set up as live image!"
