#!/bin/bash
# Transfer a Live image so that it's bootable off of a USB/SD device.
# Copyright 2007-2012, 2017, Red Hat, Inc.
# Copyright 2008-2010, 2017-2018, Fedora Project
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
                       [--skipcompress] [--no-overlay] [--overlayfs [temp]]
                       [--overlay-size-mb <size>] [--copy-overlay]
                       [--reset-overlay] [--home-size-mb <size>] [--copy-home]
                       [--delete-home] [--crypted-home] [--unencrypted-home]
                       [--swap-size-mb <size>] [--updates <updates.img>]
                       [--ks <kickstart>] [--label <label>]
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
                 or the mount point for another LiveOS filesystem.  Entering
                 'live' for the <source> will source the currently booted
                 LiveOS device.

             <target device>
                 This should be, or a link to, the device partition path for
                 the attached, target device, such as /dev/sdc1.  (Issue the
                 df -Th command to get a listing of mounted partitions, so you
                 can confirm the filesystem types, available space, and device
                 names.)  Be careful to specify the correct device, or you may
                 overwrite important data on another disk!  For a multi boot
                 installation to the currently booted device, enter 'live' as
                 the target.

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

    Multi image installations may be invoked interactively if the target device
    already contains a LiveOS image.

    LiveOS images employ embedded filesystems through the Device-mapper
    component of the Linux kernel.  The filesystems are embedded within files
    in the /LiveOS/ directory of the storage device.  The /LiveOS/squashfs.img
    file is the default, compressed filesystem containing one directory and the
    file /LiveOS/rootfs.img that contains the root filesystem for the
    distribution.  These are read-only filesystems that are usually fixed in
    size to within a few GiB of the size of the full root filesystem at build
    time.  At boot time, a Device-mapper snapshot with a sparse 32 GiB, in-
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
        action of the --format, --overlay-size-mb, --copy-overlay,
        --home-size-mb, --copy-home, & --swap-size-mb options, if present on
        the command line. (The --skipcopy option is useful while testing the
        script, in order to avoid repeated and lengthy copy commands, or with
        --reset-mbr, to repair the boot configuration files on a previously
        installed LiveOS device.)

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
        Signals the boot configuration to accommodate multiple images on the
        target device.  Image and boot files will be installed under the
        --livedir <directory>.  SYSLINUX boot components from the installation
        host will always update those in the boot path of the target device.

    --livedir <dir>
        Designates the directory for installing the LiveOS image.  The default
        is /LiveOS.

    --compress   (default state for the original root filesystem)
        The default, compressed SquashFS filesystem image is copied on
        installation.  (This option has no effect if the source filesystem is
        already expanded.)

    --skipcompress   (default option when  --xo is specified)
        Expands the source SquashFS.img on installation into the read-only
        /LiveOS/rootfs.img root filesystem image file.  This avoids the system
        overhead of decompression during use at the expense of storage space
        and bus I/O.

    --no-overlay   (effective only with skipcompress or an uncompressed image)
        Installs a kernel option, rd.live.overlay=none, that signals the live
        boot process to create a writable, linear Device-mapper target for an
        uncompressed /LiveOS/rootfs.img filesystem image file.  Read-write by
        default (unless a kernel argument of rd.live.overlay.readonly is given)
        this configuration avoids the complications of using an overlay of
        fixed size for persistence when storage format and space allows.

    --overlayfs [temp]   (add --overlay-size-mb for persistence on vfat devices)
        Specifies the creation of an OverlayFS type overlay.  If the option is
        followed by 'temp', a temporary overlay will be used.  On vfat or msdos
        formatted devices, --overlay-size-mb <size> must also be provided for a
        persistent overlay.  OverlayFS overlays are directories of the files
        that have changed on the read-only root filesystem.  With non-vfat-
        formatted devices, the OverlayFS can extend the available root
        filesystem space up to the capacity of the Live USB device.

        The --overlayfs option requires an initial boot image based on dracut
        version 045 or greater to use the OverlayFS feature.  Lacking this, the
        device boots with a temporary Device-mapper overlay.

    --overlay-size-mb <size>
        Specifies creation of a filesystem overlay of <size> mebibytes (integer
        values only).  The overlay makes persistent storage available to the
        live operating system, if the operating system supports it.  The
        overlay holds a snapshot of changes to the root filesystem.
        *Note well* that deletion of any original files in the read-only root
        filesystem does not recover any storage space on your LiveOS device.
        Storage in the persistent /LiveOS/overlay-<device_id> file is allocated
        as needed.  If the overlay storage space is filled, the overlay will
        enter an 'Overflow' state where the root filesystem will continue to
        operate in a read-only mode.  There will not be an explicit warning or
        signal when this happens, but applications may begin to report errors
        due to the restriction.  If significant changes or updates to the root
        filesystem are to be made, carefully watch the fraction of space
        allocated in the overlay by issuing the 'dmsetup status' command at a
        command line of the running LiveOS image.  Some consumption of root
        filesystem and overlay space can be avoided by specifying a persistent
        home filesystem for user files, see --home-size-mb below.  The target
        storage device must have enough free space for the image and the
        overlay.  A maximum <size> of 4095 MiB is permitted for vfat-formatted
        devices.  If there is not enough room on your device, you will be given
        information to help in adjusting your settings.

    --copy-overlay
        This option allows one to copy the persistent overlay from one live
        image to the new image.  Changes already made in the source image will
        be propagated to the new installation.
            WARNING: User sensitive information such as password cookies and
            application or user data will be copied to the new image!  Scrub
            this information before using this option.

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

    --copy-home
        This option allows one to copy a persistent home.img filesystem from
        the source LiveOS image to the target image.  Changes already made in
        the source home directory will be propagated to the new image.
            WARNING: User-sensitive information, such as password cookies and
            user and application data, will be copied to the new image! Scrub
            this information before using this option.

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
        iso without needing to make a new iso. <updates.img> should be a path
        accessible to this script, which will be copied to the target device.

    --ks <kickstart>
        Setup inst.ks to point to an kickstart file on the device. Use this for
        automating package installs on boot. <kickstart> should be a path
        accessible to this script, which will be copied to the target device.

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

    Copyright 2008-2010, 2017-2018, Fedora Project and various contributors.
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
    if [[ -d $SRCMNT ]]; then
        umount $SRCMNT && rmdir $SRCMNT
    fi
    if [[ -d $TGTMNT ]]; then
        umount $TGTMNT && rmdir $TGTMNT
    fi
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
# which, when checked with -f or -e doesn't actually exist, except on vfat or
# msdos filesystems where the default kernel mount option is check=n (see
# https://www.kernel.org/doc/Documentation/filesystems/vfat.txt) and Bash
# matches in a case-insensitive manner implicitly--even if check=s (strict) is
# set explicitly (GNU bash, version 4.4.12(1)-release (x86_64-redhat-linux-gnu)
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
        # Make the partition bootable from BIOS
        run_parted --script $device set $partnum legacy_boot on
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
    sleep 5
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
    echo 'Waiting for devices to settle...'
    udevadm settle
    sleep 5
    TGTDEV=$(get_partition1 ${device})
    umount $TGTDEV &> /dev/null || :
    mkfs.fat -n "$label" $TGTDEV
    udevadm settle
    sleep 5
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
    sleep 5
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
    sleep 5
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

