#!/bin/bash
# Convert a live CD iso so that it's bootable off of a USB stick
# Copyright 2007  Red Hat, Inc.
# Jeremy Katz <katzj@redhat.com>
#
# overlay/persistence enhancements by Douglas McClendon <dmc@viros.org>
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
    echo "$0 [--reset-mbr] [--noverify] [--overlay-size-mb <size>] [--home-size-mb <size>] [--unencrypted-home] <isopath> <usbstick device>"
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

    if [[ "$DEV" =~ "/dev/loop*" ]]; then
       device="$DEV"
       return
    fi

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
    if [[ "$DEV" =~ "/dev/loop*" ]]; then
       return
    fi
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
    if [[ "$dev" =~ "/dev/loop*" ]]; then
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

if [ $(id -u) != 0 ]; then 
    echo "You need to be root to run this script"
    exit 1
fi

cryptedhome=1
keephome=1
while [ $# -gt 2 ]; do
    case $1 in
	--overlay-size-mb)
	    overlaysizemb=$2
	    shift
	    ;;
	--home-size-mb)
            homesizemb=$2
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
        --extra-kernel-args)
            kernelargs=$2
            shift
            ;;
	*)
	    usage
	    ;;
    esac
    shift
done

ISO=$(readlink -f "$1")
USBDEV=$2

if [ -z "$ISO" ]; then
    usage
fi

if [ ! -b "$ISO" -a ! -f "$ISO" ]; then
    usage
fi

if [ -z "$USBDEV" -o ! -b "$USBDEV" ]; then
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

# do some basic sanity checks.  
checkSyslinuxVersion 
checkFilesystem $USBDEV
checkPartActive $USBDEV
checkMBR $USBDEV
checkMounted $USBDEV
[ -n $resetmbr ] && resetMBR $USBDEV

if [ -n "$overlaysizemb" -a "$USBFS" = "vfat" ]; then
  if [ "$overlaysizemb" -gt 2047 ]; then
    echo "Can't have an overlay greater than 2048MB on VFAT"
    exitclean
  fi
fi

if [ -n "$homesizemb" -a "$USBFS" = "vfat" ]; then
  if [ "$homesizemb" -gt 2047 ]; then
    echo "Can't have a home overlay greater than 2048MB on VFAT"
    exitclean
  fi
fi

# FIXME: would be better if we had better mountpoints
CDMNT=$(mktemp -d /media/cdtmp.XXXXXX)
mount -o loop,ro "$ISO" $CDMNT || exitclean
USBMNT=$(mktemp -d /media/usbdev.XXXXXX)
mount $USBDEV $USBMNT || exitclean

trap exitclean SIGINT SIGTERM

if [ -f "$USBMNT/LiveOS/home.img" -a -n "$keephome" -a -n "$homesizemb" ]; then
  echo "ERROR: Requested keeping existing /home and specified a size for /home"
  echo "Please either don't specify a size or specify --delete-home"
  exitclean
fi

# let's try to make sure there's enough room on the stick
if [ -d $CDMNT/LiveOS ]; then
  check=$CDMNT/LiveOS
else
  check=$CDMNT
fi
if [ -d $USBMNT/LiveOS ]; then
  tbd=$(du -s -B 1M $USBMNT/LiveOS | awk {'print $1;'})
  [ -f $USBMNT/LiveOS/home.img ] && homesz=$(du -s -B 1M $USBMNT/LiveOS/home.img | awk {'print $1;'})
  [ -n "$homesz" -a -n "$keephome" ] && tbd=$(($tbd - $homesz))
else
  tbd=0
fi
livesize=$(du -s -B 1M $check | awk {'print $1;'})
free=$(df  -B1M $USBDEV  |tail -n 1 |awk {'print $4;'})

if [ $(($overlaysizemb + $homesizemb + $livesize)) -gt $(($free + $tbd)) ]; then
  echo "Unable to fit live image + overlay on available space on USB stick"
  echo "Size of live image: $livesize"
  [ -n "$overlaysizemb" ] && echo "Overlay size: $overlaysizemb"
  [ -n "$homesizemb" ] && echo "Home overlay size: $homesizemb"
  echo "Available space: $(($free + $tbd))"
  exitclean
