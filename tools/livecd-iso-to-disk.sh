#!/bin/bash
# Transfer a Live image so that it's bootable off of a USB/SD device.
# Copyright 2007-2012  Red Hat, Inc.
#
# Jeremy Katz <katzj@redhat.com>
# Brian C. Lane <bcl@redhat.com>
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

shortusage() {
    echo "
    SYNTAX

    livecd-iso-to-disk [--help] [--noverify] [--format] [--msdos] [--reset-mbr]
                       [--efi] [--skipcopy] [--force] [--xo] [--xo-no-home]
                       [--timeout <time>] [--totaltimeout <time>]
                       [--extra-kernel-args <args>] [--multi] [--livedir <dir>]
                       [--compress] [--skipcompress] [--swap-size-mb <size>]
                       [--overlay-size-mb <size>] [--home-size-mb <size>]
                       [--delete-home] [--crypted-home] [--unencrypted-home]
                       [--updates <updates.img>] [--ks <kickstart>]
                       [--label <label>]
                       <source> <target device>

    (Enter livecd-iso-to-disk --help on the command line for more information.)"
}

usage() {
    echo "
    "
    shortusage
    echo "
    livecd-iso-to-disk  -  Transfer a LiveOS image so that it's bootable off of
                           a USB/SD device.

    The script may be run in simplest form with just the two arguments:

             <source>
                 This may be the filesystem path to a LiveOS .iso image file,
                 such as from a CD-ROM, DVD, or download.  It could also be the
                 device node reference for the mount point of another LiveOS
                 filesystem, including the currently-running one (such as a
                 booted Live CD/DVD/USB, where /run/initramfs/livedev links to
                 the booted LiveOS device).

             <target device>
                 This should be the device partition name for the attached,
                 target device, such as /dev/sdb1 or /dev/sdc1.  (Issue the
                 df -Th command to get a listing of the mounted partitions,
                 where you can confirm the filesystem types, available space,
                 and device names.)  Be careful to specify the correct device,
                 or you may overwrite important data on another disk!

    To execute the script to completion, you will need to run it with root user
    permissions.
    SYSLINUX must be installed on the computer running this script.

    DESCRIPTION

    livecd-iso-to-disk installs a Live CD/DVD/USB image (LiveOS) onto a USB/SD
    storage device (or any storage partition that will boot with a SYSLINUX
    bootloader).  The target storage device can then boot the installed
    operating system on systems that support booting via the USB or the SD
    interface.  The script requires a LiveOS source image and a target storage
    device.  The source image may be either a LiveOS .iso file, the currently-
    running LiveOS image, the device node reference for an attached device
    installed with a LiveOS image, or a file backed by a block device installed
    with a LiveOS image.  If the operating system supports persistent overlays
    for saving system changes, a pre-sized overlay may be included with the
    installed image.

    Unless you request the --format option, installing an image does not
    destroy data outside of the LiveOS, syslinux, & EFI directories on your
    target device.  This allows one to maintain other files on the target disk
    outside of the LiveOS filesystem.

    LiveOS images employ embedded filesystems through the Device-mapper
    component of the Linux kernel.  The filesystems are embedded within files
    in the /LiveOS/ directory of the storage device.  The /LiveOS/squashfs.img
    file is the default, compressed filesystem containing one directory and the
    file /LiveOS/ext3fs.img that contains the root filesystem for the
    distribution.  These are read-only filesystems that are usually fixed in
    size to within +1 GiB of the size of the full root filesystem at build time.
    At boot time, a Device-mapper snapshot with a default 0.5 GiB, in-memory,
    read-write overlay is created for the root filesystem.  Optionally, one may
    specify a fixed-size, persistent on disk overlay to hold changes to the
    root filesystem.  The build-time size of the root filesystem will limit the
    maximum size of the working root filesystem--even if an overlay file larger
    than the apparent free space on the root filesystem is used.  *Note well*
    that deletion of any original files in the read-only root filesystem does
    not recover any storage space on your LiveOS device.  Storage in the
    persistent /LiveOS/overlay-<device_id> file is allocated as needed, but the
    system will crash *without warning* and fail to boot once the overlay has
    been totally consumed.  If significant changes or updates to the root
    filesystem are to be made, carefully watch the fraction of space allocated
    in the overlay by issuing the 'dmsetup status' command at a command line of
    the running LiveOS image.  Some consumption of root filesystem and overlay
    space can be avoided by specifying a persistent home filesystem for user
    files, which will be saved in a fixed-size /LiveOS/home.img file.  This
    filesystem is encrypted by default.  (One may bypass encryption with the
    --unencrypted-home option.)  This filesystem is mounted on the /home
    directory.  When its storage space is full, out-of-space warnings will be
    issued by the operating system.

    OPTIONS

    --help
        Displays usage information and exits.

    --noverify
        Disables the image validation process that occurs before the image is
        copied from the original Live CD .iso image.  When this option is
        specified, the image is not verified before it is copied onto the
        target storage device.

    --format
        Formats the target device and creates an MS-DOS partition table (or GPT
        partition table, if the --efi option is passed).

    --msdos
        Forces format to use the msdos (vfat) filesystem instead of ext4.

    --reset-mbr
        Sets the Master Boot Record (MBR) of the target storage device to the
        mbr.bin file from the installation system's syslinux directory.  This
        may be helpful in recovering a damaged or corrupted device.

    --efi
        Creates a GUID partition table when --format is passed, and installs a
        hybrid Extensible Firmware Interface (EFI)/MBR bootloader on the disk.
        This is necessary for most Intel Macs.

    --skipcopy
        Skips the copying of the live image to the target device, bypassing the
        actions of the --format, --overlay-size-mb, --home-size-mb, &
        --swap-size-mb options, if present on the command line. (The --skipcopy
        option is useful while testing the script, in order to avoid repeated
        and lengthy copy commands, or with --reset-mbr, to repair the boot
        configuration files on a previously installed LiveOS device.)

    --force
        This option allows the installation script to bypass a delete
        confirmation dialog in the event that a pre-existing LiveOS directory
        is found on the target device.

    --xo
        Used to prepare an image for the OLPC XO-1 laptop with its compressed,
        JFFS2 filesystem.  Do not use the following options with --xo:
            --overlay-size-mb <size>, home-size-mb <size>, --delete-home,
            --compress

    --xo-no-home
        Used together with the --xo option to prepare an image for an OLPC XO
        laptop with the home directory on an SD card instead of the internal
        flash storage.

    --timeout <time>
        Modifies the bootloader's timeout value, which indicates how long to
        pause at the boot: prompt before booting automatically.  This overrides
        the value set during iso creation.  Units are 1/10 s.  The timeout is
        canceled when any key is pressed, the assumption being that the user
        will complete the command line.  A timeout of zero will disable the
        timeout completely.

    --totaltimeout <time>
        Adds a bootloader totaltimeout, which indicates how long to wait before
        booting automatically.  This is used to force an automatic boot.  This
        timeout cannot be canceled by the user.  Units are 1/10 s.

    --extra-kernel-args <args>
        Specifies additional kernel arguments, <args>, that will be inserted
        into the syslinux and EFI boot configurations.  Multiple arguments
        should be specified in one string, i.e.,
            --extra-kernel-args \"arg1 arg2 ...\"

    --multi
        Used when installing multiple images, to signal configuration of boot
        files for the image in the --livedir <dir> parameter.

    --livedir <dir>
        Used when multiple LiveOS images are installed on a device to designate
        the directory <dir> for the particular image.

    --compress   (default state for the original root filesystem)
        The default, compressed SquashFS filesystem image is copied on
        installation.  (This option has no effect if the source filesystem is
        already expanded.)

    --skipcompress   (default option when  --xo is specified)
        Expands the source SquashFS.img on installation into the read-only
        /LiveOS/ext3fs.img root filesystem image file.  This avoids the system
        overhead of decompression during use at the expense of storage space.

    --swap-size-mb <size>
        Sets up a swap file of <size> mebibytes (integer values only) on the
        target device.  A maximum <size> of 4095 MiB is permitted for vfat-
        formatted devices.

    --overlay-size-mb <size>
        Specifies creation of a filesystem overlay of <size> mebibytes (integer
        values only).  The overlay makes persistent storage available to the
        live operating system, if the operating system supports it.  The overlay
        holds a snapshot of changes to the root filesystem.  *Note well* that
        deletion of any original files in the read-only root filesystem does not
        recover any storage space on your LiveOS device.  Storage in the
        persistent /LiveOS/overlay-<device_id> file is allocated as needed, but
        the system will crash *without warning* and fail to boot once the
        overlay has been totally consumed.  If significant changes or updates
        to the root filesystem are to be made, carefully watch the fraction of
        space allocated in the overlay by issuing the 'dmsetup status' command
        at a command line of the running LiveOS image.  Some consumption of root
        filesystem and overlay space can be avoided by specifying a persistent
        home filesystem for user files, see --home-size-mb below.  The target
        storage device must have enough free space for the image and the
        overlay.  A maximum <size> of 4095 MiB is permitted for vfat-formatted
        devices.  If there is not enough room on your device, you will be
        given information to help in adjusting your settings.

    --home-size-mb <size>
        Specifies creation of a home filesystem of <size> mebibytes (integer
        values only).  A persistent home directory will be stored in the
        /LiveOS/home.img filesystem image file.  This filesystem is encrypted
        by default and not compressed  (one may bypass encryption with the
        --unencrypted-home option).  When the home filesystem storage space is
        full, one will get out-of-space warnings from the operating system.
        The target storage device must have enough free space for the image,
        any overlay, and the home filesystem.  Note that the --delete-home
        option must also be selected to replace an existing persistent home
        with a new, empty one.  A maximum <size> of 4095 MiB is permitted for
        vfat-formatted devices.  If there is not enough room on your device,
        you will be given information to help in adjusting your settings.

    --delete-home
        One must explicitly select this option in the case where there is an
        existing persistent home filesystem on the target device and the
        --home-size-mb <size> option is selected to create an empty, new home
        filesystem.  This prevents unwitting deletion of user files.

    --crypted-home   (default that only applies to new home-size-mb requests)
        Sets the default option to encrypt a new persistent home filesystem
        when --home-size-mb <size> is specified.

    --unencrypted-home
        Prevents the default option to encrypt a new persistent home directory
        filesystem.

    --updates <updates.img>
        Setup inst.updates to point to an updates image on the device. Anaconda
        uses this for testing updates to an iso without needing to make a new iso.

    --ks <kickstart>
        Setup inst.ks to point to an kickstart file on the device. Use this for
        automating package installs on boot.

    --label <label>
        Specifies a specific filesystem label instead of default LIVE. Useful
        when you do unattended installs that pass a label to inst.ks.

    CONTRIBUTORS

    livecd-iso-to-disk: David Zeuthen, Jeremy Katz, Douglas McClendon,
                        Chris Curran and other contributors.
                        (See the AUTHORS file in the source distribution for
                        the complete list of credits.)

    BUGS

    Report bugs to the mailing list
    http://admin.fedoraproject.org/mailman/listinfo/livecd or directly to
    Bugzilla http://bugzilla.redhat.com/bugzilla/ against the Fedora product,
    and the livecd-tools component.

    COPYRIGHT

    Copyright (C) Fedora Project 2008, 2009, 2010 and various contributors.
    This is free software. You may redistribute copies of it under the terms of
    the GNU General Public License http://www.gnu.org/licenses/gpl.html.
    There is NO WARRANTY, to the extent permitted by law.

    SEE ALSO

    livecd-creator, project website http://fedoraproject.org/wiki/FedoraLiveCD
    "
    exit 1
}

