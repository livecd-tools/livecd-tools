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
    # FIXME: weird dev names could mess this up I guess
    p=/dev/`basename $p`
    partnum=${p##$device}
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

createGPTLayout() {
    dev=$1
    getdisk $dev

    echo "WARNING: THIS WILL DESTROY ANY DATA ON $device!!!"
    echo "Press Enter to continue or ctrl-c to abort"
    read

    /sbin/parted --script $device mklabel gpt
    partinfo=$(/sbin/parted --script -m $device "unit b print" |grep ^$device:)
    size=$(echo $partinfo |cut -d : -f 2 |sed -e 's/B$//')
    /sbin/parted --script $device unit b mkpart '"EFI System Partition"' fat32 17408 $(($size - 17408)) set 1 boot on
    USBDEV=${device}1
    /sbin/udevsettle
    /sbin/mkdosfs -n LIVE $USBDEV
    USBLABEL="UUID=$(/lib/udev/vol_id -u $dev)"
}

checkGPT() {
    dev=$1
    getdisk $dev

    if [ "$(/sbin/fdisk -l $device 2>/dev/null |grep -c GPT)" -eq "0" ]; then
       echo "EFI boot requires a GPT partition table."
       echo "This can be done manually or you can run with --reset-mbr"
       exitclean
    fi

    partinfo=$(/sbin/parted --script -m $device "print" |grep ^$partnum:)
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

cryptedhome=1
keephome=1
homesizemb=0
swapsizemb=0
overlaysizemb=0

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
	--mactel)
	    mactel=1
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
	*)
	    usage
	    ;;
    esac
    shift
done

ISO=$(readlink -f "$1")
USBDEV=$(readlink -f "$2")

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
checkFilesystem $USBDEV
checkMounted $USBDEV
if [ -z "$mactel" ]; then
  checkSyslinuxVersion
  checkPartActive $USBDEV
  [ -n "$resetmbr" ] && resetMBR $USBDEV
  checkMBR $USBDEV
elif [ -n "$mactel" ]; then
  [ -n "$resetmbr" ] && createGPTLayout $USBDEV
  checkGPT $USBDEV
fi


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
mount -o loop,ro "$ISO" $CDMNT || exitclean
USBMNT=$(mktemp -d /media/usbdev.XXXXXX)
mount $mountopts $USBDEV $USBMNT || exitclean

trap exitclean SIGINT SIGTERM

if [ -f "$USBMNT/LiveOS/$HOMEFILE" -a -n "$keephome" -a "$homesizemb" -gt 0 ]; then
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
  [ -f $USBMNT/LiveOS/$HOMEFILE ] && homesz=$(du -s -B 1M $USBMNT/LiveOS/$HOMEFILE | awk {'print $1;'})
  [ -n "$homesz" -a -n "$keephome" ] && tbd=$(($tbd - $homesz))
else
  tbd=0
fi
livesize=$(du -s -B 1M $check | awk {'print $1;'})
if [ -n "$skipcompress" ]; then
    mount -o loop $CDMNT/LiveOS/squashfs.img $CDMNT
    livesize=$(du -s -B 1M $CDMNT/LiveOS/ext3fs.img | awk {'print $1;'})
    umount $CDMNT
fi
free=$(df  -B1M $USBDEV  |tail -n 1 |awk {'print $4;'})

if [ $(($overlaysizemb + $homesizemb + $livesize + $swapsizemb)) -gt $(($free + $tbd)) ]; then
  echo "Unable to fit live image + overlay on available space on USB stick"
  echo "Size of live image: $livesize"
  [ "$overlaysizemb" -gt 0 ] && echo "Overlay size: $overlaysizemb"
  [ "$homesizemb" -gt 0 ] && echo "Home overlay size: $homesizemb"
  [ "$swapsizemb" -gt 0 ] && echo "Home overlay size: $swapsizemb"
  echo "Available space: $(($free + $tbd))"
  exitclean
fi

if [ -d $USBMNT/LiveOS -a -z "$force" ]; then
    echo "Already set up as live image."  
    if [ -z "$keephome" -a -e $USBMNT/LiveOS/$HOMEFILE ]; then
      echo "WARNING: Persistent /home will be deleted!!!"
      echo "Press Enter to continue or ctrl-c to abort"
      read
    else
      echo "Deleting old OS in fifteen seconds..."
      sleep 15

      [ -e "$USBMNT/LiveOS/$HOMEFILE" -a -n "$keephome" ] && mv $USBMNT/LiveOS/$HOMEFILE $USBMNT/$HOMEFILE
    fi

    rm -rf $USBMNT/LiveOS
fi

echo "Copying live image to USB stick"
[ -z "$mactel" -a ! -d $USBMNT/$SYSLINUXPATH ] && mkdir -p $USBMNT/$SYSLINUXPATH
[ -n "$mactel" -a ! -d $USBMNT/EFI/boot ] && mkdir -p $USBMNT/EFI/boot
[ ! -d $USBMNT/LiveOS ] && mkdir $USBMNT/LiveOS
[ -n "$keephome" -a -f "$USBMNT/$HOMEFILE" ] && mv $USBMNT/$HOMEFILE $USBMNT/LiveOS/$HOMEFILE
# cases without /LiveOS are legacy detection, remove for F10
if [ -n "$skipcompress" -a -f $CDMNT/LiveOS/squashfs.img ]; then
    mount -o loop $CDMNT/LiveOS/squashfs.img $CDMNT
    cp $CDMNT/LiveOS/ext3fs.img $USBMNT/LiveOS/ext3fs.img || (umount $CDMNT ; exitclean)
    umount $CDMNT
elif [ -f $CDMNT/LiveOS/squashfs.img ]; then
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

