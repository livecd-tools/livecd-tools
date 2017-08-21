#!/bin/bash
# Transfer a Live image so that it's bootable off of a USB/SD device.
# Copyright 2007-2012, 2017,  Red Hat, Inc.
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
                       [--timeout <duration>] [--totaltimeout <duration>]
                       [--nobootmsg] [--nomenu] [--extra-kernel-args <args>]
                       [--multi] [--livedir <dir>] [--compress]
                       [--compress] [--skipcompress] [--no-overlay]
                       [--overlay-size-mb <size>] [--reset-overlay]
                       [--home-size-mb <size>] [--delete-home] [--crypted-home]
                       [--unencrypted-home] [--swap-size-mb <size>]
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
                 device node reference, the LiveOS-containing directory path,
                 or the mount point for another LiveOS filesystem, including
                 the currently booted LiveOS device, which is mounted at
                 /run/initramfs/live.

             <target device>
                 This should be the device partition name for the attached,
                 target device, such as /dev/sdc1.  (Issue the df -Th command
                 to get a listing of mounted partitions, so you can confirm the
                 filesystem types, available space, and device names.)  Be
                 careful to specify the correct device, or you may overwrite
                 important data on another disk!

    To execute the script to completion, you will need to run it with root user
    permissions.
    SYSLINUX must be installed on the computer running this script.

    DESCRIPTION

    livecd-iso-to-disk installs a Live CD/DVD/USB image (LiveOS) onto a USB/SD
    storage device (or any storage partition that will boot with a SYSLINUX
    bootloader).  The target storage device can then boot the installed
    operating system on systems that support booting via the USB or the SD
    interface.  The script requires a LiveOS source image and a target storage
    device.  A loop device backed by a file may also be targeted for virtual
    block device installation.  The source image may be either a LiveOS .iso
    file, or another reference to a LiveOS image, such as the device node for
    an attached device installed with a LiveOS image, its mount point, a loop
    device backed by a file containing an installed LiveOS image, or even the
    currently-running LiveOS image.  A pre-sized overlay file for persisting
    root filesystem changes may be included with the installed image.

    Unless you request the --format option, installing an image does not
    destroy data outside of the LiveOS, syslinux, & EFI directories on your
    target device.  This allows one to maintain other files on the target disk
    outside of the LiveOS filesystem.

    LiveOS images employ embedded filesystems through the Device-mapper
    component of the Linux kernel.  The filesystems are embedded within files
    in the /LiveOS/ directory of the storage device.  The /LiveOS/squashfs.img
    file is the default, compressed filesystem containing one directory and the
    file /LiveOS/rootfs.img that contains the root filesystem for the
    distribution.  These are read-only filesystems that are usually fixed in
    size to within a few GiB of the size of the full root filesystem at build
    time.  At boot time, a Device-mapper snapshot with a default 0.5 GiB, in-
    memory, read-write overlay is created for the root filesystem.  Optionally,
    one may specify a fixed-size, persistent on disk overlay to hold changes to
    the root filesystem.  The build-time size of the root filesystem will limit
    the maximum size of the working root filesystem--even if supplied with an
    overlay file larger than the apparent free space on the root filesystem.
    *Note well* that deletion of any original files in the read-only root
    filesystem does not recover any storage space on your LiveOS device.
    Storage in the persistent /LiveOS/overlay-<device_id> file is allocated as
    needed.  If the overlay storage space is filled, the overlay will enter an
    'Overflow' state where the root filesystem will continue to operate in a
    read-only mode.  There will not be an explicit warning or signal when this
    happens, but applications may begin to report errors due to this
    restriction.  If significant changes or updates to the root filesystem are
    to be made, carefully watch the fraction of space allocated in the overlay
    by issuing the 'dmsetup status' command at a command line of the running
    LiveOS image.  Some consumption of root filesystem and overlay space can be
    avoided by specifying a persistent home filesystem for user files, which
    will be saved in a fixed-size /LiveOS/home.img file.  This filesystem is
    encrypted by default.  (One may bypass encryption with the
    --unencrypted-home option.)  This filesystem is mounted on the /home
    directory of the root filesystem.  When its storage space is filled,
    out-of-space warnings will be issued by the operating system.

    OPTIONS

    --help|-h|-?
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

    --reset-mbr|--resetmbr
        Sets the Master Boot Record (MBR) of the target storage device to the
        mbr.bin file from the installation system's syslinux directory.  This
        may be helpful in recovering a damaged or corrupted device.

    --efi|--mactel
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

    --timeout <duration>
        Modifies the bootloader's timeout value, which indicates how long to
        pause at the boot prompt before booting automatically.  This overrides
        the value set during iso creation.

            For SYSLINUX, a timeout unit is 1/10 second; the timeout is
            canceled when any key is pressed (the assumption being that the
            user will complete the command line); and a timeout of zero will
            disable the timeout completely.

            For EFI GRUB, the timeout unit is 1 second; timeout specifies the
            time to wait for keyboard input before booting the default menu
            entry. A timeout of '0' means to boot the default entry immediately
            without displaying the menu; and a timeout of '-1' means to wait
            indefinitely.

        Enter a desired timeout value in 1/10 second units (or '-1') and the
        appropriate value will be supplied to the configuration file.  For
        immediate booting, enter '-0' to avoid the ambiguity between systems.
        An entry of '-0' will result in an SYSLINUX setting of timeout 1 and
        totaltimeout 1.  '0' or '-1' will result in an SYSLINUX setting of '0'
        (disable timeout, that is, wait indefinitely), but '0' for EFI GRUB
        will mean immediate boot of the default, while '-1' will mean EFI GRUB
        waits indefinitely for a user selection.

    --totaltimeout <duration>
        Adds a SYSLINUX bootloader totaltimeout, which indicates how long to
        wait before booting automatically.  This is used to force an automatic
        boot.  This timeout cannot be canceled by the user.  Units are 1/10 s.
        A totaltimeout of zero will disable the timeout completely.
        (This setting is not available in EFI GRUB.)

    --nobootmsg
        Do not display boot.msg, usually, \"Press the <ENTER> key to begin the
        installation process.\"

    --nomenu
        Skip the boot menu, and automatically boot the 'linux' label item.

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
        /LiveOS/rootfs.img root filesystem image file.  This avoids the system
        overhead of decompression during use at the expense of storage space.

    --no-overlay   (effective only with skipcompress)
        Installs a kernel option, rd.live.overlay=none, that signals the live
        boot process to create a writable, linear Device-mapper target for an
        uncompressed /LiveOS/rootfs.img filesystem image file.  Read-write by
        default (unless a kernel argument of rd.live.overlay.readonly is given)
        this configuration avoids the complications of using an overlay of
        fixed size for persistence when storage format and space allows.

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

    --reset-overlay
        This option will reset the persistent overlay to an unallocated state.
        This might be used if installing a new or refreshed image onto a device
        with an existing overlay, and avoids the writing of a large file on a
        vfat-formatted device.  This option also renames the overlay to match
        the current device filesystem label and UUID.

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

    --swap-size-mb <size>
        Sets up a swap file of <size> mebibytes (integer values only) on the
        target device.  A maximum <size> of 4095 MiB is permitted for vfat-
        formatted devices.

    --updates <updates.img>
        Setup a kernel command line argument, inst.updates, to point to an
        updates image on the device. Used by Anaconda for testing updates to an
        iso without needing to make a new iso.

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

    Copyright 2008-2010, 2017, Fedora Project and various contributors.
    This is free software. You may redistribute copies of it under the terms of
    the GNU General Public License http://www.gnu.org/licenses/gpl.html.
    There is NO WARRANTY, to the extent permitted by law.

    SEE ALSO

    livecd-creator, project website http://fedoraproject.org/wiki/FedoraLiveCD
    "
    exit 1
}