cleanup() {
    sleep 2
    [ -d "$SRCMNT" ] && umount $SRCMNT && rmdir $SRCMNT
    [ -d "$TGTMNT" ] && umount $TGTMNT && rmdir $TGTMNT
}

exitclean() {
    RETVAL=$?
    if [ -d "$SRCMNT" ] || [ -d "$TGTMNT" ];
    then
        [ "$RETVAL" = 0 ] || echo "Cleaning up to exit..."
        cleanup
    fi
    exit $RETVAL
}

isdevloop() {
    [ x"${1#/dev/loop}" != x"$1" ]
}

# Return the matching file with the right case, or original string
# which, when checked with -f or -e doesn't actually exist.
nocase_path() {
    shopt -s nocaseglob
    echo $1
    shopt -u nocaseglob
}


run_parted() {
    LC_ALL=C parted "$@"
}

getdisk() {
    DEV=$1

    if isdevloop "$DEV"; then
        [[ -b $DEV ]] && loop=True
    fi

    p=$(udevadm info -q path -n $DEV)
    if [ $? -gt 0 ]; then
        echo "Error getting udev path to $DEV"
        exitclean
    fi
    if [[ -n $loop ]]; then
        node=${DEV#/dev/loop}
        p=$(basename $DEV)
        device=loop${node%p*}
    elif [ -e /sys/$p/device ]; then
        device=$(basename /sys/$p)
    else
        device=$(basename $(readlink -f /sys/$p/../))
    fi
    if [ -z "$device" -o ! -e /sys/block/$device -o ! -e /dev/$device ]; then
        echo "Error finding block device of $DEV.  Aborting!"
        exitclean
    fi

    device="/dev/$device"
    # FIXME: weird dev names could mess this up I guess
    p=/dev/$(basename $p)
    p=${p##$device}
    # Strip off leading p from partnum, eg. with /dev/mmcblk0p1
    partnum=${p##p}
}

get_partition1() {
    # Get the name of partition one. Devices that end with a digit need to have
    # a 'p' appended before the partition number.
    local dev=$1

    if [[ $dev =~ .*[0-9]+$ ]]; then
        echo -n "${dev}p1"
    else
        echo -n "${dev}1"
    fi
}

resetMBR() {
    getdisk $1
    # if efi, we need to use the hybrid MBR
    if [ -n "$efi" ]; then
        if [ -f /usr/lib/syslinux/gptmbr.bin ]; then
            cat /usr/lib/syslinux/gptmbr.bin > $device
        elif [ -f /usr/share/syslinux/gptmbr.bin ]; then
            cat /usr/share/syslinux/gptmbr.bin > $device
        else
            echo "Could not find gptmbr.bin (syslinux)"
            exitclean
        fi
        # Make it bootable on EFI and BIOS
        run_parted -s $device set $partnum legacy_boot on
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
    # Wait for changes to show up/settle down
    /sbin/udevadm settle
}

checkMBR() {
    getdisk $1

    bs=$(mktemp /tmp/bs.XXXXXX)
    dd if=$device of=$bs bs=512 count=1 2>/dev/null || exit 2

    mbrword=$(hexdump -n 2 $bs |head -n 1|awk {'print $2;'})
    rm -f $bs
    if [ "$mbrword" = "0000" ]; then
        if [ -z "$format" ]; then
            echo "MBR appears to be blank."
            echo "Press Enter to replace the MBR and continue or ctrl-c to abort"
            read
        fi
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

    if [ "$(/sbin/fdisk -l $device 2>/dev/null |grep -m1 $dev |awk {'print $2;'})" != "*" ]; then
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
        "$(/sbin/pvs -o vg_name --noheadings $dev* 2>/dev/null || :)" ]; then
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
    umount ${device}* &> /dev/null || :
    wipefs -a ${device}
    run_parted -s $device mklabel gpt
    partinfo=$(run_parted -s -m $device "unit MB print" |grep ^$device:)
    dev_size=$(echo $partinfo |cut -d : -f 2 |sed -e 's/MB$//')
    p1_size=$(($dev_size - 3))

    if [ $p1_size -le 0 ]; then
        echo "Your device isn't big enough to hold $SRC"
        echo "It is $(($p1_size * -1)) MB too small"
        exitclean
    fi
    p1_start=1
    p1_end=$(($p1_size + 1))
    run_parted -s $device u MB mkpart '"EFI System Partition"' fat32 $p1_start $p1_end set 1 boot on
    # Sometimes automount can be _really_ annoying.
    echo "Waiting for devices to settle..."
    /sbin/udevadm settle
    sleep 5
    TGTDEV=$(get_partition1 ${device})
    umount $TGTDEV &> /dev/null || :
    /sbin/mkdosfs -n $label $TGTDEV
    TGTLABEL="UUID=$(/sbin/blkid -s UUID -o value $TGTDEV)"
}

createMSDOSLayout() {
    dev=$1
    getdisk $dev

    echo "WARNING: THIS WILL DESTROY ANY DATA ON $device!!!"
    echo "Press Enter to continue or ctrl-c to abort"
    read
    umount ${device}* &> /dev/null || :
    wipefs -a ${device}
    run_parted -s $device mklabel msdos
    partinfo=$(run_parted -s -m $device "unit MB print" |grep ^$device:)
    dev_size=$(echo $partinfo |cut -d : -f 2 |sed -e 's/MB$//')
    p1_size=$(($dev_size - 3))

    if [ $p1_size -le 0 ]; then
        echo "Your device isn't big enough to hold $SRC"
        echo "It is $(($p1_size * -1)) MB too small"
        exitclean
    fi
    p1_start=1
    p1_end=$(($p1_size + 1))
    run_parted -s $device u MB mkpart primary fat32 $p1_start $p1_end set 1 boot on
    # Sometimes automount can be _really_ annoying.
    echo "Waiting for devices to settle..."
    /sbin/udevadm settle
    sleep 5
    TGTDEV=$(get_partition1 ${device})
    umount $TGTDEV &> /dev/null || :
    /sbin/mkdosfs -n LIVE $TGTDEV
    TGTLABEL="UUID=$(/sbin/blkid -s UUID -o value $TGTDEV)"
}

createEXTFSLayout() {
    dev=$1
    getdisk $dev

    echo "WARNING: THIS WILL DESTROY ANY DATA ON $device!!!"
    echo "Press Enter to continue or ctrl-c to abort"
    read
    umount ${device}* &> /dev/null || :
    wipefs -a ${device}
    run_parted -s $device mklabel msdos
    partinfo=$(run_parted -s -m $device "u MB print" |grep ^$device:)
    dev_size=$(echo $partinfo |cut -d : -f 2 |sed -e 's/MB$//')
    p1_size=$(($dev_size - 3))

    if [ $p1_size -le 0 ]; then
        echo "Your device isn't big enough to hold $SRC"
        echo "It is $(($p1_size * -1)) MB too small"
        exitclean
    fi
    p1_start=1
    p1_end=$(($p1_size + 1))
    run_parted -s $device u MB mkpart primary ext2 $p1_start $p1_end set 1 boot on
    # Sometimes automount can be _really_ annoying.
    echo "Waiting for devices to settle..."
    /sbin/udevadm settle
    sleep 5
    TGTDEV=$(get_partition1 ${device})
    umount $TGTDEV &> /dev/null || :

    # Check extlinux version
    if extlinux -v 2>&1 | grep -q 'extlinux 3'; then
        mkfs=/sbin/mkfs.ext3
    else
        mkfs=/sbin/mkfs.ext4
    fi
    $mkfs -L $label $TGTDEV
    TGTLABEL="UUID=$(/sbin/blkid -s UUID -o value $TGTDEV)"
}

checkGPT() {
    dev=$1
    getdisk $dev

    if [ "$(run_parted -s -m $device p 2>/dev/null |grep -ic :gpt:)" -eq "0" ]; then
        echo "EFI boot requires a GPT partition table."
        echo "This can be done manually or you can run with --format"
        exitclean
    fi

    partinfo=$(run_parted -s -m $device "print" |grep ^$partnum:)
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

    TGTFS=$(/sbin/blkid -s TYPE -o value $dev || :)
    if [ "$TGTFS" != "vfat" ] && [ "$TGTFS" != "msdos" ]; then
        if [ "$TGTFS" != "ext2" ] && [ "$TGTFS" != "ext3" ] && [ "$TGTFS" != "ext4" ] && [ "$TGTFS" != "btrfs" ]; then
            echo "Target filesystem ($dev:$TGTFS) must be vfat, ext[234] or btrfs"
            exitclean
        fi
    fi

    if [ "$TGTFS" = "ext2" -o "$TGTFS" = "ext3" -o "$TGTFS" = "ext4" ] && [ ! -x /usr/sbin/extlinux ]; then
        echo "Target filesystem ($TGTFS) requires syslinux-extlinux to be installed."
        exitclean
    fi


    TGTLABEL=$(/sbin/blkid -s LABEL -o value $dev)
    if [ "$TGTLABEL" != "$label" ]; then
        if [ "$TGTFS" = "vfat" -o "$TGTFS" = "msdos" ]; then
            /sbin/dosfslabel $dev $label
            if [ $? -gt 0 ]; then
                echo "dosfslabel failed on $dev, device not setup"
                exitclean
            fi
        elif [ "$TGTFS" = "ext2" -o "$TGTFS" = "ext3" -o "$TGTFS" = "ext4" ]; then
            /sbin/e2label $dev $label
            if [ $? -gt 0 ]; then
                echo "e2label failed on $dev, device not setup"
                exitclean
            fi
        else
            echo "Unknown filesystem type. Try setting its label to $label and re-running"
            exitclean
        fi
    fi

    # Use UUID if available
    TGTUUID=$(/sbin/blkid -s UUID -o value $dev)
    if [ -n "$TGTUUID" ]; then
        TGTLABEL="UUID=$TGTUUID"
    else
        TGTLABEL="LABEL=$label"
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
    check=($(syslinux --version 2>&1)) || :
    if [[ 'syslinux' != $check ]]; then
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
        shortusage
        exit 1
    fi
}

if [ $(id -u) != 0 ]; then
    echo "You need to be root to run this script"
    exit 1
fi

detectsrctype() {
    if [[ -e "$SRCMNT/Packages" ]]; then
        echo "/Packages found, will copy source packages to target"
        packages=1
    fi
    if [[ -e "$SRCMNT/LiveOS/squashfs.img" ]]; then
        # LiveOS style boot image
        srctype=live
        return
    fi
    if [ -e $SRCMNT/images/install.img -o -e $SRCMNT/isolinux/initrd.img ]; then
        if [ -n "$packages" ]; then
            srctype=installer
        else
            srctype=netinst
        fi
        imgtype=install
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
    if [ -x /usr/bin/rsync ]; then
        rsync --inplace -P "$1" "$2"
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

set -e
set -o pipefail
trap exitclean EXIT
shopt -s extglob

cryptedhome=1
keephome=1
homesizemb=0
swapsizemb=0
overlaysizemb=0
srctype=
imgtype=
packages=
LIVEOS=LiveOS
HOMEFILE="home.img"
updates=
ks=
label="LIVE"

while true ; do
    case $1 in
        --help | -h | -?)
            usage
            ;;
        --noverify)
            noverify=1
            ;;
        --format)
            format=1
            ;;
        --msdos)
            usemsdos=1
            ;;
        --reset-mbr|--resetmbr)
            resetmbr=1
            ;;
        --efi|--mactel)
            efi=1
            ;;
        --skipcopy)
            skipcopy=1
            ;;
        --force)
            force=1
            ;;
        --xo)
            xo=1
            skipcompress=1
            ;;
        --xo-no-home)
            xonohome=1
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
        --extra-kernel-args)
            kernelargs=$2
            shift
            ;;
        --multi)
            multi=1
            ;;
        --livedir)
            LIVEOS=$2
            shift
            ;;
        --compress)
            skipcompress=""
            ;;
        --skipcompress)
            skipcompress=1
            ;;
        --swap-size-mb)
            checkint $2
            swapsizemb=$2
            shift
            ;;
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
        --crypted-home)
            cryptedhome=1
            ;;
        --unencrypted-home)
            cryptedhome=""
            ;;
        --delete-home)
            keephome=""
            ;;
        --updates)
            updates=$2
            shift
            ;;
        --ks)
            ks=$2
            shift
            ;;
        --label)
            label=$2
            shift
            ;;
        --*)
            echo "invalid arg -- $1"
            shortusage
            exit 1
            ;;
        *)
            break
            ;;
    esac
    shift