if [ -z "$mactel" ]; then
  cp $CDMNT/isolinux/* $USBMNT/$SYSLINUXPATH
  BOOTCONFIG=$USBMNT/$SYSLINUXPATH/isolinux.cfg
else
  if [ -d $CDMNT/EFI/boot ]; then
    cp $CDMNT/EFI/boot/* $USBMNT/EFI/boot
  else
    # whee!  this image wasn't made with grub.efi bits.  so we get to create
    # them here.  isn't life grand?
    cp $CDMNT/isolinux/* $USBMNT/EFI/boot
    mount -o loop,ro -t squashfs $CDMNT/LiveOS/squashfs.img $CDMNT
    mount -o loop,ro -t ext3 $CDMNT/LiveOS/ext3fs.img $CDMNT
    cp $CDMNT/boot/efi/EFI/redhat/grub.efi $USBMNT/EFI/boot/boot.efi
    cp $CDMNT/boot/grub/splash.xpm.gz $USBMNT/EFI/boot/splash.xpm.gz
    if [ -d $CDMNT/lib64 ]; then efiarch="x64" ; else efiarch="ia32"; fi
    umount $CDMNT
    umount $CDMNT

    # magic config...
    cat > $USBMNT/EFI/boot/boot.conf <<EOF
default=0
splashimage=/EFI/boot/splash.xpm.gz
timeout 10
hiddenmenu

title Live
  kernel /EFI/boot/vmlinuz0 root=CDLABEL=live rootfstype=iso9660 ro quiet liveimg
  initrd /EFI/boot/initrd0.img
EOF

    cp $USBMNT/EFI/boot/boot.conf $USBMNT/EFI/boot/boot${efiarch}.conf
    cp $USBMNT/EFI/boot/boot.efi $USBMNT/EFI/boot/boot${efiarch}.efi
  fi

  # this is a little ugly, but it gets the "interesting" named config file
  BOOTCONFIG=$USBMNT/EFI/boot/boot?*.conf
  rm -f $USBMNT/EFI/boot/grub.conf
fi

echo "Updating boot config file"
# adjust label and fstype
sed -i -e "s/CDLABEL=[^ ]*/$USBLABEL/" -e "s/rootfstype=[^ ]*/rootfstype=$USBFS/" $BOOTCONFIG
if [ -n "$kernelargs" ]; then sed -i -e "s/liveimg/liveimg ${kernelargs}/" $BOOTCONFIG ; fi

if [ "$overlaysizemb" -gt 0 ]; then
    echo "Initializing persistent overlay file"
    OVERFILE="overlay-$( /lib/udev/vol_id -l $USBDEV )-$( /lib/udev/vol_id -u $USBDEV )"
    if [ "$USBFS" = "vfat" ]; then
	# vfat can't handle sparse files
	dd if=/dev/zero of=$USBMNT/LiveOS/$OVERFILE count=$overlaysizemb bs=1M
    else
	dd if=/dev/null of=$USBMNT/LiveOS/$OVERFILE count=1 bs=1M seek=$overlaysizemb
    fi
    sed -i -e "s/liveimg/liveimg overlay=${USBLABEL}/" $BOOTCONFIG
    sed -i -e "s/\ ro\ /\ rw\ /" $BOOTCONFIG
fi

if [ "$swapsizemb" -gt 0 ]; then
    echo "Initializing swap file"
    dd if=/dev/zero of=$USBMNT/LiveOS/swap.img count=$swapsizemb bs=1M
    mkswap -f $USBMNT/LiveOS/swap.img
fi

if [ "$homesizemb" -gt 0 ]; then
    echo "Initializing persistent /home"
    homesource=/dev/zero
    [ -n "$cryptedhome" ] && homesource=/dev/urandom
    if [ "$USBFS" = "vfat" ]; then
	# vfat can't handle sparse files
	dd if=${homesource} of=$USBMNT/LiveOS/$HOMEFILE count=$homesizemb bs=1M
    else
	dd if=/dev/null of=$USBMNT/LiveOS/$HOMEFILE count=1 bs=1M seek=$homesizemb
    fi
    if [ -n "$cryptedhome" ]; then
	loop=$(losetup -f)
	losetup $loop $USBMNT/LiveOS/$HOMEFILE
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
        cryptsetup luksClose EncHomeFoo
        losetup -d $loop
    else
        echo "Formatting unencrypted /home"
	mke2fs -F -j $USBMNT/LiveOS/$HOMEFILE
	tune2fs -c0 -i0 -ouser_xattr,acl $USBMNT/LiveOS/$HOMEFILE
    fi
fi

# create the forth files for booting on the XO if requested
# we'd do this unconditionally, but you have to have a kernel that will
# boot on the XO anyway.
if [ -n "$xo" ]; then
    echo "Setting up /boot/olpc.fth file"
    args=$(egrep "^[ ]*append" $USBMNT/$SYSLINUXPATH/isolinux.cfg |head -n1 |sed -e 's/.*initrd=[^ ]*//')
    if [ -z "$xonohome" -a ! -f $USBMNT/LiveOS/$HOMEFILE ]; then
	args="$args persistenthome=mtd0"
    fi
    args="$args reset_overlay"
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
" \${BOOTPATHDEV}\syslinux\initrd0.img" expand$ to ramdisk
" \${BOOTPATHDEV}\syslinux\vmlinuz0" expand$ to boot-device
unfreeze
boot
EOF

fi

echo "Installing boot loader"
if [ -n "$mactel" ]; then
    # replace the ia32 hack
    if [ -f "$USBMNT/EFI/boot/boot.conf" ]; then cp -f $USBMNT/EFI/boot/bootia32.conf $USBMNT/EFI/boot/boot.conf ; fi
    cleanup
elif [ "$USBFS" = "vfat" -o "$USBFS" = "msdos" ]; then
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