if [[ ${*:0} =~ -help|\ -h|-\? ]]; then
    usage
fi

if [[ $(id -u) != 0 ]]; then
    echo '
    ALERT:  You need to have root user privileges to run this script.
    '
    exit 1
fi

if (( $# < 2 )); then
    shortusage
    echo '
    ERROR:  At minimum, a source and a target must be specified.'
    exit 1
fi

cleanup() {
    sleep 2
    [[ -d $SRCMNT ]] && umount $SRCMNT && rmdir $SRCMNT
    [[ -d $TGTMNT ]] && umount $TGTMNT && rmdir $TGTMNT
}

exitclean() {
    RETVAL=$?
    if [[ -d $SRCMNT ]] || [[ -d $TGTMNT ]]; then
        [[ $RETVAL == 0 ]] || echo "Cleaning up to exit..."
        cleanup
    fi
    exit $RETVAL
}

isdevloop() {
    [[ x${1#/dev/loop} != x$1 ]]
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
    if [[ -n $loop ]]; then
        node=${DEV#/dev/loop}
        p=${DEV##*/}
        device=loop${node%p*}
    elif [[ -e /sys/$p/device ]]; then
        device=${p##*/}
    else
        q=$(readlink -f /sys/$p/../)
        device=${q##*/}
    fi
    if [[ -z $device || ! -e /sys/block/$device || ! -e /dev/$device ]]; then
        echo "Error finding block device of $DEV.  Aborting!"
        exitclean
    fi

    device="/dev/$device"
    p=/dev/${p##*/}
    p=${p##$device}
    # Strip off leading p from partnum, e.g., with /dev/mmcblk0p1
    partnum=${p##p}
}

get_partition1() {
    # Return an appropriate name for partition one. Devices that end with a
    # digit need to have a 'p' appended before the partition number.
    local dev=$1

    if [[ $dev =~ .*[0-9]+$ ]]; then
        echo -n "${dev}p1"
    else
        echo -n "${dev}1"
    fi
}

resetMBR() {
    # If efi, we need to use the hybrid MBR.
    if [[ -n $efi ]]; then
        if [[ -f /usr/lib/syslinux/gptmbr.bin ]]; then
            cat /usr/lib/syslinux/gptmbr.bin > $device
        elif [[ -f /usr/share/syslinux/gptmbr.bin ]]; then
            cat /usr/share/syslinux/gptmbr.bin > $device
        else
            echo 'Could not find gptmbr.bin (SYSLINUX).'
            exitclean
        fi
    else
        if [[ -f /usr/lib/syslinux/mbr.bin ]]; then
            cat /usr/lib/syslinux/mbr.bin > $device
        elif [[ -f /usr/share/syslinux/mbr.bin ]]; then
            cat /usr/share/syslinux/mbr.bin > $device
        else
            echo 'Could not find mbr.bin (SYSLINUX).'
            exitclean
        fi
    fi
    # Wait for changes to show up/settle down.
    udevadm settle
}

checkMBR() {
    mbrword=($(hexdump -n 2 <<< \
        "$(dd if=$device bs=2 count=1 &> /dev/null)")) || exit 2
    if [[ ${mbrword[1]} == 0000 ]]; then
        printf '
        The Master Boot Record, MBR, appears to be blank.
        Do you want to replace the MBR on this device?
        Press Enter to continue, or Ctrl C to abort.'
        read
        resetMBR $1
    fi
    return 0
}

checkPartActive() {
    local dev=$1
    getdisk $dev

    # If we're installing to whole-disk and not a partition, then we
    # don't need to worry about being active.
    if [[ $dev == $device ]]; then
        return
    fi

    local partinfo=$(fdisk -l $device) 2>/dev/null
    partinfo=${partinfo##*$dev+( )}

    if [[ ${partinfo:0:1} != "*" ]]; then
        printf "\n        ATTENTION:
        The partition isn't marked bootable!\n
        You can mark the partition as bootable with the following commands:\n
        # parted %s
          (parted) toggle <N> boot
          (parted) quit\n\n" $device
        exitclean
    fi
}

createGPTLayout() {
    local dev=$1
    getdisk $dev

    printf '\n    WARNING: This will DESTROY All DATA on: %s !!\n
        Press Enter to continue, or Ctrl C to abort.\n' $device
    read
    umount ${device}* &> /dev/null || :
    wipefs -a ${device}
    run_parted --script $device mklabel gpt
    local sizeinfo=$(run_parted --script -m $device 'unit MiB print')
    sizeinfo=${sizeinfo#*${device}:}
    sizeinfo=${sizeinfo%%MiB*}
    run_parted --script $device unit MiB mkpart '"EFI System Partition"' fat32\
        4 $((sizeinfo - 2)) set 1 boot on
    # Sometimes automount can be _really_ annoying.
    echo 'Waiting for devices to settle...'
    udevadm settle
    sleep 5
    TGTDEV=$(get_partition1 ${device})
    umount $TGTDEV &> /dev/null || :
    mkfs.fat -n "$label" $TGTDEV
    udevadm settle
    # mkfs.fat silently truncates label to 11 bytes.
    label=$(lsblk -ndo LABEL $TGTDEV)
}

createMSDOSLayout() {
    local dev=$1
    getdisk $dev

    printf '\n    WARNING: This will DESTROY ALL DATA on: %s !!\n
        Press Enter to continue, or Ctrl C to abort.\n' $device
    read
    umount ${device}* &> /dev/null || :
    wipefs -a ${device}
    run_parted --script $device mklabel msdos
    local sizeinfo=$(run_parted --script -m $device 'unit MiB print')
    sizeinfo=${sizeinfo#*${device}:}
    sizeinfo=${sizeinfo%%MiB*}
    run_parted --script $device unit MiB mkpart primary fat32 \
        4 $((sizeinfo - 2)) set 1 boot on
    echo 'Waiting for devices to settle...'
    udevadm settle
    sleep 5
    TGTDEV=$(get_partition1 ${device})
    umount $TGTDEV &> /dev/null || :
    mkfs.fat -n "$label" $TGTDEV
    udevadm settle
    # mkfs.fat silently truncates label to 11 bytes.
    label=$(lsblk -ndo LABEL $TGTDEV)
}

createEXTFSLayout() {
    local dev=$1
    getdisk $dev

    printf '\n    WARNING: This will DESTROY ALL DATA on: %s !!\n
        Press Enter to continue, or Ctrl C to abort.\n' $device
    read
    umount ${device}* &> /dev/null || :
    wipefs -a ${device}
    run_parted --script $device mklabel msdos
    local sizeinfo=$(run_parted --script -m $device 'unit MiB print')
    sizeinfo=${sizeinfo#*${device}:}
    sizeinfo=${sizeinfo%%MiB*}
    run_parted --script $device unit MiB mkpart primary ext2 \
        4 $((sizeinfo - 2)) set 1 boot on
    echo 'Waiting for devices to settle...'
    udevadm settle
    sleep 5
    TGTDEV=$(get_partition1 ${device})
    umount $TGTDEV &> /dev/null || :

    # Check extlinux version
    if [[ $(extlinux -v 2>&1) =~ extlinux\ 3 ]]; then
        mkfs=mkfs.ext3
    else
        mkfs=mkfs.ext4
    fi
    $mkfs -O ^64bit -L "$label" $TGTDEV
    udevadm settle
    # mkfs.ext[34] truncate labels to 16 bytes.
    label=$(lsblk -ndo LABEL $TGTDEV)
}

checkGPT() {
    local dev=$1
    getdisk $dev
    local partinfo=$(run_parted --script -m $device 'print')
    if ! [[ ${partinfo} =~ :gpt: ]]; then
        printf '\n        ATTENTION:
        EFI booting requires a GPT partition table on the boot disk.\n
        This can be set up manually, or you can reformat your disk
        by running livecd-iso-to-disk with the --format --efi options.'
        exitclean
    fi

    while IFS=: read -r -a _info; do
        if [[ $partnum == ${_info[0]} ]]; then
            volname=${_info[5]}
            flags=${_info[6]}
            break
        fi
    done <<< "$partinfo"

    if [[ $volname != 'EFI System Partition' ]]; then
        printf "\n        ALERT:
        The partition name must be 'EFI System Partition'.\n
        This can be set with a partition editor, such as parted,
        or you can run livecd-iso-to-disk with the --reset-mbr option."
        exitclean
    fi
    if ! [[ $flags =~ boot ]]; then
        printf "\n        ATTENTION:
        The partition isn't marked bootable!\n
        You can mark the partition as bootable with the following commands:\n
        # parted %s
          (parted) toggle <N> boot
          (parted) quit\n\n" $device
        exitclean
    fi
}

checkFilesystem() {
    local dev=$1

    TGTFS=$(blkid -s TYPE -o value $dev || :)
    if [[ -n $format ]]; then
        if [[ -n $efi ]] || [[ -n $usemsdos ]] ||
             ! type extlinux >/dev/null 2>&1; then
            TGTFS=vfat
        else
            TGTFS=ext4
        fi
    fi
    if [[ $TGTFS != @(vfat|msdos|ext[234]|btrfs) ]]; then
        printf '\n        ALERT:
        The target filesystem must have a vfat, ext[234], or btrfs format.
        Exiting...\n'
        exitclean
    fi
    if [[ $TGTFS == @(vfat|msdos) ]]; then
        tgtmountopts='-o shortname=winnt,umask=0077'
        CONFIG_FILE=syslinux.cfg
    else
        CONFIG_FILE=extlinux.conf
    fi
}

checkSyslinuxVersion() {
    if ! type syslinux >/dev/null 2>&1; then
        printf '\n        ALERT:
        You need to have the SYSLINUX package installed to run this script.
        Exiting...\n\n'
        exit 1
    fi
}

checkMounted() {
    local dev=$1
    for d in $dev*; do
        local mountpoint=$(findmnt -nro TARGET $d)
        if [[ -n $mountpoint ]]; then
            printf "\n    NOTICE:  '%s' is mounted at '%s'.\n
            Please unmount for safety.        Exiting...\n\n" $d "$mountpoint"
            exitclean
        fi
    done
    if [[ $(swapon -s) =~ ${dev} ]]; then
        printf "\n    NOTICE:   Your chosen target device, '%s',\n
        is in use as a swap device.  Please disable swap if you want
        to use this device.        Exiting..." $dev
        exitclean
    fi
}

checkint() {
    case $2 in
        timeout )
            if ! [[ $1 == @(0|-0|-1|[1-9]*([0-9])) ]]; then
                shortusage
                echo -e "\nERROR: '$1' is not a valid integer for --$2.\n"
                exit 1
            fi
            ;;
        totaltimeout )
            if ! [[ $1 == @(0|[1-9]*([0-9])) ]]; then
                shortusage
                echo -e "\nERROR: '$1' is not a valid integer for --$2.\n"
                exit 1
            fi
            ;;
        * )
            if ! [[ $1 == [1-9]*([0-9]) ]]; then
                shortusage
                echo -e "\nERROR: '$1' is not a valid integer entry.\n"
                exit 1
            fi
            ;;
    esac
}

detectsrctype() {
    if [[ -e $SRCMNT/Packages ]]; then
        echo "/Packages found, will copy source packages to target."
        packages=1
    fi
    local cmdline=$(< /proc/cmdline)
    local len=${#cmdline}
    if [[ -z $livedir ]]; then
        livedir=${cmdline#* @(rd.live.dir|live_dir)=}
        if [[ ${#livedir} == $len ]]; then
            livedir=LiveOS
        else
            livedir=${livedir%% *}
        fi
    fi
    squashimg=${cmdline#* rd.live.squashimg=}
    if [[ ${#squashimg} == $len ]]; then
        squashimg=squashfs.img
    else
        squashimg=${squashimg%% *}
    fi
    liveram=${cmdline#* @(rd.live.ram|live_ram)}
    if [[ ${#liveram} == $len ]]; then
        liveram=''
    else
        liveram=1
    fi
    writable_fsimg=${cmdline#* @(rd.writable.fsimg|writable_fsimg)}
    if [[ ${#writable_fsimg} != $len ]]; then
        SRCIMG=/run/initramfs/fsimg/rootfs.img
        srctype=live
        return
    fi
    if [[ -n $liveram ]]; then
        for f in /run/initramfs/squashed.img \
                 /run/initramfs/rootfs.img ; do
            if [[ -e $f ]]; then
                SRCIMG=$f
                break
            fi
        done
        srctype=live
        return
    fi
    for f in "$SRCMNT/$livedir/$squashimg" \
            "$SRCMNT/$livedir/rootfs.img" \
            "$SRCMNT/$livedir/ext3fs.img"; do
        if [[ -e $f ]]; then
            SRCIMG="$f"
            srctype=live
            break
        fi
    done
    [[ -n $srctype ]] && return

    if [[ -e $SRCMNT/images/install.img ]] ||
        [[ -e $SRCMNT/isolinux/initrd.img ]]; then
        if [[ -n $packages ]]; then
            srctype=installer
        else
            srctype=netinst
        fi
        imgtype=install
        if ! [[ -e $SRCMNT/images/install.img ]]; then
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

if type rsync >/dev/null 2>&1; then
    copyFile='rsync --inplace --8-bit-output --progress'
elif type gvfs-copy >/dev/null 2>&1; then
    copyFile='gvfs-copy -p'
elif type strace >/dev/null 2>&1 && type awk >/dev/null 2>&1; then
    copyFile='cp_p'
else
    copyFile='cp'
fi

set -e
set -o pipefail
trap exitclean EXIT
shopt -s extglob

cryptedhome=1
keephome=1
homesizemb=0
swapsizemb=0
overlaysizemb=0
resetoverlay=''
overlay=''
srctype=
imgtype=
packages=
LIVEOS=LiveOS
HOMEFILE=home.img
updates=
ks=
label=''

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
            checkint $2 timeout
            timeout=$2
            shift
            ;;
        --totaltimeout)
            checkint $2 totaltimeout
            totaltimeout=$2
            shift
            ;;
        --nobootmsg)
            nobootmsg=1
            ;;
        --nomenu)
            nomenu=1
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
            skipcompress=''
            ;;
        --skipcompress)
            skipcompress=1
            ;;
        --no-overlay)
            overlay=none
            ;;
        --overlay-size-mb)
            checkint $2
            overlaysizemb=$2
            shift
            ;;
        --reset-overlay)
            resetoverlay=resetoverlay
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
            cryptedhome=''
            ;;
        --delete-home)
            keephome=''
            ;;
        --swap-size-mb)
            checkint $2
            swapsizemb=$2
            shift
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
            shortusage
            echo "invalid arg -- $1"
            exit 1
            ;;
        *)
            break
            ;;
    esac
    shift
done

if [[ $# -ne 2 ]]; then
    shortusage
    echo '
    ERROR:  At minimum, a source and a target must be specified.'
    exit 1
fi

SRC=$(readlink -f "$1") || :
TGTDEV=$(readlink -f "$2") || :

if [[ -z $SRC ]]; then
    shortusage
    echo "Missing source"
    exit 1
fi

if ! [[ -b $SRC || -f $SRC || -d $SRC ]]; then
    shortusage
    echo -e "\nERROR: '$SRC' is not a file, block device, or directory.\n"
    exit 1
fi

if [[ -z $TGTDEV ]]; then
    shortusage
    echo "Missing target device"
    exit 1
fi

if ! [[ -b $TGTDEV ]]; then
    shortusage
    echo "
    ERROR:  '$TGTDEV' is not a block device."
    exit 1
fi

# Do some basic sanity checks.
checkSyslinuxVersion
checkMounted $TGTDEV
checkFilesystem $TGTDEV

if [[ $LIVEOS =~ [[:space:]] ]]; then
    printf "\n    ALERT:
    The LiveOS directory name, '%s', contains spaces, newlines or tabs.\n
    Whitespace does not work with the SYSLINUX boot loader.
    The whitespace will be replaced by underscores.\n\n" "$LIVEOS"
    LIVEOS=${LIVEOS//[[:space:]]/_}
fi

if [[ $overlay == none ]] && ((overlaysizemb > 0)); then
    printf '\n        ERROR:
        You have specified --no-overlay AND --overlay-size-mb <size>.\n
        Only one of these options may be requested at a time.\n
        Please request only one of these options.  Exiting...\n'
    exitclean
fi

if ((overlaysizemb > 0)); then
    if [[ $TGTFS == @(vfat|msdos) ]] && ((overlaysizemb > 4095)); then
        printf '\n        ALERT:
        An overlay size greater than 4095 MiB
        is not allowed on VFAT formatted filesystems.\n'
        exitclean
    fi
    [[ -z $label ]] && label=$(lsblk -no LABEL $TGTDEV)
    # Remove newline, if parent device is passed, such as for a loop device.
    label=${label#$'\n'}
    # If more than one partition is present, use label from first.
    label=${label%$'\n'*}
    if [[ $label =~ [[:space:]] ]]; then
        printf '\n        ALERT:
        The LABEL (%s) on %s has spaces, newlines, or tabs in it.
        Whitespace does not work with the overlay.
        An attempt to rename the device will be made.\n\n' "$label" $TGTDEV
        label=${label//[[:space:]]/_}
    fi
fi

if ((homesizemb > 0)) && [[ $TGTFS = vfat ]]; then
    if ((homesizemb > 4095)); then
        echo "Can't have a home filesystem greater than 4095 MB on VFAT"
        exitclean
    fi
fi

if ((swapsizemb > 0)) && [[ $TGTFS == vfat ]]; then
    if ((swapsizemb > 4095)); then
        echo "Can't have a swap file greater than 4095 MB on VFAT"
        exitclean
    fi
fi

if [[ -z $noverify && $(file -br "$SRC") == ISO\ 9660\ * ]]; then
    # verify the image
    echo 'Verifying image...'
    if ! checkisomd5 --verbose "$SRC"; then
        printf '
        Are you SURE you want to continue?\n
        Press Enter to continue, or Ctrl C to abort.\n'
        read
    fi
fi

SRCMNT=$(mktemp -d /run/srctmp.XXXXXX)
srcmountopts='-o ro'
if [[ -f $SRC ]]; then
    srcmountopts+=,loop
elif [[ -d $SRC ]]; then
    livedir=$SRC
    SRC=$(findmnt -nro TARGET -T "$livedir")
    if [[ $livedir == $SRC ]]; then
        livedir=''
    else
        livedir=${livedir##*/}
    fi
    srcmountopts+=\ --bind
elif [[ $SRC -ef $(readlink -f /run/initramfs/livedev) ]] ||
     [[ $SRC -ef $(readlink -f /dev/live) ]]; then
    SRC=/run/initramfs/live
    srcmountopts+=\ --bind
elif ! [[ -b $SRC ]]; then
    printf "\n        ATTENTION:
    '$SRC' is not a file, block device, or directory.\n"
    exitclean
fi
mount $srcmountopts "$SRC" $SRCMNT || exitclean
trap exitclean SIGINT SIGTERM

# Figure out what needs to be done based on the source image.
detectsrctype

# Format the device
if [[ -n $format && -z $skipcopy ]]; then
    if [[ -n $efi ]]; then
        createGPTLayout $TGTDEV
    elif [[ -n $usemsdos ]] || ! type extlinux >/dev/null 2>&1; then
        createMSDOSLayout $TGTDEV
    else
        createEXTFSLayout $TGTDEV
    fi
fi

if [[ -n $efi ]]; then
    checkGPT $TGTDEV
else
  # Because we can't set boot flag for EFI Protective on msdos partition tables
    checkPartActive $TGTDEV
fi

[[ -n $resetmbr ]] && resetMBR $TGTDEV

checkMBR $TGTDEV

fs_label_msg() {
    if [[ $TGTFS == @(vfat|msdos) ]]; then
        printf '
        A label can be set with the fatlabel command.'
    elif [[ $TGTFS == ext[234] ]]; then
        printf '
        A label can be set with the e2label command.'
    elif [[ btrfs == $TGTFS ]]; then
        printf '
        A label can be set with the btrfs filesystem label command.'
    fi
    exitclean
}

labelTargetDevice() {
    local dev=$1

    TGTLABEL=$(lsblk -no LABEL $dev)
    # Remove newline, if parent device is passed, such as for a loop device.
    TGTLABEL=${TGTLABEL#$'\n'}
    # If more than one partition is present, use label from first.
    TGTLABEL=${TGTLABEL%$'\n'*}
    TGTLABEL=${TGTLABEL//[[:space:]]/_}
    [[ -z $TGTLABEL && -z $label ]] && label=LIVE
    if [[ -n $label && $TGTLABEL != "$label" ]]; then
        if [[ $TGTFS == @(vfat|msdos) ]]; then
            fatlabel $dev "$label"
        elif [[ $TGTFS == ext[234] ]]; then
            e2label $dev "$label"
        elif [[ $TGTFS == btrfs ]]; then
            btrfs filesystem label $dev "$label"
        else
            printf "
            ALERT:  Unknown filesystem type.
            Try setting its label to '$label' and re-running.\n"
        fi
        TGTLABEL="$label"
    fi
    label=$TGTLABEL
}

labelTargetDevice $TGTDEV

# Use UUID if available.
TGTUUID=$(blkid -s UUID -o value $TGTDEV)
if [[ -n $TGTUUID ]]; then
    TGTLABEL=UUID=$TGTUUID
elif [[ -n $TGTLABEL ]]; then
        TGTLABEL="LABEL=$TGTLABEL"
else
    printf '\n    ALERT:
    You need to have a filesystem label or
    UUID for your target device.\n'
    fs_label_msg
fi
OVERNAME="overlay-$label-$TGTUUID"

TGTMNT=$(mktemp -d /run/tgttmp.XXXXXX)
mount $tgtmountopts $TGTDEV $TGTMNT || exitclean

if [[ -z $skipcopy ]] && [[ -f $TGTMNT/$LIVEOS/$HOMEFILE ]] &&
    [[ -n $keephome ]] && ((homesizemb > 0)); then
    printf '\n        ERROR:
        The target has an existing home.img file and you requested that a new
        home.img be created.  To remove an existing home.img on the target,
        you must explicitly specify --delete-home as an installation option.\n
        Please adjust your home.img options.  Exiting...\n\n'
    exitclean
fi
if [[ -n $resetoverlay ]]; then
    existing=($(find $TGTMNT/$LIVEOS/ -name overlay-* -print || :))
    if [[ ! -s $existing ]]; then
        printf '\n        NOTICE:
        A persistent overlay was not found on the target device to reset.\n
        Press Enter to continue, or Ctrl C to abort.\n'
        read
    elif ((overlaysizemb > 0)) && [[ -z $skipcopy ]]; then
        printf '\n        ERROR:
        You requested a new persistent overlay AND to reset the current one.\n
        Please select only one of these options.  Exiting...\n\n'
        exitclean
    elif [[ $existing != $TGTMNT/$LIVEOS/$OVERNAME ]]; then
        mv $existing $TGTMNT/$LIVEOS/$OVERNAME
    fi
fi

if [[ -d $SRCMNT/EFI/BOOT ]]; then
    EFI_BOOT=/EFI/BOOT
elif [[ -d $SRCMNT/EFI/boot ]]; then
    EFI_BOOT=/EFI/boot
fi
if [[ -n $efi && -z $EFI_BOOT ]]; then
    printf '\n        ATTENTION:
    You requested EFI booting, but this source image lacks support
    for EFI booting.  Exiting...\n'
    exitclean
fi

if [[ $srctype == live ]] &&
   [[ -z $multi && -z $force && -e $TGTMNT/syslinux ]]; then
    IFS=: read -n 1 -p '
    ATTENTION:

        >> There may be other LiveOS images on this device. <<

    Do you want a Multi Live Image installation?

        If so, press Enter to continue.

        If not, press the [space bar], and other images
                will be ignored.

    To abort the installation, press Ctrl C.
    ' multi
    if [[ $multi != " " ]]; then
        multi=1
    else
        unset -v multi
    fi
fi
if [[ -z $skipcopy ]] && [[ $srctype == live ]]; then
    if [[ -d $TGTMNT/$LIVEOS ]] && [[ -z $force ]]; then
        printf "\nThe '%s' directory is already set up with a LiveOS image.\n
               " $LIVEOS
        if [[ -z $keephome && -e $TGTMNT/$LIVEOS/$HOMEFILE ]]; then
            printf '\n        WARNING:
            \r        The old persistent home.img will be deleted!!!\n
            \r        Press Enter to continue, or Ctrl C to abort.'
            read
        else
            printf '    Press Ctrl C if you wish to abort.
                Deleting the old OS in     seconds.\b\b\b\b\b\b\b\b\b\b'
            for (( i=14; i>=0; i=i-1 )); do
                printf '\b\b%02d' $i
                sleep 1
            done
            [[ -e $TGTMNT/$LIVEOS/$HOMEFILE && -n $keephome ]] &&
                mv $TGTMNT/$LIVEOS/$HOMEFILE $TGTMNT/$HOMEFILE
            [[ -e $TGTMNT/$LIVEOS/$OVERNAME && -n $resetoverlay ]] &&
                mv $TGTMNT/$LIVEOS/$OVERNAME $TGTMNT/$OVERNAME
        fi
        rm -rf -- $TGTMNT/$LIVEOS
    fi
fi

if [[ $(syslinux --version 2>&1) != syslinux\ * ]]; then
    SYSLINUXPATH=''
elif [[ -n $multi ]]; then
    SYSLINUXPATH=$LIVEOS/syslinux
else
    SYSLINUXPATH=syslinux
fi

thisScriptpath=$(readlink -f "$0")
checklivespace() {
# let's try to make sure there's enough room on the target device

# var=($(du -B 1M path)) uses the compound array assignment operator to extract
# the numeric result of du into the index zero position of var.  The index zero
# value is the default operative value for the array variable when no other
# indices are specified.
    if [[ -d $TGTMNT/$LIVEOS ]]; then
        tbd=($(du -B 1M $TGTMNT/$LIVEOS))
        if [[ -s $TGTMNT/$LIVEOS/$HOMEFILE ]] && [[ -n $keephome ]]; then
            homesize=($(du -B 1M $TGTMNT/$LIVEOS/$HOMEFILE))
            tbd=$((tbd - homesize))
        fi
    else
        tbd=0
    fi

    targets="$TGTMNT/$SYSLINUXPATH $TGTMNT$EFI_BOOT "
    [[ -n $xo ]] && targets+=$TGTMNT/boot/olpc.fth
    duTable=($(du -c -B 1M $targets 2> /dev/null || :))
    # du -c reports a grand total in the first column of the last row, i.e., at
    # ${array[*]: -2:1}, the penultimate index position.
    tbd=$((tbd + ${duTable[*]: -2:1}))

    if [[ -n $skipcompress ]] && [[ -s $SRCIMG ]]; then
        if mount -o loop "$SRCIMG" $SRCMNT; then
            if [[ -e $SRCMNT/LiveOS/rootfs.img ]]; then
                SRCIMG=$SRCMNT/LiveOS/rootfs.img
            elif [[ -e $SRCMNT/LiveOS/ext3fs.img ]]; then
                SRCIMG=$SRCMNT/LiveOS/ext3fs.img
            else
                printf "\n        ERROR:
                '%s' does not appear to contain a LiveOS image.  Exiting...\n
                " "$SRCIMG"
                exitclean
            fi
            livesize=($(du -B 1M --apparent-size "$SRCIMG"))
            umount -l $SRCMNT
        else
            echo "WARNING: --skipcompress or --xo was specified but the
            currently-running kernel can not mount the SquashFS from the source
            file to extract it. Instead, the compressed SquashFS will be copied
            to the target device."
            skipcompress=""
        fi
    else
        livesize=($(du -B 1M "$SRCIMG"))
    fi
    if ((livesize > 4095)) &&  [[ vfat == $TGTFS ]]; then
        echo "
        An image size greater than 4095 MB is not suitable for a 
        VFAT-formatted device.
        "
        if [[ -n $skipcompress ]]; then
            echo " The compressed SquashFS will instead be copied
            to the target device."
            skipcompress=''
            livesize=($(du -B 1M "$SRCMNT/$livedir/$squashimg"))
        else
            echo "Exiting..."
            exitclean
        fi
    fi
    sources="$SRCMNT/$livedir/osmin.img"\ "$SRCMNT/$livedir/syslinux"
    sources+=" $SRCMNT/isolinux $SRCMNT/syslinux $SRCMNT$EFI_BOOT"
    duTable=($(du -c -B 1M "$0" $sources 2> /dev/null || :))
    livesize=$((livesize + ${duTable[*]: -2:1} + 1))

    tba=$((overlaysizemb + homesizemb + livesize + swapsizemb))
    if ((tba > freespace + tbd)); then
        needed=$((tba - freespace - tbd))
        printf "\n  The live image + overlay, home, & swap space, if requested,
        \r  will NOT fit in the space available on the target device.\n
        \r  + Size of live image: %10s  MiB\n" $livesize
        ((overlaysizemb > 0)) && \
            printf "  + Overlay size: %16s\n" $overlaysizemb
        ((homesizemb > 0)) && \
            printf "  + Home directory size: %9s\n" $homesizemb
        ((swapsizemb > 0)) && \
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
}
freespace=($(df -B 1M $TGTDEV))
freespace=${freespace[*]: -3:1}

[[ -z $skipcopy && live == $srctype ]] && checklivespace

# Verify available space for DVD installer
if [[ $srctype == installer ]]; then
    if [[ $imgtype == install ]]; then
        imgpath=images/install.img
    else
        imgpath=isolinux/initrd.img
    fi
    duTable=($(du -s -B 1M $SRCMNT/$imgpath))
    installimgsize=${duTable[0]}

    tbd=0
    if [[ -e $TGTMNT/$imgpath ]]; then
        duTable=($(du -s -B 1M $TGTMNT/$imgpath))
        tbd=${duTable[0]}
    fi
    if [[ -e $TGTMNT/${SRC##*/} ]]; then
        duTable=($(du -s -B 1M "$TGTMNT/${SRC##*/}"))
        tbd=$((tbd + ${duTable[0]}))
    fi
    printf '\nSize of %s:  %s
    \rAvailable space:  %s' $imgpath $installimgsize $((freespace + tbd)) 
    if (( installimgsize > ((freespace + tbd)) )); then
        printf '\nERROR: Unable to fit DVD image + install.img on the available
        space of the target device.\n'
        exitclean
    fi
fi

# Live image copy
if [[ $srctype == live && -z $skipcopy ]]; then
    printf '\nCopying LiveOS image to target device...\n'
    [[ ! -d $TGTMNT/$LIVEOS ]] && mkdir $TGTMNT/$LIVEOS
    [[ -n $keephome && -f $TGTMNT/$HOMEFILE ]] &&
        mv $TGTMNT/$HOMEFILE $TGTMNT/$LIVEOS/$HOMEFILE
    [[ -n $resetoverlay && -e $TGTMNT/$OVERNAME ]] &&
        mv $TGTMNT/$OVERNAME $TGTMNT/$LIVEOS/$OVERNAME
    if [[ -n $skipcompress && -f $SRCMNT/$livedir/$squashimg ]]; then
        mount -o loop "$SRCMNT/$livedir/$squashimg" $SRCMNT || exitclean
        $copyFile "$SRCIMG" $TGTMNT/$LIVEOS/rootfs.img || {
            umount $SRCMNT ; exitclean ; }
        umount $SRCMNT
    elif [[ -f $SRCIMG ]]; then
        $copyFile "$SRCIMG" $TGTMNT/$LIVEOS/${SRCIMG##/*/} || exitclean
        [[ ${SRCIMG##/*/} == squashed.img ]] &&
            mv $TGTMNT/$LIVEOS/${SRCIMG##/*/} $TGTMNT/$LIVEOS/squashfs.img
    fi
    if [[ -f $SRCMNT/$livedir/osmin.img ]]; then
        $copyFile "$SRCMNT/$livedir/osmin.img" $TGTMNT/$LIVEOS/osmin.img ||
            exitclean
    fi
    printf '\nSyncing filesystem writes to disc.
    Please wait, this may take a while...\n'
    sync
fi

# Bootloader is always reconfigured, so keep this out of the -z skipcopy stuff.
[[ ! -d $TGTMNT/$SYSLINUXPATH ]] && mkdir -p $TGTMNT/$SYSLINUXPATH
if [[ -n $EFI_BOOT ]]; then
    if [[ -n $multi ]]; then
        if [[ -e $TGTMNT$EFI_BOOT/grub.cfg ]]; then
            BOOTCONFIG_EFI=$TGTMNT$EFI_BOOT/grub.cfg
        elif [[ -e $(nocase_path "$TGTMNT$EFI_BOOT/boot*.conf") ]]; then
            BOOTCONFIG_EFI=$(nocase_path "$TGTMNT$EFI_BOOT/boot*.conf")
        fi
        [[ -e $TGTMNT/EFI_previous ]] && rm $TGTMNT/EFI_previous
        mv $BOOTCONFIG_EFI $TGTMNT/EFI_previous
    fi
    [[ -d $TGTMNT/EFI ]] && rm -r -- $TGTMNT/EFI
    mkdir -p $TGTMNT$EFI_BOOT
fi

# Adjust syslinux sources for replication of installed images
# between filesystem types.
if [[ -d $SRCMNT/isolinux/ ]]; then
    cp $SRCMNT/isolinux/* $TGTMNT/$SYSLINUXPATH
elif [[ -d $SRCMNT/syslinux/ ]]; then
    [[ -d $SRCMNT/$livedir/syslinux ]] && subdir="$livedir"/
    cp "$SRCMNT/${subdir}syslinux/"* $TGTMNT/$SYSLINUXPATH
    if [[ -f $TGTMNT/$SYSLINUXPATH/extlinux.conf ]]; then
        mv $TGTMNT/$SYSLINUXPATH/extlinux.conf \
            $TGTMNT/$SYSLINUXPATH/isolinux.cfg
    elif [[ -f $TGTMNT/$SYSLINUXPATH/syslinux.cfg ]]; then
        mv $TGTMNT/$SYSLINUXPATH/syslinux.cfg \
            $TGTMNT/$SYSLINUXPATH/isolinux.cfg
    fi
fi
BOOTCONFIG=$TGTMNT/$SYSLINUXPATH/isolinux.cfg

# Always install EFI components, when available, so that they are available to
# propagate, if desired from the installed system.
if [[ -n $EFI_BOOT ]]; then
    echo "Setting up $EFI_BOOT"
    cp -r $SRCMNT$EFI_BOOT/* $TGTMNT$EFI_BOOT

    # The GRUB EFI config file can be one of:
    #   boot?*.conf
    #   BOOT?*.conf
    #   grub.cfg
    if [[ -e $TGTMNT$EFI_BOOT/grub.cfg ]]; then
        BOOTCONFIG_EFI=$TGTMNT$EFI_BOOT/grub.cfg
    elif [[ -e $(nocase_path "$TGTMNT$EFI_BOOT/boot*.conf") ]]; then
        BOOTCONFIG_EFI=$(nocase_path "$TGTMNT$EFI_BOOT/boot*.conf")
    elif [[ -n $efi ]]; then
        echo "Unable to find EFI config file."
        exitclean
    fi
    rm -f $TGTMNT$EFI_BOOT/grub.conf

    # On some images (RHEL) the BOOT*.efi file isn't in $EFI_BOOT, but is in
    # the eltorito image, so try to extract it if it is missing

    # test for presence of *.efi grub binary
    if [[ ! -f $(nocase_path "$TGTMNT$EFI_BOOT/boot*efi") ]]; then
        if ! type dumpet >/dev/null 2>&1 && [[ -n $efi ]]; then
            echo "No /usr/bin/dumpet tool found. EFI image will not boot."
            echo "Source media is missing grub binary in /EFI/BOOT/*EFI"
            exitclean
        else
            # dump the eltorito image with dumpet, output is $SRC.1
            dumpet -i "$SRC" -d
            EFIMNT=$(mktemp -d /run/srctmp.XXXXXX)
            mount -o loop "$SRC".1 $EFIMNT

            if [[ -f $(nocase_path "$EFIMNT$EFI_BOOT/boot*efi") ]]; then
                cp $(nocase_path "$EFIMNT$EFI_BOOT/boot*efi") $TGTMNT$EFI_BOOT
            elif [[ -n $efi ]]; then
                echo "No BOOT*.EFI found in eltorito image. EFI will not boot"
                umount $EFIMNT
                rm "$SRC".1
                exitclean
            fi
            umount $EFIMNT
            rm "$SRC".1
        fi
    fi
else
    # So sed doesn't complain about missing input variable...
    BOOTCONFIG_EFI=''
fi

# DVD installer copy
if [[ -z $skipcopy ]] && [[ $srctype == @(installer|netinst) ]]; then
    echo "Copying DVD image to target device."
    mkdir -p $TGTMNT/images/
    if [[ $imgtype == install ]]; then
        for img in install.img updates.img product.img; do
            if [[ -e $SRCMNT/images/$img ]]; then
                $copyFile $SRCMNT/images/$img $TGTMNT/images/$img || exitclean
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
if [[ -n $packages && -z $skipcopy ]]; then
    echo "Copying package data from $SRC to device."
    rsync --inplace -rLDP --exclude EFI/ --exclude images/ --exclude isolinux/ \
        --exclude TRANS.TBL --exclude LiveOS/ "$SRCMNT/" "$TGTMNT/"
    echo "Waiting for device to finish writing."
    sync
fi

if [[ $srctype == live ]]; then
    # Copy this installer script.
    cp -fT "$thisScriptpath" $TGTMNT/$LIVEOS/livecd-iso-to-disk
    chmod +x $TGTMNT/$LIVEOS/livecd-iso-to-disk &> /dev/null || :

    # When the source is an installed Live USB/SD image, restore the boot
    # config file to a base state before updating.
    if [[ -d $SRCMNT/syslinux/ ]]; then
        echo "Preparing boot config files."
        title=$(sed -n -r '/^\s*label\s+linux/{n
                           s/^\s*menu\s+label\s+\^Start\s+(.*)/\1/p}
                          ' $BOOTCONFIG)
        # Delete all labels before the 'linux' menu label.
        sed -i -r '/^\s*label .*/I,/^\s*label linux\>/I{
                   /^\s*label linux\>/I ! {N;N;N;N
                   /\<kernel\s+[^ ]*menu.c32\>/d};}' $BOOTCONFIG
        sed -i -r '/^\s*menu\s+end/I,$ {
                   /^\s*menu\s+end/I ! d}' $BOOTCONFIG
        # Keep only the menu entries up through the first submenu.
        sed -i -r "/\s+}$/ { N
                   /\n}$/ { n;Q}}" $BOOTCONFIG_EFI
        # Restore configuration entries to a base state.
        # And, if --multi, distinguish the new menuentry with $LIVEOS.
        [[ -f $TGTMNT/EFI_previous ]] && livedir=$LIVEOS\ 
        sed -i -r "s/^\s*timeout\s+.*/timeout 600/I
/^\s*totaltimeout\s+.*/Iz
s/(^\s*menu\s+title\s+Welcome\s+to)\s+.*/\1 $title/I
s/\<(kernel)\>\s+[^\n.]*(vmlinuz.?)/\1 \2/
s/\<(initrd=).*(initrd.?\.img)\>/\1\2/
s/\<(root=live:[^ ]*)\s+[^\n.]*\<(rd\.live\.image|liveimg)/\1 \2/
/^\s*label\s+linux\>/I,/^\s*label\s+check\>/Is/(rd\.live\.image|liveimg).*/\1 quiet/
/^\s*label\s+check\>/I,/^\s*label\s+vesa\>/Is/(rd\.live\.image|liveimg).*/\1 rd.live.check quiet/
/^\s*label\s+vesa\>/I,/^\s*label\s+memtest\>/Is/(rd\.live\.image|liveimg).*/\1 nomodeset quiet/
s/^\s*set\s+timeout=.*/set timeout=60/
/^\s*menuentry\s+'Start\s+/,/\s+}/{s/\s+'Start\s+/&$livedir/
s/(rd\.live\.image|liveimg).*/\1 quiet/}
/^\s*menuentry\s+'Test\s+/,/\s+}/{s/\s+&\s+start\s+/&$livedir/
s/(rd\.live\.image|liveimg).*/\1 rd.live.check quiet/}
/^\s*submenu\s+'Trouble/,/\s+}/s/(rd\.live\.image|liveimg).*/\1 nomodeset quiet/
s/(linuxefi\s+[^ ]+vmlinuz.?)\s+.*\s+(root=live:[^\s+]*)/\1 \2/
s_(linuxefi|initrdefi)\s+[^ ]+(initrd.?\.img|vmlinuz.?)_\1 /images/pxeboot/\2_
                  " $BOOTCONFIG $BOOTCONFIG_EFI
    fi
fi

# Setup the updates.img
if [[ -n $updates ]]; then
    $copyFile "$updates" "$TGTMNT/updates.img"
    kernelargs+=" inst.updates=hd:$TGTLABEL:/updates.img"
fi

# Setup the kickstart
if [[ -n $ks ]]; then
    $copyFile "$ks" "$TGTMNT/ks.cfg"
    kernelargs+=" inst.ks=hd:$TGTLABEL:/ks.cfg"
fi

echo "Updating boot config file."
# adjust label and fstype
sed -i -r "s/\<root=[^ ]*/root=live:$TGTLABEL/g
        s/\<rootfstype=[^ ]*\>/rootfstype=$TGTFS/" $BOOTCONFIG $BOOTCONFIG_EFI
if [[ -n $kernelargs ]]; then
    sed -i -r "s;=initrd.?\.img\>;& ${kernelargs} ;
               s;/vmlinuz.?\>;& ${kernelargs} ;" $BOOTCONFIG $BOOTCONFIG_EFI
fi
if [[ $LIVEOS != LiveOS ]]; then
    sed -i -r "s;rd\.live\.image|liveimg;& rd.live.dir=$LIVEOS;
              " $BOOTCONFIG $BOOTCONFIG_EFI
fi

if [[ -n $BOOTCONFIG_EFI ]]; then
    # EFI images are in $SYSLINUXPATH now
    sed -i "s;/isolinux/;/$SYSLINUXPATH/;g
            s;/images/pxeboot/;/$SYSLINUXPATH/;g
            s;findiso;;g" $BOOTCONFIG_EFI
fi

# DVD Installer for netinst
if [[ $srctype != live ]]; then
    # install images will have already had their stage2 setup by the LABEL
    # substitution and non-install will have everything in the initrd.
    if [[ $imgtype != install ]]; then
        # The initrd has everything, so no stage2.
        sed -i "s;\S*stage2=\S*;;g" $BOOTCONFIG $BOOTCONFIG_EFI
    fi
fi

# Adjust the boot timeouts
if [[ -n $timeout ]]; then
    [[ $timeout == "-0" ]] && { timeout=1; totaltimeout=1; }
    sed -i -r "s/^\s*timeout.*$/timeout $((timeout==-1 ? 0 : timeout))/I
              " $BOOTCONFIG
    if [[ $timeout != @(0|-1) ]]; then
        set +e
        ((timeout = (timeout%10) > 4 ? (timeout/10)+1 : (timeout/10) ))
        set -e
    fi
    sed -i -r "s/^\s*(set\s+timeout=).*$/\1$timeout/" $BOOTCONFIG_EFI
fi
if [[ -n $totaltimeout ]]; then
    sed -i -r "/\s*timeout\s+.*/ a\totaltimeout\ $totaltimeout" $BOOTCONFIG
fi

if [[ $overlay == none ]]; then
    sed -i -r 's/rd\.live\.image|liveimg/& rd.live.overlay=none/
              ' $BOOTCONFIG $BOOTCONFIG_EFI
fi

# Don't display boot.msg.
if [[ $nobootmsg == 1 ]]; then
    sed -i '/display boot.msg/d' $BOOTCONFIG
fi
# Skip the menu, and boot 'linux'.
if [[ $nomenu == 1 ]]; then
    sed -i 's/default .*/default linux/' $BOOTCONFIG
fi

if ((overlaysizemb > 0)); then
    echo "Initializing persistent overlay file"
    if [[ -z $skipcopy ]]; then
        if [[ $TGTFS == @(vfat|msdos) ]]; then
            # vfat can't handle sparse files
            dd if=/dev/zero of=$TGTMNT/$LIVEOS/$OVERNAME \
                count=$overlaysizemb bs=1M
        else
            dd if=/dev/null of=$TGTMNT/$LIVEOS/$OVERNAME \
                count=1 bs=1M seek=$overlaysizemb
        fi
    fi
    sed -i -r "s/rd\.live\.image|liveimg/& rd.live.overlay=${TGTLABEL}/
              " $BOOTCONFIG $BOOTCONFIG_EFI
fi

if [[ -n $resetoverlay ]]; then
    printf 'Resetting the overlay.\n'
    dd if=/dev/zero of=$TGTMNT/$LIVEOS/$OVERNAME bs=64k count=1 conv=notrunc
    sed -i -r "s/rd\.live\.image|liveimg/& rd.live.overlay=${TGTLABEL}$ovl/
              " $BOOTCONFIG $BOOTCONFIG_EFI
fi

if ((swapsizemb > 0)); then
    echo "Initializing swap file."
    if [[ -z $skipcopy ]]; then
        dd if=/dev/zero of=$TGTMNT/$LIVEOS/swap.img count=$swapsizemb bs=1M
    fi
    mkswap -f $TGTMNT/$LIVEOS/swap.img
fi

if ((homesizemb > 0)) && [[ -z $skipcopy ]]; then
    echo "Initializing persistent /home"
    homesource=/dev/zero
    [[ -n $cryptedhome ]] && homesource=/dev/urandom
    if [[ $TGTFS = vfat ]]; then
        # vfat can't handle sparse files.
        dd if=${homesource} of=$TGTMNT/$LIVEOS/$HOMEFILE \
           count=$homesizemb bs=1M
    else
        dd if=/dev/null of=$TGTMNT/$LIVEOS/$HOMEFILE \
           count=1 bs=1M seek=$homesizemb
    fi
    if [[ -n $cryptedhome ]]; then
        loop=$(losetup -f --show $TGTMNT/$LIVEOS/$HOMEFILE)

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

if [[ live = $srctype ]]; then
    sed -i -r 's/\s+ro\s+|\s+ro$/ /g
               s/rd\.live\.image|liveimg/& rw/' $BOOTCONFIG $BOOTCONFIG_EFI
fi

# create the forth files for booting on the XO if requested
# we'd do this unconditionally, but you have to have a kernel that will
# boot on the XO anyway.
if [[ -n $xo ]]; then
    echo 'Setting up /boot/olpc.fth file.'
    while read -r args; do
        if [[ $args =~ ^append ]]; then
            args=${args:6}
            args=${args/ initrd=+([^ ])/}
            break
        fi
    done < $TGTMNT/$SYSLINUXPATH/isolinux.cfg
    if [[ -z $xonohome && ! -f $TGTMNT/$LIVEOS/$HOMEFILE ]]; then
        args=$args\ persistenthome=mtd0
    fi
    args=$args\ reset_overlay
    xosyspath=${SYSLINUXPATH//\//\\}
    if [[ ! -d $TGTMNT/boot ]]; then
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

if [[ -n $multi && ! -d $TGTMNT/syslinux ]]; then
    multi=move
    # If this is the first image installed, move config directory to the root.
    move_syslinux_dir() {
        mv $TGTMNT/$SYSLINUXPATH $TGTMNT/syslinux
        SYSLINUXPATH=syslinux
    }
    [[ -e $TGTMNT/EFI_previous ]] && rm $TGTMNT/EFI_previous
fi

# This is a bit of a kludge, but syslinux doesn't guarantee the API
# for its com32 modules, :/, so we use the version on the installation host,
# selecting the UI present on the source. (This means that for multi boot
# installations, the most recent host and source may alter the version and UI.)
# See https://bugzilla.redhat.com/show_bug.cgi?id=492370
for f in vesamenu.c32 menu.c32; do
    if [[ -f $TGTMNT/$SYSLINUXPATH/$f ]]; then
        UI=$f
        for d in /usr/share/syslinux /usr/lib/syslinux; do
            if [[ -f $d/$f ]]; then
                cp $d/$f $TGTMNT/$SYSLINUXPATH/$f
                break 2
            fi
        done
    fi
done
sed -i -r "s/\s+[^ ]*menu\.c32\>/ $UI/g" $TGTMNT/syslinux/$CONFIG_FILE

if [[ -z $multi ]] || [[ $multi == move ]]; then
    echo "Installing boot loader..."
    if [[ -n $efi ]]; then
        # replace the ia32 hack
        if [[ -f $TGTMNT$EFI_BOOT/BOOT.conf ]]; then
            cp -f $TGTMNT$EFI_BOOT/BOOTia32.conf $TGTMNT$EFI_BOOT/BOOT.conf
        fi
    fi

    # syslinux >= 6.02 also requires ldlinux.c32, libcom32.c32, libutil.c32
    # since the version of syslinux being used is the one on the host they may
    # or may not be available.
    for f in ldlinux.c32 libcom32.c32 libutil.c32; do
        if [[ -f /usr/share/syslinux/$f ]]; then
            cp /usr/share/syslinux/$f $TGTMNT/$SYSLINUXPATH/$f
        else
            printf "\n        ATTENTION:
            Failed to find /usr/share/syslinux/$f.
            The installed device may not boot.
                    Press Enter to continue, or Ctrl C to abort.\n"
            read
        fi
    done

    if [[ $TGTFS == @(vfat|msdos) ]]; then
        # syslinux expects the config to be named syslinux.cfg
        # and has to run with the file system unmounted.
        mv $TGTMNT/$SYSLINUXPATH/isolinux.cfg \
            $TGTMNT/$SYSLINUXPATH/syslinux.cfg
        # deal with mtools complaining about ldlinux.sys
        if [[ -f $TGTMNT/$SYSLINUXPATH/ldlinux.sys ]]; then
            rm -f $TGTMNT/$SYSLINUXPATH/ldlinux.sys
        fi
        [[ $multi == move ]] && move_syslinux_dir
        cleanup
        if [[ -n $SYSLINUXPATH ]]; then
            syslinux -d $SYSLINUXPATH $TGTDEV
        else
            syslinux $TGTDEV
        fi
    elif [[ $TGTFS == @(ext[234]|btrfs) ]]; then
        # extlinux expects the config to be named extlinux.conf
        # and has to be run with the file system mounted.
        mv $TGTMNT/$SYSLINUXPATH/isolinux.cfg \
            $TGTMNT/$SYSLINUXPATH/extlinux.conf
        [[ $multi == move ]] && move_syslinux_dir
        extlinux -i $TGTMNT/$SYSLINUXPATH
        # Starting with syslinux 4 ldlinux.sys is used on all file systems.
        if [[ -f $TGTMNT/$SYSLINUXPATH/extlinux.sys ]]; then
            chattr -i $TGTMNT/$SYSLINUXPATH/extlinux.sys
        elif [[ -f $TGTMNT/$SYSLINUXPATH/ldlinux.sys ]]; then
            chattr -i $TGTMNT/$SYSLINUXPATH/ldlinux.sys
        fi
        cleanup
    fi
fi
if [[ $multi == 1 ]]; then
    # We need to do some more config file tweaks for multi-image mode.
    sed -i -r "s;\s+[^ ]*menu\.c32\>; $UI;g
               s;kernel\s+vm;kernel /$LIVEOS/syslinux/vm;
               s;initrd=i;initrd=/$LIVEOS/syslinux/i;
              " $TGTMNT/$SYSLINUXPATH/isolinux.cfg
    mv $TGTMNT/$SYSLINUXPATH/isolinux.cfg $TGTMNT/$SYSLINUXPATH/$CONFIG_FILE
    sed -i -r "1,20 s/^\s*(menu\s+title)\s+.*/\1 Multi Live Image Boot Menu/I
               /^\s*label\s+$LIVEOS/I { N;N;N;N; d }
               0,/^\s*label\s+.*/I {
               /^\s*label\s+.*/I {
               i\
               label $LIVEOS\\
\  menu label ^Go to $LIVEOS menu\\
\  kernel $UI\\
\  APPEND /$LIVEOS/syslinux/$CONFIG_FILE\\

               };}" $TGTMNT/syslinux/$CONFIG_FILE

    cat << EOF >> $TGTMNT/$SYSLINUXPATH/$CONFIG_FILE
menu separator
LABEL multimain
  MENU LABEL Return to Multi Live Image Boot Menu
  KERNEL $UI
  APPEND ~
EOF

    if [[ -f $TGTMNT/EFI_previous ]]; then
        sed -i -r "1 i\
...
                   /^\s*menuentry\s+/ { N;N;N
                   /\s+rd.live.dir=$LIVEOS\s+/ d }
                   /\s*submenu\s+/ { N;N;N;N;N
                   /\s+rd.live.dir=$LIVEOS\s+/ d }
                  " $TGTMNT/EFI_previous
        cat $TGTMNT/EFI_previous >> $BOOTCONFIG_EFI
        sed -i -r '/^...$/,/^\s*menuentry\s+/ {
                   /^\s*menuentry\s+/ ! d}' $BOOTCONFIG_EFI
        rm $TGTMNT/EFI_previous
    fi
    cleanup
fi

[[ -n $multi ]] && multi=Multi\ 
echo "Target device is now set up with a ${multi}Live image!"