checkForSyslinux() {
    if ! type syslinux >/dev/null 2>&1; then
        printf '\n        ALERT:
        You need to have the SYSLINUX package installed to run this script.
        Exiting...\n\n'
        exit 1
    fi
}

checkMounted() {
    local tgtdev=$1
    # Allow --multi installations to live booted devices.
    if [[ -d $SRC ]]; then
        local d="$SRC"
        # Find SRC mount point.
        SRC=$(findmnt -no TARGET -T "$d")
        if ! [[ $d -ef $SRC ]]; then
            srcdir=${d#$SRC/}
        fi
    fi
    srcdev=$(findmnt -no SOURCE -T "$SRC") || :
    for live_mp in /run/initramfs/live /mnt/live ; do
        if mountpoint -q $live_mp; then
            local livedev=$(findmnt -no SOURCE $live_mp)
            livedir=$(losetup -nO BACK-FILE /dev/loop0)
            livedir=${livedir%/*}
            livedir=${livedir/#$live_mp\/}
            break
        fi
    done
    [[ $SRC == live || $SRC -ef $livedev ]] && SRC=$live_mp
    [[ $tgtdev == live || $tgtdev -ef $livedev ]] && TGTDEV=$livedev

    if [[ $SRC -ef $live_mp && -z $livedev ]] ||
        [[ $tgtdev == live && -z $livedev ]]; then
        printf '
        This host does not appear to be a LiveOS booted device.
        Exiting...'
        exitclean
    elif [[ $TGTDEV -ef $livedev ]]; then
        if [[ -n $format ]]; then
            printf '\n    NOTICE:
            You have requested --format of the currently booted LiveOS device.
            This option will be ignored.\n\n'
            unset -v format
        fi
        tgtdev=$livedev
    elif [[ $TGTDEV -ef $srcdev && -n $format ]]; then
        printf '\n    NOTICE:
        You have requested --format of the LiveOS source device.
        This option will be ignored.\n\n'
        unset -v format
    fi
    if [[ $SRC -ef $live_mp ]]; then
        srcdir=$livedir
        srcdev=$livedev
    fi
    if [[ $livedev -ef $tgtdev && $livedir == "$LIVEOS" ]]; then
        printf "\n    NOTICE:   The target installation directory, '%s',\n
        is your currently booted source directory.\n
        Please select a different target --livedir for this device.\n
                Exiting..." $LIVEOS
        exitclean
    fi
    if ! [[ $tgtdev -ef $livedev ]] && ! [[ $tgtdev -ef $srcdev ]]; then
        for d in $tgtdev*; do
            local mountpoint=$(findmnt -nro TARGET $d)
            if [[ -n $mountpoint ]]; then
                printf "\n    NOTICE:  '%s' is mounted at '%s'.\n
                Please unmount for safety.
                Exiting...\n\n" $d "$mountpoint"
                exitclean
            fi
        done
        if [[ $(swapon -s) =~ ${tgtdev} ]]; then
            printf "\n    NOTICE:   Your chosen target device, '%s',\n
            is in use as a swap device.  Please disable swap if you want
            to use this device.        Exiting..." $tgtdev
            exitclean
        fi
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
        packages=packages
    fi
    if [[ $SRC == @(/run/initramfs/live|/mnt/live) ]]; then
        local cmdline=$(< /proc/cmdline)
        local len=${#cmdline}
        local ret=${cmdline#* rd.live.squashimg=}
        if [[ ${#ret} != $len ]]; then
            squashimg=${result%% *}
        fi
        ret=${cmdline#* @(rd.live.ram|live_ram)}
        if [[ ${#ret} != $len ]]; then
            liveram=liveram
        fi
        ret=${cmdline#* @(rd.writable.fsimg|writable_fsimg)}
        if [[ ${#ret} != $len ]]; then
            SRCIMG=/run/initramfs/fsimg/rootfs.img
            srctype=live
            return
        fi
        if [[ -n $liveram ]]; then
            for f in /run/initramfs/squashed.img \
                     /run/initramfs/rootfs.img ; do
                if [[ -s $f ]]; then
                    SRCIMG=$f
                    break
                fi
            done
            srctype=live
            return
        fi
    fi
    for f in "$SRCMNT/$srcdir/$squashimg" \
            "$SRCMNT/$srcdir/rootfs.img" \
            "$SRCMNT/$srcdir/ext3fs.img"; do
        if [[ -s $f ]]; then
            SRCIMG="$f"
            srctype=live
            break
        fi
    done
    # netinstall iso has no SRCIMG.
    if [[ -n "$SRCIMG" ]]; then
        IMGMNT=$(mktemp -d /run/imgtmp.XXXXXX)
        mount -r "$SRCIMG" $IMGMNT || exitclean
        [[ -d $IMGMNT/proc ]] && flat_squashfs=flat_squashfs
        umount $IMGMNT
        rmdir $IMGMNT
    fi
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

get_label() {
    local label=$(lsblk -no LABEL $1 || :)
    # Remove newline, if parent device is passed, such as for a loop device.
    label=${label#$'\n'}
    # If more than one partition is present, use label from first.
    label=${label%$'\n'*}
    echo -n "$label"
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
    copyFile='gio copy -p'
elif type strace >/dev/null 2>&1 && type awk >/dev/null 2>&1; then
    copyFile='cp_p'
else
    copyFile='cp'
fi

set -e
set -o pipefail
trap exitclean EXIT
shopt -s extglob

cryptedhome=cryptedhome
keephome=keephome
homesizemb=''
copyhome=''
copyhomesize=''
swapsizemb=''
overlay=''
overlayfs=''
overlaysizemb=''
copyoverlay=''
copyoverlaysize=''
resetoverlay=''
srctype=''
srcdir=LiveOS
squashimg=squashfs.img
imgtype=''
packages=''
LIVEOS=LiveOS
HOMEFILE=home.img
updates=''
ks=''
label=''

while true ; do
    case $1 in
        --help | -h | -?)
            usage
            ;;
        --noverify)
            noverify=noverify
            ;;
        --format)
            format=format
            ;;
        --msdos)
            usemsdos=usemsdos
            ;;
        --reset-mbr|--resetmbr)
            resetmbr=resetmbr
            ;;
        --efi|--mactel)
            efi=efi
            ;;
        --skipcopy)
            skipcopy=skipcopy
            ;;
        --force)
            force=force
            ;;
        --xo)
            xo=xo
            skipcompress=skipcompress
            ;;
        --xo-no-home)
            xonohome=xonohome
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
            nobootmsg=nobootmsg
            ;;
        --nomenu)
            nomenu=nomenu
            ;;
        --extra-kernel-args)
            kernelargs=$2
            shift
            ;;
        --multi)
            multi=multi
            ;;
        --livedir)
            LIVEOS=$2
            shift
            ;;
        --compress)
            skipcompress=''
            ;;
        --skipcompress)
            skipcompress=skipcompress
            ;;
        --no-overlay)
            overlay=none
            ;;
        --overlayfs)
            overlayfs=overlayfs
            if [[ $2 == temp ]]; then
                overlayfs=temp
                shift
            fi
            ;;
        --overlay-size-mb)
            checkint $2
            overlaysizemb=$2
            shift
            ;;
        --copy-overlay)
            copyoverlay=copyoverlay
            ;;
        --reset-overlay)
            resetoverlay=resetoverlay
            ;;
        --home-size-mb)
            checkint $2
            homesizemb=$2
            shift
            ;;
        --copy-home)
            copyhome=copyhome
            cryptedhome=''
            ;;
        --crypted-home)
            cryptedhome=cryptedhome
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

if [[ $1 == live ]]; then
    SRC=live
else
    SRC=$(readlink -f "$1") || :
fi
if [[ $2 == live ]]; then
    TGTDEV=live
else
    TGTDEV=$(readlink -f "$2") || :
fi

if [[ -z $SRC ]]; then
    shortusage
    echo "Missing source"
    exit 1
fi

if ! [[ -f $SRC || -b $SRC || -d $SRC || live == $SRC ]]; then
    shortusage
    echo -e "\nERROR: '$SRC' is not a file, block device, or directory.\n"
    exit 1
fi

if [[ -z $TGTDEV ]]; then
    shortusage
    echo "Missing target device"
    exit 1
fi

if ! [[ -b $TGTDEV || live == $TGTDEV ]]; then
    shortusage
    echo "
    ERROR:  '$TGTDEV' is not a block device."
    exit 1
fi

# Do some basic sanity checks.
checkForSyslinux
checkMounted $TGTDEV
checkFilesystem $TGTDEV

[[ $overlayfs == overlayfs ]] && overlayfs=$TGTFS

if [[ $LIVEOS =~ [[:space:]]|/ ]]; then
    printf "\n    ALERT:
    The LiveOS directory name, '%s', contains spaces, newlines, tabs, or '/'.\n
    Whitespace and '/' do not work with the SYSLINUX boot loader.
    Replacing the whitespace by underscores, any '/' by '-':  " "$LIVEOS"
    LIVEOS=${LIVEOS//[[:space:]]/_}
    LIVEOS=${LIVEOS////-}
    printf "'$LIVEOS'\n\n"
fi

if [[ $overlayfs == @(vfat|msdos) ]] && [[ -z $overlaysizemb ]]; then
    printf '\n        ALERT:
        If the target filesystem is formatted as vfat or msdos, you must
        specify an --overlay-size-mb <size> value for an embedded overlayfs.\n
        Exiting...\n'
    exitclean
fi

if [[ $overlayfs == temp && -n $overlaysizemb ]]; then
    printf '\n        ERROR:
        You have specified --overlayfs temp AND --overlay-size-mb <size>.\n
        Only one of these options may be requested at a time.\n
        Please request only one of these options.  Exiting...\n'
    exitclean
fi

if [[ $overlay == none && -n $overlaysizemb ]]; then
    printf '\n        ERROR:
        You have specified --no-overlay AND --overlay-size-mb <size>.\n
        Only one of these options may be requested at a time.\n
        Please request only one of these options.  Exiting...\n'
    exitclean
fi

[[ -n $overlaysizemb || -n $format ]] &&
    [[ -z $label ]] && label=$(get_label $TGTDEV)

if [[ -n $overlaysizemb ]]; then
    if [[ $TGTFS == @(vfat|msdos) ]] && ((overlaysizemb > 4095)); then
        printf '\n        ALERT:
        An overlay size greater than 4095 MiB
        is not allowed on VFAT formatted filesystems.\n'
        exitclean
    fi
    if [[ $label =~ [[:space:]] ]]; then
        printf '\n        ALERT:
        The LABEL (%s) on %s has spaces, newlines, or tabs in it.
        Whitespace does not work with the overlay.
        An attempt to rename the device will be made.\n\n' "$label" $TGTDEV
        label=${label//[[:space:]]/_}
    fi
fi

if [[ -n $homesizemb ]] && [[ $TGTFS = vfat ]]; then
    if ((homesizemb > 4095)); then
        echo "Can't have a home filesystem greater than 4095 MB on VFAT"
        exitclean
    fi
fi

if [[ -n $swapsizemb ]] && [[ $TGTFS == vfat ]]; then
    if ((swapsizemb > 4095)); then
        echo "Can't have a swap file greater than 4095 MB on VFAT"
        exitclean
    fi
fi

if [[ -z $noverify ]] && checkisomd5 --md5sumonly "$SRC" &>/dev/null; then
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

if [[ -n $flat_squashfs ]] && [[ -z $overlayfs ]]; then
    if [[ $TGTFS == @(vfat|msdos) ]] && [[ -z $overlaysizemb ]]; then
        printf  "\n        ALERT:
        The source has a flat SquashFS structure that requires an OverlayFS
        overlay specified by the --overlayfs option.\n
        Because the target device filesystem is '"$TGTFS"', you must
        specify an --overlay-size-mb <size> value for an embedded overlayfs.\n
        Exiting...\n\n"
        exitclean
    elif [[ -n $overlaysizemb ]]; then
        overlayfs=$TGTFS
    else
        overlayfs=temp
    fi
fi

if [[ $srctype != live ]]; then
    if [[ -n $homesizemb ]]; then
        printf '\n        ALERT:
        The source is not for a live installation. A home.img filesystem is not
        useful for netinst or installer installations.\n
        Please adjust your home.img options.  Exiting...\n\n'
        exitclean
    elif [[ -n $overlaysizemb ]]; then
        printf '\n        ALERT:
        The source is not for a live installation. A overlay file is not
        useful for netinst or installer installations.\n
        Please adjust your script options.  Exiting...\n\n'
        exitclean
    fi
fi

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

    TGTLABEL=$(get_label $dev)
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
OVLNAME="overlay-$label-$TGTUUID"

TGTMNT=$(mktemp -d /run/tgttmp.XXXXXX)
mount $tgtmountopts $TGTDEV $TGTMNT || exitclean

if [[ -n $copyoverlay ]]; then
    SRCOVL=($(find $SRCMNT/$srcdir/ -name overlay-* -print || :))
    if [[ ! -s $SRCOVL ]]; then
        printf '\n   NOTICE:
        There appears to be no persistent overlay on this image.
        Would you LIKE to continue with NO persistent overlay?\n\n
        Press Enter to continue, or Ctrl-c to abort.\n\n'
        read
        copyoverlay=''
    fi
fi
if [[ -n $copyoverlay && -n $overlaysizemb ]]; then
    printf '\n        ERROR:
        You requested a new overlay AND to copy one from the source.\n
        Please request only one of these options.  Exiting...\n'
    exitclean
fi

[[ -d $SRCMNT/EFI ]] && d=$(ls -d $SRCMNT/EFI/*/)
# This test is case sensitive in Bash on vfat filesystems.
if [[ $d =~ EFI/BOOT/ ]]; then
    EFI_BOOT=/EFI/BOOT
elif [[ $d =~ EFI/boot/ ]]; then
    EFI_BOOT=/EFI/boot
fi
if [[ -n $efi && -z $EFI_BOOT ]]; then
    printf '\n        ATTENTION:
    You requested EFI booting, but this source image lacks support
    for EFI booting.  Exiting...\n'
    exitclean
fi
[[ -d $TGTMNT/EFI ]] && d=$(ls -d $TGTMNT/EFI/*/)
if [[ $d =~ EFI/boot/ ]]; then
    T_EFI_BOOT=/EFI/boot
else
    T_EFI_BOOT=/EFI/BOOT
fi
BOOTCONFIG_EFI=($(nocase_path "$TGTMNT$T_EFI_BOOT/boot*.conf"))
#^ Use compound array assignment in case there are multiple files.

if [[ -n $multi ]]; then
    if ! [[ -e $TGTMNT/syslinux ]]; then
        unset -v multi
    elif [[ $LIVEOS == LiveOS ]]; then
        IFS=: read -p '
    Please designate a directory name
      for this multi boot installation: ' LIVEOS
        if [[ $LIVEOS =~ [[:space:]]|/ ]]; then
            printf "\n    ALERT:
    The LiveOS directory name, '%s', contains spaces, newlines,
    tabs, or '/'.

    Whitespace and '/' do not work with the SYSLINUX boot loader.\n
    Replacing the whitespace by underscores, any '/' by '-':  " "$LIVEOS"
            LIVEOS=${LIVEOS//[[:space:]]/_}
            LIVEOS=${LIVEOS////-}
            printf "'$LIVEOS'\n\n"
        fi
    fi
    multi=/$LIVEOS
fi

if [[ -e $TGTMNT/syslinux && -z $skipcopy ]] &&
   [[ -z $multi && -z $force ]]; then
    if [[ $srctype == @(netinst|installer) ]]; then
        d='the /images & boot configuration
                directories'
    else
        d='any image in the "'$LIVEOS'"
                directory'
    fi
    IFS=: read -n 1 -p '
    ATTENTION:

        >> There may be other LiveOS images on this device. <<

    Do you want a Multi Live Image installation?

        If so, press Enter to continue.

        If not, press the [space bar], and '"$d"' will be overwritten,
                and any others ignored.

    To abort the installation, press Ctrl C.
    ' multi
    if [[ $multi != " " ]]; then
        if [[ $LIVEOS == LiveOS ]]; then
            LIVEOS=$(mktemp -d $TGTMNT/XXXX)
            rmdir $LIVEOS
            LIVEOS=${LIVEOS##*/}
        fi
        multi=/$LIVEOS
    else
        unset -v multi
    fi
fi

# Backup previous config_files.
[[ -f $TGTMNT/syslinux/$CONFIG_FILE ]] &&
    cp $TGTMNT/syslinux/$CONFIG_FILE $TGTMNT/syslinux/$CONFIG_FILE.prev
[[ -f $TGTMNT$T_EFI_BOOT/grub.cfg ]] &&
    cp $TGTMNT$T_EFI_BOOT/grub.cfg $TGTMNT$T_EFI_BOOT/grub.cfg.prev
[[ -f $BOOTCONFIG_EFI ]] &&
    cp $BOOTCONFIG_EFI $BOOTCONFIG_EFI.prev

OVLPATH=$TGTMNT/$LIVEOS/$OVLNAME
if [[ -n $resetoverlay ]]; then
    existing=($(find $TGTMNT/$LIVEOS/ -name overlay-* -print || :))
    if [[ ! -s $existing ]]; then
        printf '\n        NOTICE:
        A persistent overlay was not found on the target device to reset.\n
        Press Enter to continue, or Ctrl C to abort.\n'
        read
        resetoverlay=''
    fi
fi
if [[ -n $resetoverlay ]]; then
    if [[ -n $overlaysizemb && -z $skipcopy ]]; then
        printf '\n        ERROR:
        You requested a new persistent overlay AND to reset the current one.\n
        Please select only one of these options.  Exiting...\n\n'
        exitclean
    elif [[ -n $copyoverlay && -z $skipcopy ]]; then
        printf '\n        ERROR:
        You asked to reset the target overlay AND to copy the source one.\n
        Please select only one of these options.  Exiting...\n\n'
        exitclean
    elif [[ $existing != $OVLPATH ]]; then
        # Rename overlay in case of label change.
        mv $existing $OVLPATH
    fi
fi

HOMEPATH=$TGTMNT/$LIVEOS/$HOMEFILE
SRCHOME=$SRCMNT/$srcdir/$HOMEFILE
if [[ -z $skipcopy && -f $HOMEPATH && -n $keephome && -n $homesizemb ]]; then
    printf '\n        ERROR:
        The target has an existing home.img file and you requested that a new
        home.img be created.  To remove an existing home.img on the target,
        you must explicitly specify --delete-home as an installation option.\n
        Please adjust your home.img options.  Exiting...\n\n'
    exitclean
fi
if [[ -z $skipcopy && -f $HOMEPATH && -n $keephome &&
      -n $copyhome && -s $SRCHOME ]]; then
    printf '\n        ERROR:
        The target has an existing home.img, and you requested that one from
        the source be copied to the target device.
        To remove an existing home.img on the target, you must explicitly
        specify the --delete-home option.\n
        Please adjust your home options.  Exiting...\n'
    exitclean
fi
if [[ ! -f $SRCHOME && -n $copyhome ]]; then
    printf '\n        ERROR:
        There appears to be no persistent /home.img on the source.
        Please check your inputs.  Exiting...\n'
    exitclean
fi
if [[ $SRCFS == iso9660 && -f $SRCHOME && -z $copyhome ]]; then
    printf '\n        NOTICE:
        The source has a persistent home.img intended for installation.
        If there is an existing home.img on the target device,
        you will be asked to approve its deletion.\n
        Press Enter to continue, or Ctrl C to abort.\n'
    read
    copyhome=1
fi
if [[ -f $SRCHOME && -n $copyhome && -n $cryptedhome ]]; then
    printf '\n        ATTENTION:
        The default --encrypted-home option is only available for newly-created
        home.img filesystems.  If the home.img on the source is encrypted,
        that feature will carry over to the new installation.\n
        Press Enter to continue, or Ctrl C to abort.\n'
    read
fi
if [[ -s $SRCHOME && -n $copyhome && -n $homesizemb ]]; then
    printf '\n        ERROR:
        You requested a new home AND to copy one from the source.\n
        Please request only one of these options.  Exiting...\n'
    exitclean
fi
if [[ ! -s $SRCHOME && -n $copyhome ]] &&
    [[ -n $overlaysizemb || -n $resetoverlay || -n $copyoverlay ]]; then
    printf '\n        NOTICE:
        There appears to be no persistent home.img on this source.\n
        Would you LIKE to continue with just the persistent overlay?\n
        Press Enter to continue, or Ctrl C to abort.\n'
    read
    copyhome=''
fi

if [[ $(syslinux --version 2>&1) != syslinux\ * ]]; then
    # Older versions lacking the --version option install in the root.
    SYSLINUXPATH=''
    if [[ -n $multi ]]; then
        printf '\n        ERROR:
        This version of SYSLINUX does not support multi boot.\n
        Please upgrade.  Exiting...\n\n'
        exitclean
    fi
elif [[ -n $multi ]]; then
    SYSLINUXPATH=$LIVEOS/syslinux
else
    SYSLINUXPATH=syslinux
fi

if [[ -d $SRCMNT/isolinux/ ]]; then
    CONFIG_SRC=$SRCMNT/isolinux
# Adjust syslinux sources for replication of installed images
# between filesystem types.
elif [[ -d $SRCMNT/syslinux/ ]]; then
    [[ -d $SRCMNT/$srcdir/syslinux ]] && CONFIG_SRC="$srcdir"/
    CONFIG_SRC="$SRCMNT/${CONFIG_SRC}syslinux"
fi

if [[ -n $overlayfs && -z $(lsinitrd $CONFIG_SRC/initrd*.img\
    -f usr/lib/dracut/hooks/cmdline/30-parse-dmsquash-live.sh | \
    sed -n -r '/(dev\/root|rootfsbase)/p') ]]; then
    printf '\n    NOTICE:
    The --overlayfs option requires an initial boot image based on
    dracut version 045 or greater to use the OverlayFS feature.\n
    Lacking this, the device boots with a temporary Device-mapper overlay.\n
    Press Enter to continue, or Ctrl C to abort.\n'
    read
fi

thisScriptpath=$(readlink -f "$0")
checklivespace() {
# let's try to make sure there's enough room on the target device

# var=($(du -B 1M path)) uses the compound array assignment operator to extract
# the numeric result of du into the index zero position of var.  The index zero
# value is the default operative value for the array variable when no other
# indices are specified.
    if [[ -d $TGTMNT/$LIVEOS ]]; then
        # du -c reports a grand total in the first column of the last row,
        # i.e., at ${array[*]: -2:1}, the penultimate index position.
        tbd=($(du -c -B 1M $TGTMNT/$LIVEOS $TGTMNT/images))
        tbd=${tbd[*]: -2:1}
        if [[ -s $HOMEPATH ]] && [[ -n $keephome ]]; then
            homesize=($(du -B 1M $HOMEPATH))
            tbd=$((tbd - homesize))
        fi
        if [[ -s $OVLPATH ]] && [[ -n $resetoverlay ]]; then
            overlaysize=($(du -c -B 1M $OVLPATH))
            overlaysize=${overlaysize[*]: -2:1}
            tbd=$((tbd - overlaysize))
        fi
    else
        tbd=0
    fi

    targets="$TGTMNT/$SYSLINUXPATH"
    [[ -n $T_EFI_BOOT ]] && targets+=" $TGTMNT$T_EFI_BOOT "
    [[ -n $xo ]] && targets+=$TGTMNT/boot/olpc.fth
    duTable=($(du -c -B 1M $targets 2> /dev/null || :))
    tbd=$((tbd + ${duTable[*]: -2:1}))

    if [[ -n $skipcompress ]] && [[ -s $SRCIMG ]]; then
        if mount -o loop,ro "$SRCIMG" $SRCMNT; then
            if [[ -s $SRCMNT/LiveOS/rootfs.img ]]; then
                SRCIMG=$SRCMNT/LiveOS/rootfs.img
            elif [[ -s $SRCMNT/LiveOS/ext3fs.img ]]; then
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
            livesize=($(du -B 1M "$SRCMNT/$srcdir/$squashimg"))
            SRCIMG="$SRCMNT/$srcdir/$squashimg"
        else
            echo "Exiting..."
            exitclean
        fi
    fi
    sources="$SRCMNT/$srcdir/osmin.img"\ "$SRCMNT/$srcdir/syslinux"
    sources+=" $SRCMNT/images $SRCMNT/isolinux $SRCMNT/syslinux"
    [[ -n $EFI_BOOT ]] && sources+=" $SRCMNT$EFI_BOOT"
    duTable=($(du -c -B 1M "$0" $sources 2> /dev/null || :))
    livesize=$((livesize + ${duTable[*]: -2:1} + 1))
    [[ -s $SRCHOME  && -n $copyhome ]] &&
        copyhomesize=($(du -s -B 1M $SRCHOME))
    [[ -s $SRCOVL && -n $copyoverlay ]] && {
        copyoverlaysize=($(du -c -B 1M "$SRCOVL"))
        copyoverlaysize=${copyoverlaysize[*]: -2:1}; }

    tba=$((overlaysizemb + copyoverlaysize + homesizemb + copyhomesize +
           livesize + swapsizemb))
    if ((tba > freespace + tbd)); then
        needed=$((tba - freespace - tbd))
        printf "\n  The live image + overlay, home, & swap space, if requested,
        \r  will NOT fit in the space available on the target device.\n
        \r  + Size of live image: %10s  MiB\n" $livesize
        [[ -n $overlaysizemb ]] &&
            printf "  + Overlay size: %16s\n" $overlaysizemb
        [[ -n $overlaysize ]] &&
            printf "  + Overlay size: %16s\n" $overlaysize
        [[ -n $copyoverlaysize ]] &&
            printf "  + Copy overlay size: %11s\n" $copyoverlaysize
        ((homesizemb > 0)) &&
            printf "  + Home directory size: %9s\n" $homesizemb
        [[ -n $copyhomesize ]] &&
            printf '  + Copy home directory size: %4s\n' $copyhomesize
        [[ -n $swapsizemb ]] &&
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

if [[ -z $skipcopy ]] && [[ $srctype == live ]]; then
    if [[ -d $TGTMNT/$LIVEOS ]] && [[ -z $force ]]; then
        printf "\nThe '%s' directory is already set up with a LiveOS image.\n
               " $LIVEOS
        if [[ -z $keephome && -e $HOMEPATH ]]; then
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
            [[ -e $HOMEPATH && -n $keephome ]] &&
                mv $HOMEPATH $TGTMNT/$HOMEFILE
            [[ -e $OVLPATH && -n $resetoverlay ]] &&
                mv $OVLPATH $TGTMNT/$OVLNAME
        fi
        rm -rf -- $TGTMNT/$LIVEOS
    fi
fi

# Live image copy
if [[ $srctype == live && -z $skipcopy ]]; then
    printf '\nCopying LiveOS image to target device...\n'
    [[ ! -d $TGTMNT/$LIVEOS ]] && mkdir $TGTMNT/$LIVEOS
    [[ -n $keephome && -f $TGTMNT/$HOMEFILE ]] &&
        mv $TGTMNT/$HOMEFILE $HOMEPATH
    [[ -n $resetoverlay && -e $TGTMNT/$OVLNAME ]] &&
        mv $TGTMNT/$OVLNAME $OVLPATH
    if [[ -n $skipcompress && -f $SRCMNT/$srcdir/$squashimg ]]; then
        mount -o loop,ro "$SRCMNT/$srcdir/$squashimg" $SRCMNT || exitclean
        $copyFile "$SRCIMG" $TGTMNT/$LIVEOS/rootfs.img || {
            umount $SRCMNT ; exitclean ; }
        umount $SRCMNT
    elif [[ -f $SRCIMG ]]; then
        $copyFile "$SRCIMG" $TGTMNT/$LIVEOS/${SRCIMG##/*/} || exitclean
        [[ ${SRCIMG##/*/} == squashed.img ]] &&
            mv $TGTMNT/$LIVEOS/${SRCIMG##/*/} $TGTMNT/$LIVEOS/squashfs.img
    fi
    if [[ -f $SRCMNT/$srcdir/osmin.img ]]; then
        $copyFile "$SRCMNT/$srcdir/osmin.img" $TGTMNT/$LIVEOS/osmin.img ||
            exitclean
    fi
    if [[ -s $SRCHOME && -n $copyhome ]]; then
        $copyFile $SRCHOME $HOMEPATH || exitclean
    fi
    if [[ -s $SRCOVL && -n $copyoverlay ]]; then
        printf 'Copying overlay...'
        cp -a "$SRCOVL" $OVLPATH || exitclean
        [[ -d $SRCOVL ]] && {
            cp -a "$SRCOVL/../ovlwork" $OVLPATH/../ovlwork || exitclean; }
    fi
    printf '\nSyncing filesystem writes to disc.
    Please wait, this may take a while...\n'
    sync -f $TGTMNT/$LIVEOS/
fi
if [[ -n $resetoverlay || -n $copyoverlay ]]; then
    if [[ -d $OVLPATH ]]; then
        overlayfs=$TGTFS
    else
        # Find if OVLPATH is a filesystem.
        existing=$(blkid -s TYPE -o value $OVLPATH || :)
        [[ -n $existing && $existing != DM_snapshot_cow ]] &&
            overlayfs=$existing
    fi
fi

# Bootloader is always reconfigured, so keep this out of the -z skipcopy stuff.
[[ ! -d $TGTMNT/$SYSLINUXPATH ]] && mkdir -p $TGTMNT/$SYSLINUXPATH

cp $CONFIG_SRC/* $TGTMNT/$SYSLINUXPATH

BOOTCONFIG=$TGTMNT/$SYSLINUXPATH/isolinux.cfg
# Adjust syslinux sources for replication of installed images
# between filesystem types.
if ! [[ -f $BOOTCONFIG ]]; then
    for f in extlinux.conf syslinux.cfg; do
        f=$TGTMNT/$SYSLINUXPATH/$f
        [[ -f $f ]] && mv $f $BOOTCONFIG && break
    done
fi
TITLE=$(sed -n -r '/^\s*label\s+linux/{n
                   s/^\s*menu\s+label\s+\^(Start|Install)\s+(.*)/\1 \2/p}
                  ' $BOOTCONFIG)

# Copy LICENSE and README.
if [[ -z $skipcopy ]]; then
    for f in $SRCMNT/LICENSE $SRCMNT/Fedora-Legal-README.txt; do
        [[ -f $f ]] && cp $f $TGTMNT
    done
fi

[[ -e $BOOTCONFIG_EFI.multi ]] && rm $BOOTCONFIG_EFI.multi

# Always install EFI components, when available, so that they are available to
# propagate, if desired from the installed system.
if [[ -n $EFI_BOOT ]]; then
    echo "Setting up $T_EFI_BOOT"
    [[ ! -d $TGTMNT$T_EFI_BOOT ]] && mkdir -p $TGTMNT$T_EFI_BOOT

    # The GRUB EFI config file can be one of:
    #   boot?*.conf
    #   BOOT?*.conf
    #   grub.cfg

    # Test for EFI config file on target device from previous installation.
    if [[ -f $TGTMNT$T_EFI_BOOT/grub.cfg ]]; then
        # (Prefer grub.cfg over boot*.conf set above.)
        BOOTCONFIG_EFI=$TGTMNT$T_EFI_BOOT/grub.cfg
    fi
    if [[ -n $multi && -f $BOOTCONFIG_EFI ]]; then
        mv -Tf $BOOTCONFIG_EFI $BOOTCONFIG_EFI.multi
    fi
    if [[ $TGTMNT/EFI -ef $SRCMNT/EFI ]]; then
        cp $BOOTCONFIG_EFI.multi $BOOTCONFIG_EFI
    else
        cp -Tr $SRCMNT$EFI_BOOT $TGTMNT$T_EFI_BOOT

        rm -f $TGTMNT$T_EFI_BOOT/grub.conf
    fi

    # Select config file for initial installations.
    BOOTCONFIG_EFI=$TGTMNT$T_EFI_BOOT/grub.cfg
    if [[ ! -f $BOOTCONFIG_EFI ]]; then
        BOOTCONFIG_EFI=($(nocase_path "$TGTMNT$T_EFI_BOOT/boot*.conf"))
    fi
    if [[ -n $efi && ! -f $BOOTCONFIG_EFI ]]; then
        echo "Unable to find an EFI configuration file."
        exitclean
    fi

    # On some images (RHEL) the BOOT*.efi file isn't in $EFI_BOOT, but is in
    # the eltorito image, so try to extract it, if it is missing.

    # Test for presence of *.efi grub binary.
    bootefi=($(nocase_path "$TGTMNT$T_EFI_BOOT/boot*efi"))
    #^ Use compound array assignment to accommodate presence of multiple files.
    if [[ ! -f $bootefi ]]; then
        if ! type dumpet >/dev/null 2>&1 && [[ -n $efi ]]; then
            echo "No /usr/bin/dumpet tool found. EFI image will not boot."
            echo "Source media is missing grub binary in /EFI/BOOT/*EFI."
            exitclean
        else
            # dump the eltorito image with dumpet, output is $SRC.1
            dumpet -i "$SRC" -d
            EFIMNT=$(mktemp -d /run/srctmp.XXXXXX)
            mount -o loop "$SRC".1 $EFIMNT

            bootefi=($(nocase_path "$EFIMNT$EFI_BOOT/boot*efi"))
            if [[ -f $bootefi ]]; then
                cp -t $TGTMNT$T_EFI_BOOT ${bootefi[*]}
            elif [[ -n $efi ]]; then
                echo "No BOOT*.EFI found in eltorito image. EFI will not boot."
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
# Always install /images directory, when available, so that they may be used
# to propagate a new installation from the installed system.
if [[ -z $skipcopy ]]; then
    echo "Copying /images directory to the target device."
    for f in $(find $SRCMNT/images); do
        if [[ -d $f ]]; then
            mkdir $TGTMNT$multi/${f#$SRCMNT} || exitclean
        else
            $copyFile $f $TGTMNT$multi/${f#$SRCMNT} || exitclean
        fi
    done
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
        --exclude TRANS.TBL --exclude LiveOS/ "$SRCMNT/" "$TGTMNT/"${multi#/}
    echo "Waiting for device to finish writing."
    sync -f "$TGTMNT/"
fi

if [[ $srctype == live ]]; then
    # Copy this installer script.
    cp -fT "$thisScriptpath" $TGTMNT/$LIVEOS/livecd-iso-to-disk
    chmod +x $TGTMNT/$LIVEOS/livecd-iso-to-disk &> /dev/null || :

    # When the source is an installed Live USB/SD image, restore the boot
    # config file to a base state before updating.
    if [[ -d $SRCMNT/syslinux/ ]]; then
        echo "Preparing boot config files."
        # Delete all labels before the 'linux' menu label.
        sed -i -r '/^\s*label .*/I,/^\s*label linux\>/I{
                   /^\s*label linux\>/I ! {N;N;N;N
                   /\<kernel\s+[^ ]*menu.c32\>/d};}' $BOOTCONFIG
        sed -i -r '/^\s*menu\s+end/I,$ {
                   /^\s*menu\s+end/I ! d}' $BOOTCONFIG
        # Keep only the menu entries up through the first submenu.
        if [[ -n $BOOTCONFIG_EFI ]]; then
            sed -i -r "/\s+}$/ { N
                       /\n}$/ { n;Q}}" $BOOTCONFIG_EFI
        fi
        # Restore configuration entries to a base state.
        sed -i -r "s/^\s*timeout\s+.*/timeout 600/I
/^\s*totaltimeout\s+.*/Iz
s/(^\s*menu\s+title\s+Welcome\s+to)\s+.*/\1 $TITLE/I
s/\<(kernel)\>\s+[^\n.]*(vmlinuz.?)/\1 \2/
s/\<(initrd=).*(initrd.?\.img)\>/\1\2/
s/\<(root=live:[^ ]*)\s+[^\n.]*\<(rd\.live\.image|liveimg)/\1 \2/
/^\s*label\s+linux\>/I,/^\s*label\s+check\>/Is/(rd\.live\.image|liveimg).*/\1 quiet/
/^\s*label\s+check\>/I,/^\s*label\s+vesa\>/Is/(rd\.live\.image|liveimg).*/\1 rd.live.check quiet/
/^\s*label\s+vesa\>/I,/^\s*label\s+memtest\>/Is/(rd\.live\.image|liveimg).*/\1 nomodeset quiet/
                  " $BOOTCONFIG
    fi
    # And, if --multi, distinguish the new grub menuentry with $LIVEOS ~.
    if [[ -n $BOOTCONFIG_EFI ]]; then
        [[ -f $BOOTCONFIG_EFI.multi ]] && livedir=$LIVEOS\ ~
        sed -i -r "s/^\s*set\s+timeout=.*/set timeout=60/
/^\s*menuentry\s+'Start\s+/,/\s+}/{s/(\s+'Start\s+)[^ ]*\s+~/\1/
s/\s+'Start\s+/&$livedir/
s/(rd\.live\.image|liveimg).*/\1 quiet/}
/^\s*menuentry\s+'Test\s+/,/\s+}/{s/(\s+&\s+start\s+)[^ ]*\s+~/\1/
s/\s+&\s+start\s+/&$livedir/
s/(rd\.live\.image|liveimg).*/\1 rd.live.check quiet/}
/^\s*submenu\s+'Trouble/,/\s+}/s/(rd\.live\.image|liveimg).*/\1 nomodeset quiet/
s/(linuxefi\s+[^ ]+vmlinuz.?)\s+.*\s+(root=live:[^\s+]*)/\1 \2/
s_(linuxefi|initrdefi)\s+[^ ]+(initrd.?\.img|vmlinuz.?)_\1 /images/pxeboot/\2_
              " $BOOTCONFIG_EFI
    fi
fi

# Setup the updates.img
if [[ -n $updates ]]; then
    $copyFile "$updates" "$TGTMNT$multi/updates.img"
    kernelargs+=" inst.updates=hd:$TGTLABEL:$multi/updates.img"
fi

# Setup the kickstart
if [[ -n $ks ]]; then
    $copyFile "$ks" "$TGTMNT$multi/ks.cfg"
    kernelargs+=" inst.ks=hd:$TGTLABEL:$multi/ks.cfg"
fi

echo "Updating boot config files."
# adjust label and fstype
sed -i -r "s/\<root=[^ ]*/root=live:$TGTLABEL/g
        s;inst.stage2=hd:LABEL=[^ ]*;inst.stage2=hd:$TGTLABEL${multi/*/:$multi/images/install.img};g
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
    # EFI images are in $SYSLINUXPATH now.
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
    if [[ -n $BOOTCONFIG_EFI ]]; then
        if [[ $timeout != @(0|-1) ]]; then
            set +e
            ((timeout = (timeout%10) > 4 ? (timeout/10)+1 : (timeout/10) ))
            set -e
        fi
        sed -i -r "s/^\s*(set\s+timeout=).*$/\1$timeout/" $BOOTCONFIG_EFI
    fi
fi
if [[ -n $totaltimeout ]]; then
    sed -i -r "/\s*timeout\s+.*/ a\totaltimeout\ $totaltimeout" $BOOTCONFIG
fi

if [[ $overlay == none ]]; then
    sed -i -r 's/rd\.live\.image|liveimg/& rd.live.overlay=none/
              ' $BOOTCONFIG $BOOTCONFIG_EFI
fi

# Don't display boot.msg.
if [[ -n $nobootmsg ]]; then
    sed -i '/display boot.msg/d' $BOOTCONFIG
fi
# Skip the menu, and boot 'linux'.
if [[ -n $nomenu ]]; then
    sed -i 's/default .*/default linux/' $BOOTCONFIG
fi

if [[ -n $overlaysizemb || -n $overlayfs ]] &&
    [[ -z $resetoverlay && -z $copyoverlay ]]; then
    if [[ -z $skipcopy ]]; then
        echo "Initializing persistent overlay..."
        if [[ $TGTFS == @(vfat|msdos) && $overlayfs != temp ]]; then
            # vfat can't handle sparse files
            dd if=/dev/zero of=$OVLPATH count=$overlaysizemb bs=1M
            if [[ $overlayfs == @(vfat|msdos) ]]; then
                echo 'Formatting overlayfs...'
                mkfs.ext4 -F -j $OVLPATH
                tune2fs -c0 -i0 -ouser_xattr,acl $OVLPATH
                ovl=$(mktemp -d)
                mount $OVLPATH $ovl
                mkdir $ovl/overlayfs
                chcon --reference=/. $ovl/overlayfs
                mkdir $ovl/ovlwork
                umount $ovl
            fi
        elif [[ -z $overlayfs ]]; then
            dd if=/dev/null of=$OVLPATH count=1 bs=1M seek=$overlaysizemb
            chmod 0600 $OVLPATH &> /dev/null || :
        elif [[ $overlayfs != temp ]]; then
            mkdir $OVLPATH
            chcon --reference=/. $OVLPATH
            mkdir $OVLPATH/../ovlwork
        fi
    fi
    if [[ -n $overlayfs ]]; then
        sed -i -r 's/rd\.live\.image|liveimg/& rd.live.overlay.overlayfs/
                  ' $BOOTCONFIG $BOOTCONFIG_EFI
    fi
    if [[ -n $overlaysizemb || x${overlayfs#temp} != x ]]; then
        sed -i -r "s/rd\.live\.image|liveimg/& rd.live.overlay=${TGTLABEL}/
                  " $BOOTCONFIG $BOOTCONFIG_EFI
    fi
fi

# (Allow overlay reset with --skipcopy repair.)
if [[ -n $resetoverlay ]]; then
    printf 'Resetting the overlay.\n'
    if [[ $overlayfs == @(vfat|msdos) ]]; then
        ovl=$(mktemp -d)
        mount $OVLPATH $ovl
        rm -r -- $ovl/overlayfs
        mkdir $ovl/overlayfs
        umount $ovl
    elif [[ -d $OVLPATH ]]; then
        rm -r -- $OVLPATH
        mkdir $OVLPATH
        mkdir $OVLPATH/../ovlwork
        chcon --reference=/. $OVLPATH
    else
        dd if=/dev/zero of=$OVLPATH bs=64k count=1 conv=notrunc,fsync
    fi
fi
if [[ -n $resetoverlay || -n $copyoverlay ]]; then
    ovl=''
    [[ -n $overlayfs ]] && ovl=' rd.live.overlay.overlayfs'
    sed -i -r "s/rd\.live\.image|liveimg/& rd.live.overlay=${TGTLABEL}$ovl/
              " $BOOTCONFIG $BOOTCONFIG_EFI
fi

if ((swapsizemb > 0)); then
    echo "Initializing swap file."
    if [[ -z $skipcopy ]]; then
        dd if=/dev/zero of=$TGTMNT/$LIVEOS/swap.img count=$swapsizemb bs=1M
        chmod 0600 $TGTMNT/$LIVEOS/swap.img &> /dev/null || :
    fi
    mkswap -f $TGTMNT/$LIVEOS/swap.img
fi

if ((homesizemb > 0)) && [[ -z $skipcopy ]]; then
    echo "Initializing persistent /home"
    homesource=/dev/zero
    [[ -n $cryptedhome ]] && homesource=/dev/urandom
    if [[ $TGTFS = vfat ]]; then
        # vfat can't handle sparse files.
        dd if=${homesource} of=$HOMEPATH count=$homesizemb bs=1M
    else
        dd if=/dev/null of=$HOMEPATH count=1 bs=1M seek=$homesizemb
    fi
    chmod 0600 $HOMEPATH &> /dev/null || :
    if [[ -n $cryptedhome ]]; then
        loop=$(losetup -f --show $HOMEPATH)

        echo "Encrypting persistent home.img"
        while ! cryptsetup luksFormat -y -q $loop; do :; done;

        echo "Please enter the password again to unlock the device"
        while ! cryptsetup luksOpen $loop EncHomeFoo; do :; done;

        mkfs.ext4 -j /dev/mapper/EncHomeFoo
        tune2fs -c0 -i0 -ouser_xattr,acl /dev/mapper/EncHomeFoo
        sleep 2
        cryptsetup luksClose EncHomeFoo
        losetup -d $loop
    else
        echo "Formatting unencrypted home.img"
        mkfs.ext4 -F -j $HOMEPATH
        tune2fs -c0 -i0 -ouser_xattr,acl $HOMEPATH
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
    if [[ -z $xonohome && ! -f $HOMEPATH ]]; then
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

BOOTPATH=$SYSLINUXPATH
[[ -n $multi ]] && BOOTPATH=syslinux

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
                cp $d/$f $TGTMNT/$BOOTPATH/$f
                break 2
            fi
        done
    fi
done

if [[ $multi == /$LIVEOS ]]; then
    # We need to do some more config file tweaks for multi-image mode.
    sed -i -r "s;\s+[^ ]*menu\.c32\>; $UI;g
               s;kernel\s+vm;kernel /$LIVEOS/syslinux/vm;
               s;initrd=i;initrd=/$LIVEOS/syslinux/i;
              " $TGTMNT/$SYSLINUXPATH/isolinux.cfg
    sed -i -r "1,20 s/^\s*(menu\s+title)\s+.*/\1 Multi Live Image Boot Menu/I
               /^\s*label\s+$LIVEOS\>/I { N;N;N;N; d }
               0,/^\s*label\s+.*/I {
               /^\s*label\s+.*/I {
               i\
               label $LIVEOS\\
\  menu label ^Go to $LIVEOS ~$TITLE menu\\
\  kernel $UI\\
\  APPEND /$LIVEOS/syslinux/$CONFIG_FILE\\

               };}" $TGTMNT/syslinux/$CONFIG_FILE

    cat << EOF >> $TGTMNT/$SYSLINUXPATH/isolinux.cfg
menu separator
LABEL multimain
  MENU LABEL Return to Multi Live Image Boot Menu
  KERNEL $UI
  APPEND ~
EOF
fi

mv $TGTMNT/$SYSLINUXPATH/isolinux.cfg $TGTMNT/$SYSLINUXPATH/$CONFIG_FILE

sed -i -r "s/\s+[^ ]*menu\.c32\>/ $UI/g" $TGTMNT/syslinux/$CONFIG_FILE

if [[ -f $BOOTCONFIG_EFI.multi ]]; then
    # (Implies --multi and the presence of EFI components.)
    # Insert marker and delete any conflicting menu entries
    # after escaping special characters.
    d=$(sed 's/?/\\?/g;s/+/\\+/g;s/|/\\|/g;s/{/\\{/g;s/}/\\}/g' <<< $LIVEOS)
    sed -i -r "1 i\
...
               /^\s*menuentry\s+/ { N;N;N
               /\s+rd\.live\.dir=$d\s+/ d }
               /\s*submenu\s+/ { N;N;N;N;N
               /\s+rd\.live\.dir=$d\s+/ d }
              " $BOOTCONFIG_EFI.multi
    cat $BOOTCONFIG_EFI.multi >> $BOOTCONFIG_EFI
    # Clear header from $BOOTCONFIG_EFI.multi.
    sed -i -r '/^\.\.\.$/,/^\s*menuentry\s+/ {
               /^\s*menuentry\s+/ ! d}' $BOOTCONFIG_EFI
    rm $BOOTCONFIG_EFI.multi
fi

# Always make the following adjustments.
echo "Installing boot loader..."
if [[ -f $TGTMNT$T_EFI_BOOT/BOOT.conf ]]; then
    if [[ -f $TGTMNT$T_EFI_BOOT/BOOTia32.conf ]]; then
        # replace the ia32 hack. BOOTia32.conf was in Fedora 11-14.
        cp -f $TGTMNT$T_EFI_BOOT/BOOTia32.conf $TGTMNT$T_EFI_BOOT/BOOT.conf
    elif [[ $BOOTCONFIG_EFI -ef $TGTMNT$T_EFI_BOOT/BOOT.conf ]]; then
        cp -f $BOOTCONFIG_EFI $TGTMNT$T_EFI_BOOT/grub.cfg
    else
        # Fedora 27+ duplicates /EFI/BOOT/grub.cfg at /EFI/BOOT/BOOT.conf
        cp -f $BOOTCONFIG_EFI $TGTMNT$T_EFI_BOOT/BOOT.conf
    fi
fi

# syslinux >= 6.02 also requires ldlinux.c32, libcom32.c32, libutil.c32
# Since the version of syslinux being used is the one on the host, they may
# not be available on the source, so copy them from the host, when available.
for f in ldlinux.c32 libcom32.c32 libutil.c32; do
    if [[ -f /usr/share/syslinux/$f ]]; then
        cp /usr/share/syslinux/$f $TGTMNT/$BOOTPATH/$f
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

    # Deal with mtools complaining about ldlinux.sys
    if [[ -f $TGTMNT/$BOOTPATH/ldlinux.sys ]]; then
        rm -f $TGTMNT/$BOOTPATH/ldlinux.sys
    fi
    cleanup
    if [[ -n $BOOTPATH ]]; then
        syslinux -d $BOOTPATH $TGTDEV
    else
        syslinux $TGTDEV
    fi
elif [[ $TGTFS == @(ext[234]|btrfs) ]]; then
    # extlinux expects the config to be named extlinux.conf
    # and has to be run with the file system mounted.
    extlinux -i $TGTMNT/$BOOTPATH >/dev/null 2>&1
    # Starting with syslinux 4 ldlinux.sys is used on all file systems.
    if [[ -f $TGTMNT/$BOOTPATH/extlinux.sys ]]; then
        chattr -i $TGTMNT/$BOOTPATH/extlinux.sys
    elif [[ -f $TGTMNT/$BOOTPATH/ldlinux.sys ]]; then
        chattr -i $TGTMNT/$BOOTPATH/ldlinux.sys
    fi
    cleanup
fi

[[ -n $multi ]] && multi=Multi\ 
echo "Target device is now set up with a ${multi}Live image!"