fi

if [ -d $USBMNT/LiveOS ]; then
    echo "Already set up as live image."  
    if [ -z "$keephome" -a -e $USBMNT/LiveOS/home.img ]; then 
      echo "WARNING: Persistent /home will be deleted!!!"
      echo "Press Enter to continue or ctrl-c to abort"
      read
    else
      echo "Deleting old OS in fifteen seconds..."
      sleep 15

      [ -e "$USBMNT/LiveOS/home.img" -a -n "$keephome" ] && mv $USBMNT/LiveOS/home.img $USBMNT/home.img
    fi

    rm -rf $USBMNT/LiveOS
fi

echo "Copying live image to USB stick"
if [ ! -d $USBMNT/$SYSLINUXPATH ]; then mkdir $USBMNT/$SYSLINUXPATH ; fi
if [ ! -d $USBMNT/LiveOS ]; then mkdir $USBMNT/LiveOS ; fi
if [ -n "$keephome" -a -f "$USBMNT/home.img" ]; then mv $USBMNT/home.img $USBMNT/LiveOS/home.img ; fi
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
if [ -f $CDMNT/LiveOS/osmin.img ]; then
    cp $CDMNT/LiveOS/osmin.img $USBMNT/LiveOS/osmin.img || exitclean
fi

cp $CDMNT/isolinux/* $USBMNT/$SYSLINUXPATH

echo "Updating boot config file"
# adjust label and fstype
sed -i -e "s/CDLABEL=[^ ]*/$USBLABEL/" -e "s/rootfstype=[^ ]*/rootfstype=$USBFS/" $USBMNT/$SYSLINUXPATH/isolinux.cfg
if [ -n "$kernelargs" ]; then sed -i -e "s/liveimg/liveimg ${kernelargs}/" $USBMNT/$SYSLINUXPATH/isolinux.cfg ; fi

if [ -n "$overlaysizemb" ]; then
    echo "Initializing persistent overlay file"
    OVERFILE="overlay-$( /lib/udev/vol_id -l $USBDEV )-$( /lib/udev/vol_id -u $USBDEV )"
    if [ "$USBFS" = "vfat" ]; then
	# vfat can't handle sparse files
	dd if=/dev/zero of=$USBMNT/LiveOS/$OVERFILE count=$overlaysizemb bs=1M
    else
	dd if=/dev/null of=$USBMNT/LiveOS/$OVERFILE count=1 bs=1M seek=$overlaysizemb
    fi
    sed -i -e "s/liveimg/liveimg overlay=${USBLABEL}/" \
	$USBMNT/$SYSLINUXPATH/isolinux.cfg
    sed -i -e "s/\ ro\ /\ rw\ /" \
	$USBMNT/$SYSLINUXPATH/isolinux.cfg
fi

if [ -n "$homesizemb" ]; then
    echo "Initializing persistent /home"
    HOMEFILE=home.img
    if [ "$USBFS" = "vfat" ]; then
	# vfat can't handle sparse files
	dd if=/dev/zero of=$USBMNT/LiveOS/$HOMEFILE count=$homesizemb bs=1M
    else
	dd if=/dev/null of=$USBMNT/LiveOS/$HOMEFILE count=1 bs=1M seek=$homesizemb
    fi
    if [ -n "$cryptedhome" ]; then
	loop=$(losetup -f)
	losetup $loop $USBMNT/LiveOS/$HOMEFILE
        echo "Encrypting persistent /home"
        cryptsetup luksFormat -y -q $loop
        echo "Please enter the password again to unlock the device"
        cryptsetup luksOpen $loop EncHomeFoo
        mke2fs -j /dev/mapper/EncHomeFoo
	tune2fs -c0 -i0 -ouser_xattr,acl /dev/mapper/EncHomeFoo
        cryptsetup luksClose EncHomeFoo
        losetup -d $loop
    else
        echo "Formatting unencrypted /home"
	mke2fs -F -j $USBMNT/LiveOS/$HOMEFILE
	tune2fs -c0 -i0 -ouser_xattr,acl $USBMNT/LiveOS/$HOMEFILE
    fi
fi

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