done

if [ $# -ne 2 ]; then
    echo "Missing arguments"
    shortusage
    exit 1
fi

SRC=$(readlink -f "$1") || :
TGTDEV=$(readlink -f "$2") || :

if [ -z "$SRC" ]; then
    echo "Missing source"
    shortusage
    exit 1
fi

if [ ! -b "$SRC" -a ! -f "$SRC" ]; then
    echo "$SRC is not a file or block device"
    shortusage
    exit 1
fi

if [ -z "$TGTDEV" ]; then
    echo "Missing target device"
    shortusage
    exit 1
fi

if [ ! -b "$TGTDEV" ]; then
    echo "$TGTDEV is not a block device"
    shortusage
    exit 1
fi

if [ -z "$noverify" ]; then
    # verify the image
    echo "Verifying image..."
    if !  checkisomd5 --verbose "$SRC"; then
        echo "Are you SURE you want to continue?"
        echo "Press Enter to continue or ctrl-c to abort"
        read
    fi
fi

# do some basic sanity checks.
checkMounted $TGTDEV

# FIXME: would be better if we had better mountpoints
SRCMNT=$(mktemp -d /media/srctmp.XXXXXX)
if [ -b "$SRC" ]; then
    mount -o ro "$SRC" $SRCMNT || exitclean
elif [ -f "$SRC" ]; then
    mount -o loop,ro "$SRC" $SRCMNT || exitclean
else
    echo "$SRC is not a file or block device."
    exitclean
fi
# Figure out what needs to be done based on the source image
detectsrctype

# Format the device
if [ -n "$format" -a -z "$skipcopy" ]; then
    checkLVM $TGTDEV

    if [ -n "$efi" ]; then
        createGPTLayout $TGTDEV
    elif [ -n "$usemsdos" -o ! -x /sbin/extlinux ]; then
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


if [ "$overlaysizemb" -gt 0 ]; then
    if [ "$TGTFS" = "vfat" -a "$overlaysizemb" -gt 4095 ]; then
        echo "Can't have an overlay of 4095 MB or greater on VFAT"
        exitclean
    fi
    LABEL=$(/sbin/blkid -s LABEL -o value $TGTDEV)
    if [[ "$LABEL" =~ ( ) ]]; then
        echo "The LABEL($LABEL) on $TGTDEV has spaces in it, which do not work with the overlay"
        echo "You can re-format or use dosfslabel/e2fslabel to change it"
        exitclean
    fi
fi

if [ "$homesizemb" -gt 0 -a "$TGTFS" = "vfat" ]; then
    if [ "$homesizemb" -gt 4095 ]; then
        echo "Can't have a home filesystem greater than 4095 MB on VFAT"
        exitclean
    fi
fi

if [ "$swapsizemb" -gt 0 -a "$TGTFS" = "vfat" ]; then
    if [ "$swapsizemb" -gt 4095 ]; then
        echo "Can't have a swap file greater than 4095 MB on VFAT"
        exitclean
    fi
fi

TGTMNT=$(mktemp -d /media/tgttmp.XXXXXX)
mount $mountopts $TGTDEV $TGTMNT || exitclean

trap exitclean SIGINT SIGTERM

if [ -f "$TGTMNT/$LIVEOS/$HOMEFILE" -a -n "$keephome" -a "$homesizemb" -gt 0 ]; then
    echo "ERROR: Requested keeping existing /home and specified a size for /home"
    echo "Please either don't specify a size or specify --delete-home"
    exitclean
fi

if [ -n "$efi" ]; then
    if [ -d $SRCMNT/EFI/BOOT ]; then
        EFI_BOOT="/EFI/BOOT"
    elif [ -d $SRCMNT/EFI/boot ]; then
        EFI_BOOT="/EFI/boot"
    else
        echo "ERROR: This live image does not support EFI booting"
        exitclean
    fi
fi

# let's try to make sure there's enough room on the target device
if [[ -d $TGTMNT/$LIVEOS ]]; then
    tbd=($(du -B 1M $TGTMNT/$LIVEOS))
    if [[ -s $TGTMNT/$LIVEOS/$HOMEFILE ]] && [[ -n $keephome ]]; then
        homesize=($(du -B 1M $TGTMNT/$LIVEOS/$HOMEFILE))
        tbd=$((tbd - homesize))
    fi
else
    tbd=0
fi

if [[ live == $srctype ]]; then
   targets="$TGTMNT/$SYSLINUXPATH"
   [[ -n $efi ]] && targets+=" $TGTMNT$EFI_BOOT"
   [[ -n $xo ]] && targets+=" $TGTMNT/boot/olpc.fth"
   target_size=$(du -s -c -B 1M $targets 2> /dev/null | awk '/total$/ {print $1;}') || :
   tbd=$((tbd + target_size))
fi

if [[ -n $skipcompress ]] && [[ -s $SRCMNT/LiveOS/squashfs.img ]]; then
    if mount -o loop $SRCMNT/LiveOS/squashfs.img $SRCMNT; then
        livesize=($(du -B 1M --apparent-size $SRCMNT/LiveOS/ext3fs.img))
        umount $SRCMNT
        if ((livesize > 4095)) &&  [[ vfat == $TGTFS ]]; then
            echo "
            An uncompressed image size greater than 4095 MB is not suitable
            for a VFAT-formatted device.  The compressed SquashFS will be
            copied to the target device.
            "
            skipcompress=""
            livesize=0
        fi
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
    sources="$SRCMNT/LiveOS/ext3fs.img $SRCMNT/LiveOS/osmin.img"
    [[ -z $skipcompress ]] && sources+=" $SRCMNT/LiveOS/squashfs.img"
    sources+=" $SRCMNT/isolinux $SRCMNT/syslinux"
    [[ -n $efi ]] && sources+=" $SRCMNT$EFI_BOOT"
    [[ -n $xo ]] && sources+=" $SRCMNT/boot/olpc.fth"
    source_size=$(du -s -c -B 1M "$thisScriptpath" $sources 2> /dev/null | awk '/total$/ {print $1;}') || :
    livesize=$((livesize + source_size))
fi

freespace=$(df -B 1M --total $TGTDEV | awk '/^total/ {print $4;}')

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
            printf "  + Swap file size: %14s\n" $swapsizemb
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
    if [ -e "$TGTMNT/$(basename "$SRC")" ]; then
        tbd=$(($tbd + $(du -s -B 1M "$TGTMNT/$(basename "$SRC")" | awk {'print $1;'})))
    fi
    echo "Size of $imgpath: $installimgsize"
    echo "Available space: $((freespace + tbd))"
    if (( installimgsize > ((freespace + tbd)) )); then
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
[ -n "$efi" -a ! -d $TGTMNT$EFI_BOOT ] && mkdir -p $TGTMNT$EFI_BOOT

# Live image copy
if [ "$srctype" = "live" -a -z "$skipcopy" ]; then
    echo "Copying live image to target device."
    [ ! -d $TGTMNT/$LIVEOS ] && mkdir $TGTMNT/$LIVEOS
    [ -n "$keephome" -a -f "$TGTMNT/$HOMEFILE" ] && mv $TGTMNT/$HOMEFILE $TGTMNT/$LIVEOS/$HOMEFILE
    if [ -n "$skipcompress" -a -f $SRCMNT/LiveOS/squashfs.img ]; then
        mount -o loop $SRCMNT/LiveOS/squashfs.img $SRCMNT || exitclean
        copyFile $SRCMNT/LiveOS/ext3fs.img $TGTMNT/$LIVEOS/ext3fs.img || {
            umount $SRCMNT ; exitclean ; }
        umount $SRCMNT
    elif [ -f $SRCMNT/LiveOS/squashfs.img ]; then
        copyFile $SRCMNT/LiveOS/squashfs.img $TGTMNT/$LIVEOS/squashfs.img || exitclean
    elif [ -f $SRCMNT/LiveOS/ext3fs.img ]; then
        copyFile $SRCMNT/LiveOS/ext3fs.img $TGTMNT/$LIVEOS/ext3fs.img || exitclean
    fi
    if [ -f $SRCMNT/LiveOS/osmin.img ]; then
        copyFile $SRCMNT/LiveOS/osmin.img $TGTMNT/$LIVEOS/osmin.img || exitclean
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
    echo "Setting up $EFI_BOOT"
    cp -r $SRCMNT$EFI_BOOT/* $TGTMNT$EFI_BOOT

    # The GRUB EFI config file can be one of:
    #   boot?*.conf
    #   BOOT?*.conf
    #   grub.cfg
    if [ -e $TGTMNT$EFI_BOOT/grub.cfg ]; then
        BOOTCONFIG_EFI=$TGTMNT$EFI_BOOT/grub.cfg
    elif [ -e $(nocase_path "$TGTMNT$EFI_BOOT/boot*.conf") ]; then
        BOOTCONFIG_EFI=$(nocase_path "$TGTMNT$EFI_BOOT/boot*.conf")
    else
        echo "Unable to find EFI config file."
        exitclean
    fi
    rm -f $TGTMNT$EFI_BOOT/grub.conf

    # On some images (RHEL) the BOOT*.efi file isn't in $EFI_BOOT, but is in
    # the eltorito image, so try to extract it if it is missing

    # test for presence of *.efi grub binary
    if [ ! -f $(nocase_path "$TGTMNT$EFI_BOOT/boot*efi") ]; then
        if [ ! -x /usr/bin/dumpet ]; then
            echo "No /usr/bin/dumpet tool found. EFI image will not boot."
            echo "Source media is missing grub binary in /EFI/BOOT/*EFI"
            exitclean
        else
            # dump the eltorito image with dumpet, output is $SRC.1
            dumpet -i "$SRC" -d
            EFIMNT=$(mktemp -d /media/srctmp.XXXXXX)
            mount -o loop "$SRC".1 $EFIMNT

            if [ -f $(nocase_path "$EFIMNT$EFI_BOOT/boot*efi") ]; then
                cp $(nocase_path "$EFIMNT$EFI_BOOT/boot*efi") $TGTMNT$EFI_BOOT
            else
                echo "No BOOT*.EFI found in eltorito image. EFI will not boot"
                umount $EFIMNT
                rm "$SRC".1
                exitclean
            fi
            umount $EFIMNT
            rm "$SRC".1
        fi
    fi
fi

# DVD installer copy
if [ -z "$skipcopy" -a \( "$srctype" = "installer" -o "$srctype" = "netinst" \) ]; then
    echo "Copying DVD image to target device."
    mkdir -p $TGTMNT/images/
    if [ "$imgtype" = "install" ]; then
        for img in install.img updates.img product.img; do
            if [ -e $SRCMNT/images/$img ]; then
                copyFile $SRCMNT/images/$img $TGTMNT/images/$img || exitclean
            fi
        done
    fi
fi

# Copy packages over.
# Before Fedora17 we could copy the .iso and setup a repo=
# F17 and later look for repodata on the source media.
# The presence of packages and LiveOS indicates F17 or later.
# And then in F23 the LiveOS/squashfs.img moved back to images/install.img
# So copy over Packages, repodata and all other top level directories, anaconda
# should detect them and use them automatically.
if [ -n "$packages" -a -z "$skipcopy" ]; then
    echo "Copying package data from $SRC to device"
    rsync --inplace -rLDP --exclude EFI/ --exclude images/ --exclude isolinux/ \
        --exclude TRANS.TBL --exclude LiveOS/ "$SRCMNT/" "$TGTMNT/"
    echo "Waiting for device to finish writing"
    sync
fi

if [ "$srctype" = "live" ]; then
    # Copy this installer script.
    cp -fT "$thisScriptpath" $TGTMNT/$LIVEOS/livecd-iso-to-disk
    chmod +x $TGTMNT/$LIVEOS/livecd-iso-to-disk &> /dev/null || :

    # When the source is an installed Live USB/SD image, restore the boot config
    # file to a base state before updating.
    if [[ -d $SRCMNT/syslinux/ ]]; then
        echo "Preparing boot config file."
        sed -i -e "s/root=live:[^ ]*/root=live:CDLABEL=name/"\
               -e "s/\(r*d*.*live.*ima*ge*\) .* quiet/\1 quiet/"\
                    $BOOTCONFIG $BOOTCONFIG_EFI
        sed -i -e "s/^timeout.*$/timeout\ 100/"\
               -e "/^totaltimeout.*$/d" $BOOTCONFIG
    fi
fi

# Setup the updates.img
if [ -n "$updates" ]; then
    copyFile "$updates" "$TGTMNT/updates.img"
    kernelargs+=" inst.updates=hd:$TGTLABEL:/updates.img"
fi

# Setup the kickstart
if [ -n "$ks" ]; then
    copyFile "$ks" "$TGTMNT/ks.cfg"
    kernelargs+=" inst.ks=hd:$TGTLABEL:/ks.cfg"
fi

echo "Updating boot config file"
# adjust label and fstype
sed -i -e "s/CDLABEL=[^ ]*/$TGTLABEL/" -e "s/rootfstype=[^ ]*/rootfstype=$TGTFS/" -e "s/LABEL=[^ :]*/$TGTLABEL/" $BOOTCONFIG  $BOOTCONFIG_EFI
if [ -n "$kernelargs" ]; then
    sed -i -e "s;initrd.\?\.img;& ${kernelargs};" $BOOTCONFIG
    if [ -n "$efi" ]; then
        sed -i -e "s;vmlinuz.\?;& ${kernelargs} ;" $BOOTCONFIG_EFI
    fi
fi
if [ "$LIVEOS" != "LiveOS" ]; then
    sed -i -e "s;r*d*.*live.*ima*ge*;& live_dir=$LIVEOS;"\
              $BOOTCONFIG $BOOTCONFIG_EFI
fi

# EFI images are in $SYSLINUXPATH now
if [ -n "$efi" ]; then
    sed -i -e "s;/isolinux/;/$SYSLINUXPATH/;g" $BOOTCONFIG_EFI
    sed -i -e "s;/images/pxeboot/;/$SYSLINUXPATH/;g" $BOOTCONFIG_EFI
    sed -i -e "s;findiso;;g" $BOOTCONFIG_EFI
fi

# DVD Installer for netinst
if [ "$srctype" != "live" ]; then
    # install images will have already had their stage2 setup by the LABEL substitution
    # and non-install will have everything in the initrd
    if [ "$imgtype" != "install" ]; then
        # The initrd has everything, so no stage2
        sed -i -e "s;\S*stage2=\S*;;g" $BOOTCONFIG $BOOTCONFIG_EFI
    fi
fi

# Adjust the boot timeouts
if [ -n "$timeout" ]; then
    sed -i -e "s/^timeout.*$/timeout\ $timeout/" $BOOTCONFIG
fi
if [ -n "$totaltimeout" ]; then
    sed -i -e "/^timeout.*$/a\totaltimeout\ $totaltimeout" $BOOTCONFIG
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
    sed -i -e "s/r*d*.*live.*ima*ge*/& rd.live.overlay=${TGTLABEL} rw/"\
              $BOOTCONFIG $BOOTCONFIG_EFI
    sed -i -e "s/\ ro\ / /" $BOOTCONFIG  $BOOTCONFIG_EFI
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

        echo "Encrypting persistent /home"
        while ! cryptsetup luksFormat -y -q $loop; do :; done;

        echo "Please enter the password again to unlock the device"
        while ! cryptsetup luksOpen $loop EncHomeFoo; do :; done;

        mkfs.ext4 -j /dev/mapper/EncHomeFoo
        tune2fs -c0 -i0 -ouser_xattr,acl /dev/mapper/EncHomeFoo
        sleep 2
        cryptsetup luksClose EncHomeFoo
        losetup -d $loop
    else
        echo "Formatting unencrypted /home"
        mkfs.ext4 -F -j $TGTMNT/$LIVEOS/$HOMEFILE
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
        if [ -f "$TGTMNT$EFI_BOOT/BOOT.conf" ]; then
            cp -f $TGTMNT$EFI_BOOT/BOOTia32.conf $TGTMNT$EFI_BOOT/BOOT.conf
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

    # syslinux >= 6.02 requires also requires ldlinux.c32, libcom32.c32, libutil.c32
    # since the version of syslinux being used is the one on the host they may or may not
    # be available.
    for f in ldlinux.c32 libcom32.c32 libutil.c32; do
        if [ -f "/usr/share/syslinux/$f" ]; then
            cp /usr/share/syslinux/$f $TGTMNT/$SYSLINUXPATH/$f
        else
            echo "Failed to find /usr/share/syslinux/$f, USB may not boot."
        fi
    done

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
