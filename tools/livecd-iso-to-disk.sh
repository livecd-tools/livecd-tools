#!/bin/bash
# Transfer a Live image so that it's bootable off of a USB/SD device.
# Copyright 2007-2012, 2017, Red Hat, Inc.
# Copyright 2008-2010, 2017-2021, Fedora Project
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
trap error_report ERR

shortusage() {
    echo "
    SYNTAX

    livecd-iso-to-disk [--format [<size>[,fstype[,blksz[,extra_attr,s]]]]]
                       [--msdos] [--efi] [--noesp] [--nomac] [--reset-mbr]
                       [--multi] [--livedir <directory>] [--skipcopy]
                       [--noverify] [--force] [--xo] [--xo-no-home]
                       [--timeout <duration>] [--totaltimeout <duration>]
                       [--nobootmsg] [--nomenu] [--extra-kernel-args <arg s>]
                       [--overlay-size-mb <size>[,fstype[,blksz]]]
                       [--overlayfs [temp]] [--copy-overlay] [--reset-overlay]
                       [--compress] [--skipcompress] [--no-overlay]
                       [--home-size-mb <size>[,fstype,blksz]]] [--copy-home]
                       [--delete-home] [--crypted-home] [--unencrypted-home]
                       [--swap-size-mb <size>] [--updates <updates.img>]
                       [--ks <kickstart>] [--label <label>] [--help]
                       <source> <target partition/device>

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

             <target partition/device>
                 This should be, or a link to, the device partition path for
                 an attached, target device, such as /dev/sdc1.  A virtual
                 block device, such as a loop device or a Device-mapper target
                 may also be used.  (Issue the lsblk -pf command to get a list
                 of attached partitions, so you can confirm the device names,
                 filesystem types, and available space.)  Be careful to specify
                 the correct device, or you may overwrite important data on
                 another disk!  If you request formatting with the --format
                 option, enter only the base device path, such as /dev/sdc.
                 For a multi boot installation to the currently booted
                 device, enter 'live' as the target.

    To execute the script to completion, you will need to run it with root user
    permissions.  Legacy booting of the installed image requires that SYSLINUX
    is installed on the host computer running this script.

    DESCRIPTION

    livecd-iso-to-disk installs a Live CD/DVD/USB image (LiveOS) onto a USB/SD
    storage device.  The target storage device can then support booting the
    installed operating system on systems that support booting via the USB or
    the SD interface.  The script requires a LiveOS source image and a target
    storage device.  A loop device backed by a file may also be targeted for
    virtual block device installation.  Additionally, a Device-mapper target
    construct for block devices may be used.  If a Device-mapper mirror target
    is preconfigured, this target may be used to simultaneously target multiple
    physical devices.  The source image may be either a LiveOS .iso file, or
    another reference to a LiveOS image, such as the device node for an
    attached device installed with a LiveOS image, its mount point, a loop
    device backed by a file containing an installed LiveOS image, or even the
    currently-running LiveOS image.

    A pre-sized overlay file or a free-space-sized OverlayFS directory may be
    created for saving changes in the root filesystem of the installed image
    onto persistent storage media.

    Unless you request the --format option, installing an image does not
    destroy data outside of the LiveOS, syslinux, & EFI directories on your
    target device.  This allows one to maintain other files on the target disk
    outside of the LiveOS filesystem.

    Multi image installations may be invoked interactively if the target device
    already contains a LiveOS image.

    LiveOS images employ embedded filesystems through the loop device,
    Device-mapper, or OverlayFS components of the Linux kernel.  The
    filesystems are embedded within files or directories in the /LiveOS/
    directory (by default) of the base filesystem on the storage device.  The
    /LiveOS/squashfs.img file is a SquashFS format compressed image, which by
    default contains one directory and file, /LiveOS/rootfs.img, that contains
    the root filesystem for the installed distribution image.  These both are
    read-only filesystems that are fixed in size usually to within a few GiB of
    the size of the full root filesystem at build time.  At boot time, either a
    Device-mapper snapshot with a temporary, 32 GiB, sparse, in-memory,
    read-write, overlay is created for the root filesystem, or an OverlayFS
    directory may be configured during bootup if configured on disk or by
    kernel command line options.  When one specifies a persistent, fixed-size,
    Device-mapper overlay to hold changes to the root filesystem, the
    build-time size of the root filesystem will limit the maximum size of the
    working root filesystem——even if it is supplied with an overlay file larger
    than the apparent free space of the root filesystem.  Persistent OverlayFS
    directories avoid this limitation by creating a working union of two
    filesystems to serve as root filesystem.

    NOTE WELL: Deletion of any of the original files in the read-only root
    filesystem does not recover any storage space on your LiveOS device.
    Storage in a Device-mapper overlay is allocated as needed.  If its overlay
    storage space is filled, the overlay will enter an 'Overflow' state while
    the root filesystem continues to operate in a read-only mode.  There will
    not be an explicit warning or signal when this happens, but applications
    may begin to report errors due to this restriction.  If many or large
    changes or updates to the root filesystem are to be made, carefully watch
    the fraction of space allocated in the overlay by issuing the command
    'dmsetup status' at a terminal or console of the running LiveOS image.
    Consumption of root filesystem and overlay space can be avoided by
    specifying a persistent home filesystem for user files, which will be saved
    in a fixed-size /LiveOS/home.img file.  This filesystem is encrypted by
    default.  (One may bypass encryption with the --unencrypted-home option.)
    This filesystem is mounted on the /home directory of the root filesystem.
    When its storage space is filled, out-of-space warnings will be issued by
    the operating system.
        When an OverlayFS overlay is requested (with the --overlayfs option),
    any changes to the root filesytem are saved in a directory space that is
    unioned by the kernel with the read-only root filesystem.  With non-vfat-
    formatted devices, the OverlayFS can extend the available root filesystem
    space up to the capacity of the Live USB/SD device.

    OPTIONS

    --format [sizemb[,fstype[,blksz[,extra_attr,s]]]]
        Partitions and formats the target device, creates an MS-DOS partition
        table or GUID partition table (GPT), if the --efi option is passed,
        creates 1 to 3 partitions, and invokes the --reset-mbr action.

        NOTE WELL: All current disk content will be lost.

          Partition 1 is sized as requested or as available & fstype formatted.
            fstype may be: ext[432](ext4 default)|fat|vfat|msdos|btrfs|xfs|f2fs
            (extra_attr,s may be passed to f2fs formatting, for example,
            --format f2fs,-,extra_attr,compression  Until GRUB's f2fs.mod is
            updated, any extra_attr will require booting with an EFI Boot Stub
            loader, such as the one from dracut triggered by the above format
            request.)  Partition 1 is labelled as before or requested,
            flagged as bootable, and may allow an optional block size.
          Partition 2 is fat16 formatted and labelled 'EFI System Partition'.
          Partition 3 is HFS+ formatted and labelled as 'Mac'.

            Creation of partitions 2 & 3 is dependent on the presence of the
            files /images/efiboot.img & /images/macboot.img in the source.

    --msdos (a legacy option. Use the --format msdos syntax instead.)
        Forces format to use the msdos (vfat) filesystem instead of ext4.

     --efi|--mactel
        NOTE: Even without this option, EFI components are always configured
              and loaded on the target disk if they are present on the source.
        When --efi is used with --format, a GUID partition table (GPT) and 1 to
          3 partitions are created.  A hybrid Extensible Firmware Interface
          (EFI)/MBR bootloader is installed on the disk.
          This option is necessary for most Intel Macs.
        When --efi is used without --format but with --reset-mbr,
          it loads a hybrid (EFI)/MBR bootloader on the device.

     --noesp    (Used with --format)
        Skips the formatting of a secondary EFI System Partition and
          an Apple HFS+ boot partition.
        NOTE: Even with this option, EFI components are configured and loaded
              on the primary partition if they are present on the source.

     --nomac    (Used with --format)
        Skips the formatting of an Apple HFS+ boot partition.  Useful when
        hfsplus-tools are not available.

   --reset-mbr|--resetmbr
        Sets the Master Boot Record (MBR) of the target storage device to the
        mbr.bin or gptmbr.bin file from the installation system's syslinux
        directory.  This may be helpful in recovering a damaged or corrupted
        device.  Also sets the legacy_boot flag on the primary partition for
        GPT disks.

    --multi
        Signals the boot configuration to accommodate multiple images on the
        target device.  Image and boot files will be installed under the
        --livedir <directory>.  SYSLINUX boot components from the installation
        host will always update those in the boot path of the target device.
        Boot files in the /EFI directories will be replaced by files from the
        source if they have newer modified times.

    --livedir <directory>
        Designates the directory for installing the LiveOS image.  The default
        is /LiveOS.

    --skipcopy|--reconfig
        Skips the copying of the live image to the target device, bypassing the
        action of the --format, --overlay-size-mb, --copy-overlay,
        --home-size-mb, --copy-home, & --swap-size-mb options, if present on
        the command line. (The --skipcopy option is useful while testing the
        script, in order to avoid repeated and lengthy copy operations, or with
        --reset-mbr, to repair or reinstall the boot configuration files on a
        previously installed LiveOS device.)

    --noverify
        Disables the image validation process that occurs before the image is
        copied from the original Live CD .iso image.  When this option is
        specified, the image is not verified before it is copied onto the
        target storage device.

    --force
        This option forces an overwrite of the --livedir image, its syslinux
        directory, and associated files like home.img.  This allows the script
        to bypass a delete confirmation dialog in the event that a pre-existing
        LiveOS directory is found on the target device.  It also skips writing
        a new boot entry in the current system's UEFI boot manager for F2FS
        formatted target devices.

    --xo
        Used to prepare an image for the OLPC XO-1 laptop with its compressed,
        JFFS2 filesystem.  Do not use the following options with --xo:
            --overlay-size-mb <size>, home-size-mb <size>, --delete-home,
            --compress

    --xo-no-home
        Used together with the --xo option to prepare an image for an OLPC XO
        laptop with the /home directory on an SD card instead of the internal
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

    --extra-kernel-args <arg s>
        Specifies additional kernel arguments, <arg s>, that will be inserted
        into the syslinux and EFI boot configurations.  Multiple arguments
        should be specified in one string, i.e.,
            --extra-kernel-args \"arg1 arg2 ...\"

    --overlay-size-mb size[,fstype[,blksz]]
        Specifies creation of a filesystem overlay of <size> mebibytes (integer
        values only).  [fstype] and [blksz] are relevant only for creating
        OverlayFS overlay filesystems on vfat-formatted primary devices.  An
        overlay makes persistent storage available to the live operating
        system, if permitted and installed on writable media.  The overlay
        holds a snapshot of changes to the root filesystem.
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
        overlay.  A maximum <size> of 4096 MiB is permitted for vfat-formatted
        devices.  If there is not enough room on your device, you will be given
        information to help in adjusting your settings.

    --overlayfs [temp]  (add --overlay-size-mb for persistence on vfat devices)
        Specifies the creation of an OverlayFS type overlay.  If the option is
        followed by 'temp', a temporary overlay will be used.  On vfat or msdos
        formatted devices, --overlay-size-mb <size> must also be provided for a
        persistent overlay.  OverlayFS overlays are directories of the files
        that have changed on the read-only root filesystem.  With non-vfat-
        formatted devices, the OverlayFS can extend the available root
        filesystem space up to the capacity of the Live USB/SD device.

        The --overlayfs option requires an initial boot image based on dracut
        version 045 or greater to use the OverlayFS feature.  Lacking this, the
        device boots with a temporary Device-mapper overlay.

    --copy-overlay
        This option allows one to copy the persistent overlay from one live
        image to the new image.  Changes already made in the source image will
        be propagated to the new installation.
            WARNING:  User sensitive information such as password cookies and
            application or user data will be copied to the new image!  Scrub
            this information before using this option.

    --reset-overlay
        This option will reset the persistent overlay to an unallocated state.
        This might be used if installing a new or refreshed image onto a device
        with an existing overlay, and avoids the writing of a large file on a
        vfat-formatted device.  This option also renames the overlay to match
        the current device filesystem label and UUID.

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

    --home-size-mb <size>[,fstype[,blksz]]
        Specifies creation of a home filesystem of <size> mebibytes (integer
        values only).  A persistent home directory will be stored in the
        /LiveOS/home.img filesystem image file.  This filesystem is encrypted
        by default and not compressed  (one may bypass encryption with the
        --unencrypted-home option).  When the home filesystem storage space is
        full, one will get out-of-space warnings from the operating system.
        The target storage device must have enough free space for the image,
        any overlay, and the home filesystem.  Note that the --delete-home
        option must also be selected to replace an existing persistent home
        with a new, empty one.  A maximum <size> of 4096 MiB is permitted for
        vfat-formatted devices.  If there is not enough room on your device,
        you will be given information to help in adjusting your settings.

    --copy-home
        This option allows one to copy a persistent home.img filesystem from
        the source LiveOS image to the target image.  Changes already made in
        the source home directory will be propagated to the new image.
            WARNING:  User-sensitive information, such as password cookies and
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
        target device.  A maximum <size> of 4096 MiB is permitted for vfat-
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
        Specifies a specific filesystem label instead of the default 'LIVE'.
        Useful when you do unattended installs that pass a label to inst.ks.

    --help|-h|-?
        Displays usage information and exits.

    CONTRIBUTORS

    livecd-iso-to-disk: David Zeuthen, Jeremy Katz, Douglas McClendon,
                        Chris Curran and other contributors.
                        (See the AUTHORS file in the source distribution for
                        the complete list of credits.)

    BUGS

    Report bugs to the mailing list
    https://admin.fedoraproject.org/mailman/listinfo/livecd or directly to
    Bugzilla https://bugzilla.redhat.com/bugzilla/ against the Fedora product,
    and the livecd-tools component.

    COPYRIGHT

    Copyright 2008-2010, 2017-2021, Fedora Project and various contributors.
    This is free software. You may redistribute copies of it under the terms of
    the GNU General Public License https://www.gnu.org/licenses/gpl.html.
    There is NO WARRANTY, to the extent permitted by law.

    SEE ALSO

    livecd-creator, project website https://fedoraproject.org/wiki/FedoraLiveCD
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

error_report() {
    RETVAL=$?
    printf "Error %s detected at line %s\n" $RETVAL "$(caller)" >&2
    exitclean $RETVAL
}

checkForSyslinux() {
    if ! type syslinux >/dev/null 2>&1; then
        printf '\n        ATTENTION:
        The installation host is missing the SYSLINUX boot loader software.\n
        Legacy booting via SYSLINUX-EXTLINUX will not be possible on the
        installed device.  UEFI booting may be possible via GRUB or
        another boot loader.\n
        Install SYSLINUX-EXTLINUX with the command:
            sudo dnf install syslinux\n
        Press Enter to continue, or Ctrl C to abort.'
        syslinuxboot=missing
        read
    fi
}

fscheck() {
    local fstype=$1
    local fs=$2
    case $fstype in
        ext[432])
            e2fsck -yfv $fs || :
            ;;
        vfat|msdos)
            fsck.fat -avVw $fs
            ;;
        btrfs)
            btrfs check -p --repair --force $fs
            ;;
        xfs)
            xfs_repair -v $fs
            ;;
        hfsplus)
            fsck.hfsplus -yfp $fs
            ;;
        f2fs)
            fsck.f2fs -f $fs
    esac
}

cleansrc() {
    umount $IMGMNT $IMGMNT &> /dev/null || :
    rmdir $IMGMNT &> /dev/null || :
}

cleanup() {
    sync -f $TGTMNT/$LIVEOS/ &> /dev/null || :
    losetup -d $l2 $l3 &> /dev/null || :
    if [[ -d $SRCMNT && -z $SRCwasMounted ]]; then
        umount $SRCMNT && rmdir $SRCMNT
    fi
    umount $TGTMNT &> /dev/null || :
    for p in $(findmnt -nro TARGET -S $TGTDEV || :); do
        umount -l $p
    done
    [[ -d $TGTMNT ]] && rmdir $TGTMNT
    if [[ -d $d ]] && mountpoint -q $d; then
        umount $d && rmdir $d
    fi
    sleep 2
    if [[ -z $1 ]]; then
        fscheck $TGTFS $TGTDEV || :
    fi
    if [[ $(lsblk -ndo TYPE $device) == dm ]]; then
        dmsetup -v remove ${p3##*/} ${p2##*/}
    fi
}

exitclean() {
    RETVAL=${1:-$?}
    if [[ -d $IMGMNT || -d $SRCMNT || -d $TGTMNT ]]; then
        [[ $RETVAL == 0 ]] || echo "Cleaning up to exit..."
        cleansrc
        cleanup $RETVAL
    fi
    trap - EXIT
    exit $RETVAL
}

checkinput() {
    local val=$1
    local measure=$2
    local fstype=$3
    local use=$4
    case $measure in
        format)
            local re='[1-9]*([0-9])'
            case $val in
                $re)
                    if (($val < 512)); then
                        echo -e "
                        NOTE: '$val MiB' may be small for an image partition."
                        exit 1
                    else
                        return 0
                    fi
                    ;;
                *)
                    echo -e "
                    ERROR: '$val' is not a valid integer entry for format size
                                  in MiB.\n"
                    exit 1
            esac
            ;;
        timeout)
            if [[ $val != @(0|-0|-1|[1-9]*([0-9])) ]]; then
                shortusage
                echo -e "\nERROR: '$1' is not a valid integer for --$2.\n"
                exit 1
            fi
            ;;
        totaltimeout)
            if [[ $val != @(0|[1-9]*([0-9])) ]]; then
                shortusage
                echo -e "\nERROR: '$1' is not a valid integer for --$2.\n"
                exit 1
            fi
            ;;
        blocksize)
            case $fstype in
                fat|vfat|msdos)
                    if [[ $val != @(512|1024|2048|4096|8192|16384|32768) ]]; then
                        printf '
                        ERROR:  < %s > is not a valid sector size for FAT.
                        512, 1024, 2048, 4096, 8192, 16384, & 32768 bytes may
                        be specified. Values larger than 4096 do not conform to
                        the FAT file system specification and may not work
                        everywhere.\n
                        ' $1
                        exit 1
                    fi
                    if [[ $use == dev ]] && ((val > 512)); then
                        printf '
                        WARNING:
                        Block sizes greater that 512 bytes on vfat partitions
                        are not suitable for SYSLINUX bootable partitions.
                        Press Ctrl C to abort or Enter to continue...\n'
                        read
                    fi
                    if [[ $use == home ]]; then
                        printf '
                        WARNING:
                        Using a FAT filesystem for a GNU/Linux home directory
                        will cause many core applications and services to fail
                        do to its limitations in managing access rights.
                        Press Ctrl C to abort or Enter to continue...\n'
                        read
                    fi
                    ;;
                ext[432])
                    if [[ $val == ?(-)!(1024|2048|4096) ]]; then
                        printf '
                        ERROR: < %s > is not a valid block size for the %s fs.
                        1024, 2048, and 4096 bytes may be specified.\n\n' $1 $3
                        exit 1
                    fi
                    ;;
                xfs)
                    if [[ $val != @(512|4096|65536) ]]; then
                        printf '
                        ERROR: < %s > is not a valid block size for the xfs fs.
                        512, 4096, and 65536 bytes may be specified.\n' $1
                        exit 1
                    fi
                    local s=$(LC_ALL=C getconf PAGESIZE)
                    if [[ $use == dev ]] && ((val > s)); then
                        printf '
                        WARNING:
                        Partitions with block sizes greater than the
                        pagesize, %s bytes, may not be mountable by
                        default on this system.
                        Press Ctrl C to abort, or Enter to continue...\n' $s
                        read
                    fi
                    ;;
                btrfs)
                    local -n var
                    case $use in
                        ovl)
                            var=overlaysizeb ;;
                        home)
                            var=homesizeb ;;
                        dev)
                            var=format
                    esac
                    if (( var < 16<<30)); then
                        if [[ $val != 4 ]]; then
                        printf '
                        ERROR: Illegal metadata nodesize < %s KiB> for btrfs
                        mixed block group filesystems.  Mixed block groups are
                        configured by this installer for filesystems smaller
                        than 16 GiB.  4 KiB is required for mixed block groups.
                        \n' $1
                        exit 1
                        fi
                    elif [[ $val != @(16|32|64) ]]; then
                        printf '
                        ERROR:  < %s KiB> is not a valid metadata node size for
                        btrfs.  16 KiB is the default; 64 KiB is the maximum.\n
                        ' $1
                        exit 1
                    fi
                    ;;
                f2fs)
                    if [[ $val != @(4096|-) ]]; then
                        printf '
                        ERROR:  F2FS does not support block sizes other than
                                4096 bytes.\n'
                        exit 1
                    fi
            esac
            ;;
        *)
            if [[ $val != [1-9]*([0-9]) ]]; then
                shortusage
                echo -e "\nERROR: '$1' is not a valid integer for $2.\n"
                exit 1
            fi
    esac
}

checkfstype() {
    local fstype=$1
    local fs=$2
    fserr() {
        printf '
                ERROR:  < %s > is not a supported filesystem type.\n
                Supported filesystems are %sext[432], btrfs, xfs, & f2fs.\n
                Please adjust this option.  Exiting...\n\n' $1 "$2"
                exit 1
        }
    case $fstype in
        f2fs)
            if ! type mkfs.f2fs >/dev/null 2>&1; then
                printf '
                NOTICE:  f2fs-tools must be installed in the host operating
                system in order to create F2FS filesystems.\n
                Run the command "sudo dnf install f2fs-tools".  Exiting...\n\n'
                exit 1
            fi
    esac
    case $fs in
        dev)
            # Set filesystem metadata allowance factor.
            case $fstype in
            ext[432])
                m=5       # 1>>5 = 1/32
                ;;
            xfs)
                m=6       # 1>>6 = 1/64
                ;;
            fat|vfat|msdos)
                m=9       # 1>>9 = 1/512
                ;;
            btrfs)
                m=10     # 1>>10 = 1/1024
                ;;
            f2fs)
                m=4       # 1>>4 = 1/16
                if [[ ${format[*]:3} =~ extra_attr ]] &&
                    ! type objcopy >/dev/null 2>&1; then
                    printf '
                    NOTICE:  The host operating system must have the binutils
                    package installed in order to build a UEFI executable for
                    use as an EFI Boot Stub loader, which is required currently
                    due to a bug in GRUB'\''s f2fs.mod that prevents reading
                    an F2FS-formatted image with extra_attr or compression.\n
                    Run the command "sudo dnf install binutils".\n
                    Press Ctrl C to abort, or Enter to continue...\n\n'
                    read
                    nouefi=nouefi
                fi
                ;;
            *)
                fserr $fstype 'fat|vfat|msdos, '
        esac
            ;;
        ovl)
            if [[ $fstype == !(ext[432]|btrfs|xfs|f2fs) ]]; then
                fserr $fstype ''
            fi
            ;;
        home)
            if [[ $fstype == !(fat|vfat|msdos|ext[432]|btrfs|xfs|f2fs) ]]; then
                fserr $fstype 'fat|vfat|msdos, '
            fi
    esac
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
    local dev=$1

    p=$(udevadm info -q path -n $(readlink -nf $dev))
    if [[ -d /sys/$p/loop ]] || [[ -d /sys/$p/device ]] ||
       [[ -d /sys/$p/dm ]]; then
        device=${p##*/}
    else
        local d=$(readlink -nf /sys/$p/../)
        device=${d##*/}
    fi
    if [[ $device =~ loop ]] &&
        ! [[ $'\n'$(lsblk -nro NAME /dev/loop[0-9]
                    )$'\n' =~ $'\n'${device}$'\n' ]]; then
        printf "\n        ALERT:
        The loop device, '%s' is not attached or available.\n
        Please attach this device or adjust your request.
        Exiting...\n" $dev
        exitclean
    fi
    if [[ -z $device || ! -d /sys/block/$device || ! -b /dev/$device ]]; then
        echo -e "\n>>>  Error finding block device of '$dev'.  Aborting!\n"
        exitclean
    fi

    device=/dev/$device
    local d=/dev/${p##*/}
    partnum=${d##$device}
    # Strip off leading p from partnum, e.g., with /dev/mmcblk0p1
    partnum=${partnum##p}
    ! [[ $partnum ]] && partnum=1
    p2=$(get_partition_name $device $((partnum+1)))
    p3=$(get_partition_name $device $((partnum+2)))
}

get_partition_name() {
    # Return an appropriate name for partition $2. Devices that end with a
    # digit need to have a 'p' prepended to the partition number.
    local dev=$1
    local pn=$2

    if [[ $dev =~ .*dm-[0-9]+$ ]]; then
        dev=/dev/mapper/$(< /sys$p/dm/name)
    fi
    if [[ $dev =~ .*[0-9]+$ ]]; then
        echo -n "${dev}p$pn"
    else
        echo -n "${dev}$pn"
    fi
}

partSize() {
    echo $(lsblk -nbdo size $1)
}

resetMBR() {
    udevadm settle
    if [[ $syslinuxboot == missing ]]; then
        printf '\n        NOTICE:
        The Master Boot Record (MBR) will not be reset because
        the SYSLINUX-EXTLINUX boot loader is not installed.\n
        Legacy booting will likely fail.\n
        UEFI booting may succeed, depending on other boot loaders,
        such as GRUB, and the target system firmware.\n'

    # If gpt, we need to use the hybrid MBR.
    elif [[ gpt == $(lsblk -ndro PTTYPE $device) ]]; then
        if [[ -f /usr/lib/syslinux/gptmbr.bin ]]; then
            cat /usr/lib/syslinux/gptmbr.bin > $device
        elif [[ -f /usr/share/syslinux/gptmbr.bin ]]; then
            cat /usr/share/syslinux/gptmbr.bin > $device
        else
            echo 'Could not find gptmbr.bin (SYSLINUX).'
            exitclean
        fi
        if [[ $resetmbr ]]; then
            # Make the partition bootable from BIOS.
            run_parted --script $device set $partnum legacy_boot on
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
    local mbrword=($(hexdump -n 2 <<< \
        "$(dd if=$device bs=2 count=1 &> /dev/null)")) || exit 2
    if [[ ${mbrword[1]} == 0000 ]]; then
        printf '
        The Master Boot Record, MBR, appears to be blank.
        Do you want to replace the MBR on this device?
        Press Enter to continue, or Ctrl C to abort.'
        read
        resetMBR
    fi
    return 0
}

checkPartActive() {
    local dev=$1

    # If we're installing to whole-disk and not a partition, then we
    # don't need to worry about being active.
    if [[ -n $format ]]; then
        return
    fi
    if [[ 0x80 != $(lsblk -nro PARTFLAGS $dev) ]]; then
        printf '\n        NOTICE:
        The partition is not marked bootable.\n
        Attempting to set the boot flag now...\n'
        run_parted --script $device set $partnum boot on
        udevadm settle
        if [[ 0x80 == $(lsblk -nro PARTFLAGS $dev) ]]; then
            printf "\n        Success!  '$dev' is now a bootable partition.\n"
        else
            printf "\n        > Failed. <\n
            Check your device partition scheme.
            You may be able to mark the partition bootable
            with the following commands:\n
            # parted %s
     (parted) toggle %s boot
     (parted) quit\n\n" $device $partnum
            exitclean
        fi
    fi
}

mkfs_config() {
    local fs=$1
    local lbl=$2
    local -n var=$3
    local fn=$4
    local fstype=${var[1]:=ext4}
    local bs=${var[2]}
    local xa=${format[*]:3}
    local sz=$var
    ops=''
    loop=''
    case $fstype in
        fat|vfat|msdos)
            # mkfs.fat silently truncates label to 11 bytes.
            _label="${lbl[*]::11}"
            ops=-v\ -n\ "$_label"
            [[ -n $bs ]] && ops+=' -S '$bs
            [[ -n $fn ]] && ops+=" -C $fn "$((sz/1024))
            if [[ $fs == dev ]]; then
                f=fat32
                [[ $bs != @(''|512) ]] && syslinuxboot=''
            fi
            ;;
        ext4)
            [[ $_64bit ]] && [[ $fs == dev ]] && ops+='-O ^64bit '
            ;&      # Execute the next block without testing its pattern.
        ext[43])
            ops+='-j '
            ;&
        ext2)
            # mkfs.ext[432] maximum label length is 16 bytes.
            _label="${lbl[*]::16}"
            ops+="-F -L $_label"
            [[ -n $bs ]] && ops+=' -vb '$bs
            if [[ -n $fn ]]; then
                falloc $sz "$fn"
                ops+=" -E nodiscard $fn"
            fi
            ;;
        xfs)
            # mkfs.xfs maximum label length is 12 characters.
            _label="${lbl[*]::12}"
            ops="-f -L $_label"
            if [[ -n $bs ]]; then
                ops+=' -b 'size=$bs
                ((bs<1024)) && ops+=' -m 'crc=0
            fi
            if [[ -n $fn ]]; then
                falloc $sz "$fn"
                ops+=" -K -l internal -d file=0,name=$fn"
            fi
            ;;
        btrfs)
            # mkfs.btrfs maximum label length is 255 characters.
            _label="${lbl[*]::255}"
            ops="-f -L $_label"
            # Recommended by Btrfs wiki for out of space problems.
            # https://btrfs.wiki.kernel.org/index.php/FAQ#if_your_device_is_small
            [[ -n $sz ]] && ((sz < 16<<30)) && ops+=\ --mixed
            [[ $fs == @(home|ovl) ]] && [[ -n $bs ]] && ops+=' -n '${bs}k
            if [[ -n $fn ]]; then
                falloc $sz "$fn"
                [[ $fs == ovl ]] && [[ $TGTFS == btrfs ]] && chattr +C "$fn"
                loop=$(losetup -f --show "$fn")
                ops+=' --nodiscard '$loop
            fi
            ;;
        f2fs)
            # mkfs.f2fs maximum label length is 512 unicode characters.
            _label="${lbl[*]::512}"
            ops="-f -l $_label"
            if [[ $xa ]] && local c=($(mkfs.f2fs -V)) &&
                ((${c[2]//-/} < 20200824)); then
                # mkfs.f2fs 1.14.0 (2020-08-24)
                printf "
                NOTICE: The host version of ${c[*]} may not fully support
                        extra_attr or compression.\n
                Press Ctrl C to abort, or Enter to continue...\n\n"
                read
                unset -v xa
            fi
            [[ $xa ]] && ops+=" -O ${xa// /,}"
            [[ $fs == dev ]] && f=''
            if [[ -n $fn ]]; then
                falloc $sz "$fn"
                loop=$(losetup -f --show "$fn")
                ops+=' -t 0 '$loop
            fi
    esac
    [[ $fs != dev ]] && mkfs=mkfs.$fstype || :
}

createFSLayout() {
    local partition_label_type=msdos
    local pt=primary
    local pn=''
    f=$TGTFS
    local boot='set 1 boot on'
    if [[ -z $noesp ]]; then
        # Allow 1 MiB gap.
        ((format-=1<<20))
    else
        boot+=' set 1 esp on'
    fi
    local end=$((oio+format))
    if [[ -n $efi ]]; then
        partition_label_type=gpt
        pt=''
        pn="${label:=LIVE}"
        boot+=' set 1 legacy_boot on'
    fi

    mkfs_config dev "${label:=LIVE}" format
    run_parted --script $device mklabel $partition_label_type
    run_parted --script $device unit B mkpart $pt $pn $f $oio $end $boot
    echo -e '\nWaiting for devices to settle...'
    TGTDEV=$(get_partition_name $device '1')
    udevadm settle -E $TGTDEV
    umount $TGTDEV &> /dev/null || :
    $mkfs $ops $TGTDEV
    echo
    udevadm settle -E /dev/disk/by-label/"$_label"
    label=$(lsblk -ndo LABEL $TGTDEV)

    ((end+=1<<20))
    if [[ -n $l2 ]]; then
        if [[ $partition_label_type == gpt ]]; then
            pn='"EFI System Partition"'
        fi
        boot='set 2 esp on'
        run_parted --script $device unit B mkpart $pt "$pn" fat32 \
                     $end $((end+p2s-(1<<20))) $boot
        echo 'Waiting for devices to settle...'
        p2=$(get_partition_name $device '2')
        udevadm settle -E $p2
        mkfs.fat -v -n ESP $p2
        umount $p2 &> /dev/null || :
        losetup -d $l2
        fsck.fat -avVw $p2
        echo
    fi

    if [[ -n $l3 ]]; then
        [[ $partition_label_type == gpt ]] && pn='"Mac"'
        ((end+=p2s))
        run_parted --script $device unit B mkpart $pt "$pn" hfs+ \
                     $end $((end+p3s))
        p3=$(get_partition_name $device '3')
        mkfs.hfsplus $p3 -v Apple
        f=$(mktemp -d)
        udevadm settle -E $p3
        mount $p3 $f
        d=$(mktemp -d)
        mount -t hfsplus $l3 $d >/dev/null 2>&1
        cp -Trp $d $f
        umount $d $f >/dev/null 2>&1 || :
        losetup -d $l3
        rmdir $f $d
        if ! fsck.hfsplus -yrdfp $p3 ; then
            printf '\n        NOTICE:
            The macboot.img failed the filesystem check after copying.
            Macintosh booting will fail.\n
                    Press Enter to continue, or Ctrl C to abort.'
            unset -v p3
            read
        fi
    fi
}

checkGPT() {

    local partinfo=$(run_parted --script -m $device 'print')
    if ! [[ ${partinfo} =~ :gpt: ]]; then
        printf '\n        ATTENTION:
        EFI booting often requires a GPT partition table on the boot disk.\n
        This can be set up manually, or you can reformat your disk
        by running livecd-iso-to-disk with the --format --efi options.\n
        Sometimes, when EFI components are available in a legacy MBT partition
        with a fat filesystem, booting with the GRUB menu is possible. When
        EFI components are available in the source disk, they will be
        configured and loaded onto the target device. To test if they will work
        without a GPT partition table, remove the --efi option from the
        livecd-iso-to-disk command line, and see if a UEFI menu item
        appears in the BIOS boot menu.'
        exitclean
    fi

    partinfo=${partinfo#*$partnum:}
    if ! [[ $partinfo =~ :boot,\ .*legacy_boot,\ esp\; ]]; then
        printf "\n        ATTENTION:
        The partition isn't marked as an EFI System bootable.\n
        Mark the partition as bootable with the following commands:\n
        # parted %s
 (parted) set %s boot on
 (parted) set %s legacy_boot on
 (parted) set %s esp on
 (parted) quit\n\n" $device $partnum $partnum $partnum
        exitclean
    fi
}

checkFilesystem() {
    local dev=$1
    getdisk $dev

    if [[ $dev == $device ]] && [[ -n $skipcopy ]]; then
        printf "\n        ALERT:
        --skipcopy for the purpose of reconfiguring an existing
        installation should be invoked with a particular
        partition.  Perhaps you want to reconfigure '%s'.\n
        Exiting...\n" $(get_partition_name $device '1')
        exitclean
    fi
    TGTFS=$(blkid -s TYPE -o value $dev || :)
    local t=$(lsblk -ndo TYPE $dev)
    if [[ -n ${format[1]} ]] && [[ -z $skipcopy ]]; then
        if [[ part == $t ]]; then
            if [[ $2 == live ]]; then
                printf "\n        ALERT:
                'live' as target device translates to the '%s' partition on
                this device.  The --format option applies to the whole disk
                and will destroy the currently running disk, '%s'.
                Exiting...\n" $dev $device
                exitclean
            else
                printf "\n        ALERT:
                '%s' is a partition on this device.  The --format option
                applies to the whole disk and will remove all content on the
                device, '%s'.\n
                Please designate a whole device path as your formatting target.
                Exiting...\n" $dev $device
                exitclean
            fi
        fi
        if [[ ${format[1]} == @(fat|vfat|msdos) ]] ; then
            TGTFS=vfat
        else
            TGTFS=${format[1]}
        fi
    elif [[ $t == @(disk|loop|dm) ]]; then
        printf "\n        ALERT:
        '%s' is the %s device but not a partition on this device.
        Please designate the specific partition for loading the image.
        Perhaps you want '%s'.
        Exiting...\n" $dev $t $(get_partition_name $dev '1')
        exitclean
    fi
    if [[ $TGTFS != @(vfat|msdos|ext[432]|btrfs|xfs|f2fs) ]]; then
        printf "\n        ALERT:  '%s' is not a valid filesystem format for the
        target. vfat, ext[432], btrfs, xfs, or f2fs formats are supported.
        Exiting...\n" $TGTFS
        exitclean
    fi
    falloc() {
        # fallocate space $1 for a file $2.
        truncate -s 0 $2
        fallocate -l $1 $2
    }
    case $TGTFS in
        ext[32])
            # fallocate not available in ext[32].
            falloc() {
                truncate -s 0 $2
                dd if=/dev/zero of=$2 bs=1MiB count=$(($1>>20)) status=progress
            }
            ;&
        ext[432]|btrfs|xfs|f2fs)
            CONFIG_FILE=extlinux.conf
            if [[ -n ${format[1]} ]]; then
                # Check extlinux version & set mkfs version for boot partition.
                dev=($(extlinux -v 2>&1))
                t=ext4
                case ${dev[1]} in
                    3.*)
                        t=ext3
                        [[ $TGTFS == ext2 ]] && t=ext2
                        ;;
                    4.[0-9][0-9]|5.00)
                        [[ $TGTFS != xfs ]] && t=$TGTFS
                        ;;
                    5.[0-9][1-9]|[6-9].[0-9][0-9]|extlinux:)
                    # case extlinux: when command not found...
                        t=$TGTFS
                esac
                mkfs=mkfs.$t
            fi
            ;;&
        btrfs)
            #FIXME Compression of $TGTMNT/syslinux interferes with EXTLINUX
            #      booting, but is ok for UEFI grub booting.
            tgtmountopts=''  # '-o compress'
            ;;
        vfat|msdos)
            tgtmountopts='-o shortname=winnt,umask=0077'
            ((homesizeb == 4<<30)) && ((homesizeb-=512))
            ((overlaysizeb == 4<<30)) && ((overlaysizeb-=512))
            ((swapsizeb == 4<<30)) && ((swapsizeb-=512))
            CONFIG_FILE=syslinux.cfg
            mkfs=mkfs.fat
    esac
}

checkMounted() {
    local tgtdev=$1
    local live_mp
    local m
    # Allow --multi installations to live booted devices.
    if [[ -d $SRC ]]; then
        local d="$SRC"
        # Find SRC mount point.
        SRC=$(findmnt -no TARGET -T "$d")
        if ! [[ $d -ef $SRC ]]; then
            srcdir=${d#$SRC/}
        fi
    fi
    if [[ $SRC == @(live|/run/initramfs/live|/mnt/live) ]]; then
        local cmdline=$(< /proc/cmdline)
        local len=${#cmdline}
        local ret=${cmdline#* rd.live.squashimg=}
        if [[ ${#ret} != $len ]]; then
            squashimg=${ret%% *}
        fi
        ret=${cmdline#* @(rd.live.ram|live_ram)}
        if [[ ${#ret} != $len ]]; then
            liveram=liveram
        fi
        ret=${cmdline#* @(rd.writable.fsimg|writable_fsimg)}
        if [[ ${#ret} != $len ]]; then
            SRCIMG=/run/initramfs/fsimg/rootfs.img
            srctype=live
        fi
        ret=${cmdline#* iso-scan/filename=}
        if [[ ${#ret} != $len ]]; then
            m=$(mktemp -d)
            mount $(realpath /run/initramfs/isoscandev) $m
            SRC=$m${ret%% *}
            srctype=live
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
        fi
    fi

    if [[ -b "$SRC" ]]; then
        srcdev=$SRC
    else
        srcdev=$(findmnt -no SOURCE -T "$SRC") || :
    fi
    for live_mp in /run/initramfs/live /mnt/live ; do
        if mountpoint -q $live_mp; then
            local livedev=$(findmnt -no SOURCE $live_mp)
            local livedir=$(losetup -nO BACK-FILE /dev/loop0)
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
    elif [[ $livedev =~ $TGTDEV && -n ${format[1]} ]]; then
        printf "\n    NOTICE:
        You have requested --format of the currently booted LiveOS disk,
            '%s'\n
        Exiting...\n\n" $TGTDEV
        exitclean
    elif [[ $srcdev =~ $TGTDEV  && -n ${format[1]} ]]; then
        printf "\n    NOTICE:
        You have requested --format of the LiveOS source disk,
            '%s'\n
        Exiting...\n\n" $TGTDEV
        exitclean
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
        if [[ -z ${format[1]} ]]; then
            live_mp=''
            for d in ${tgtdev}*; do
                local mountpoint=($(findmnt -nro TARGET $d || :))
                for m in "${mountpoint[@]}"; do
                    if [[ -n $m ]]; then
                        printf "\n   NOTICE:  '%s' is mounted at '%s'." $d "$m"
                        live_mp=$m
                    fi
                done
            done
            if [[ -n $live_mp ]]; then
                printf '\n            Please unmount for safety.\n
                Exiting...\n\n'
                exitclean
            fi
        fi
        if [[ $p == /devices/virtual/block/loop* ]] &&
           [[ 1 == $(lsblk -rno RO $tgtdev) ]]; then
            printf "\n   NOTICE: '%s' is attached READ-ONLY.
            The target device must be writable.
            Please adjust this.
            Exiting...\n\n" $tgtdev
            exitclean
        elif [[ $p == /devices/virtual/block/dm-* ]] &&
             [[ 1 == $(< /sys$p/dm/suspended) ]]; then
            printf "\n   NOTICE: '%s' is suspended.
            Please adjust this.
            Exiting...\n\n" $tgtdev
            exitclean
        elif [[ $(swapon -s) =~ ${tgtdev} ]]; then
            printf "\n   NOTICE:   Your chosen target device, '%s',\n
            is in use as a swap device.  Please disable swap if you want
            to use this device.        Exiting..." $tgtdev
            exitclean
        fi
    fi
}

detectsrctype() {
    local f
    if [[ -e $SRCMNT/Packages ]]; then
        echo "/Packages found, will copy source packages to target."
        packages=packages
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
    SRCFS=$(findmnt -no FSTYPE $SRCMNT)
    # netinstall iso has no SRCIMG.
    if [[ -n "$SRCIMG" ]]; then
        IMGMNT=$(mktemp -d /run/imgtmp.XXXXXX)
        mount -r "$SRCIMG" $IMGMNT || exitclean
        if [[ -d $IMGMNT/proc ]]; then
            flat_squashfs=flat_squashfs
            RFSIMG="$SRCIMG"
        else
            for f in $IMGMNT/LiveOS/rootfs.img $IMGMNT/LiveOS/ext3fs.img; do
                [[ -s $f ]] && RFSIMG=$f && break
            done
            mount -r $RFSIMG $IMGMNT || exitclean
        fi
        # list file as deleted module directory may have remnant files.
        kver=($(ls -vr $IMGMNT/usr/lib/modules/*/vmlinuz))
        kver=(${kver[@]%/*}); kver=(${kver[@]##*/})
        if [[ $TGTFS == ext4 ]]; then
            f=$(which syslinux)
            f="$(sed -nr '0,/SYSLINUX (\S+) .*/ s//\1/ p' $f)"$'\n'6.04
            [[ $f == $(sort -rV <<< "$f") ]] || _64bit=_64bit
        fi
        umount -l $IMGMNT $IMGMNT 2>/dev/null || :
    fi
    [[ -n $srctype ]] && return

    if [[ -e $SRCMNT$IMGMNT/images/install.img ]] ||
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
    udevadm settle
    local label=($(lsblk -no LABEL $1 || :))
    # Use compound array assignment to accommodate multiple partitions if
    # a parent device is passed, such as for a loop device.
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

if type gio >/dev/null 2>&1; then
    copyFile='gio copy -p'
elif type rsync >/dev/null 2>&1; then
    copyFile='rsync --inplace --8-bit-output --progress'
elif type strace >/dev/null 2>&1 && type awk >/dev/null 2>&1; then
    copyFile='cp_p'
else
    copyFile='cp'
fi

set -eE
set -o pipefail
set -o braceexpand
trap exitclean EXIT
shopt -s extglob

cryptedhome=cryptedhome
keephome=keephome
homesizeb=''
copyhome=''
copyhomesize=''
swapsizeb=''
overlay=''
overlayfs=''
overlaysizeb=''
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
SRCwasMounted=''
syslinuxboot=syslinux

while true ; do
    case $1 in
        --help | -h | -?)
            usage
            ;;
        --noverify)
            noverify=noverify
            ;;
        --format)
            declare -a 'format=({'"$2"'})'
            i=${#format[@]}
            case $format in
                {*)
                    format=${format//[{\}]/}
                    ;;&
                {[[:digit:]]*)
                    i=0
            esac
            case $i in
                1)
                    format=('' $format)
                    i=2
                    case ${format[1]} in
                        --msdos)
                            format[1]=msdos
                            ;;
                        --*)          # next option (implicit size and type)
                            format[1]=ext4
                            i=1
                    esac
                    checkfstype ${format[1]} dev
                    shift $i
                    continue
                    ;;
                [2-9])
                    [[ $format == [[:alpha:]]* ]] && format=('' ${format[@]})
            esac
            checkfstype ${format[1]:=ext4} dev
            if [[ -n $format ]]; then
                checkinput $format format
                ((format<<=20))
            fi
            [[ -n ${format[2]} ]] &&
                checkinput ${format[2]} blocksize ${format[1]} dev
            shift
            ;;
        --msdos)
            format[1]=msdos
            ;;
        --reset-mbr|--resetmbr)
            resetmbr=resetmbr
            ;;
        --efi|--mactel)
            efi=efi
            ;;
        --noesp)
            noesp=noesp
            ;;
        --nomac)
            nomac=nomac
            ;;
        --skipcopy|--reconfig)
            skipcopy=skipcopy
            ;;
        --force)
            force=force
            keephome=''
            ;;
        --xo)
            xo=xo
            skipcompress=skipcompress
            ;;
        --xo-no-home)
            xonohome=xonohome
            ;;
        --timeout)
            checkinput $2 timeout
            timeout=$2
            shift
            ;;
        --totaltimeout)
            checkinput $2 totaltimeout
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
            declare -a 'overlaysizeb=({'"$2"'})'
            overlaysizeb=${overlaysizeb//[{\}]/}
            checkinput $overlaysizeb ovl
            ((overlaysizeb<<=20))
            [[ -n ${overlaysizeb[1]} ]] && checkfstype ${overlaysizeb[1]} ovl
            [[ -n ${overlaysizeb[2]} ]] &&
                checkinput ${overlaysizeb[2]} blocksize ${overlaysizeb[1]} ovl
            shift
            ;;
        --copy-overlay)
            copyoverlay=copyoverlay
            ;;
        --reset-overlay)
            resetoverlay=resetoverlay
            ;;
        --home-size-mb)
            declare -a 'homesizeb=({'"$2"'})'
            homesizeb=${homesizeb//[{\}]/}
            checkinput $homesizeb home
            ((homesizeb<<=20))
            [[ -n ${homesizeb[1]} ]] && checkfstype ${homesizeb[1]} home
            [[ -n ${homesizeb[2]} ]] &&
                checkinput ${homesizeb[2]} blocksize ${homesizeb[1]} home
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
            swapsizeb=$2
            checkinput $swapsizeb swap
            ((swapsizeb<<=20))
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
    esac
    shift
done

if [[ $# -ne 2 ]]; then
    shortusage
    echo '
    ERROR:  At minimum, a source and a target must be specified.'
    exit 1
fi

if [[ ${format[1]} == @(ext[432]|btrfs|xfs) ]] &&
    ! type extlinux >/dev/null 2>&1; then
    printf "
    NOTICE:  The EXTLINUX boot loader is not installed on the host computer.
    Legacy booting of the '%s' root filesystem may not be available.\n
    UEFI booting by GRUB or another boot loader may be available
    depending on target systems & firmware.\n
    EXTLINUX may be installed by running the command:\n
        sudo dnf install syslinux-extlinux\n
    Press Enter to continue, or Ctrl C to abort.\n\n" ${format[1]}
fi

if [[ $1 == live ]]; then
    SRC=live
else
    SRC=$(readlink -f "$1") || :
fi
if [[ $2 == live ]]; then
    TGTDEV=$(realpath $(readlink /run/initramfs/livedev)) || (printf "
    ERROR:  There is no running LiveOS system to target.\n\n" && exitclean)
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
echo -e "\nSource image is '$SRC'"

# Do some basic sanity checks.
checkForSyslinux
checkFilesystem $TGTDEV $2
checkMounted $TGTDEV

if [[ $LIVEOS =~ [[:space:]]|/ ]]; then
    printf "\n    ALERT:
    The LiveOS directory name, '%s', contains spaces, newlines, tabs, or '/'.\n
    Whitespace and '/' do not work with the SYSLINUX boot loader.
    Replacing the whitespace by underscores, any '/' by '-':  " "$LIVEOS"
    LIVEOS=${LIVEOS//[[:space:]]/_}
    LIVEOS=${LIVEOS////-}
    printf "'$LIVEOS'\n\n"
fi

[[ $overlayfs == overlayfs ]] && overlayfs=$TGTFS

f() {
    # format parameter string
    f="$((${overlaysizeb[0]}>>20)) ${overlaysizeb[1]} ${overlaysizeb[2]}"
    f=${f// /,}; f=${f%%+(,)}
    echo $f
}

case $overlayfs in
    vfat|msdos)
        [[ -z $overlaysizeb ]] && {
        printf '\n        ALERT:
        If the target filesystem is formatted as vfat or msdos, you must
        specify an --overlay-size-mb <size> value for an embedded overlayfs.\n
        Exiting...\n'
        exitclean; }
        ;;
    temp)
        [[ -n $overlaysizeb ]] && {
        printf '\n        ERROR:
        You have specified --overlayfs temp AND --overlay-size-mb %s.\n
        --overlay-size-mb is only appropriate for persistent overlays on
        vfat formatted partitions.\n
        Please request only one of these options.  Exiting...
        \n' $(f)
        exitclean; }
        ;;
    !(''))
        if [[ -n $overlaysizeb ]]; then
            printf '\n    Notice:
            An OverlayFS overlay within an %s-formatted partition
            will use a union mount directory and does not need a
            separate --overlay-size-mb persistent overlay file.
            The option \033[1m--overlay-size-mb %s\033[0m will be ignored.
            \n\r' $TGTFS $(f)
            unset -v overlaysizeb
        fi
esac

[[ -z $label ]] && label=$(get_label $TGTDEV)

case ${#overlaysizeb[@]} in
0)
    [[ $overlayfs == @(vfat|msdos) ]] && {
        printf '\n        ALERT:
        If the target filesystem is formatted as vfat or msdos, you must
        specify an --overlay-size-mb <size> value for an embedded overlayfs.\n
        Exiting...\n'
        exitclean; }
    ;;
*)
    if [[ $TGTFS == @(vfat|msdos) ]] && ((overlaysizeb >= 4<<30)); then
        printf '\n        ALERT:
        An overlay size greater than 4096 MiB
        is not allowed on VFAT formatted filesystems.\n'
        exitclean
    fi
    if [[ -z ${format[1]} ]] && [[ $label =~ [[:space:]] ]]; then
        printf '\n        ALERT:
        The LABEL (%s) on %s has spaces, newlines, or tabs in it.
        Whitespace does not work with the overlay.
        An attempt to rename the device will be made.\n\n' "$label" $TGTDEV
        label=${label//[[:space:]]/_}
    fi
    [[ $overlaysizeb ]] && [[ $overlay == none ]] && {
        printf '\n        ERROR:
            You have specified --no-overlay AND --overlay-size-mb <size>.\n
            Only one of these options may be requested at a time.\n
            Please request only one of these options.  Exiting...\n'
        exitclean; }
    ;;&
[2-9])
    [[ -z $overlayfs ]] &&
        printf '\n    Notice:
        A Device-mapper overlay file does not need an embedded filesystem.
        Only the size option in \033[1m--overlay-size-mb %s\033[0m is
        relevant.\n' $(f)
esac

if [[ -n $homesizeb ]] && [[ $TGTFS == @(vfat|msdos) ]]; then
    if ((homesizeb >= 4<<30)); then
        printf '\n      NOTICE:
        A file on a FAT filesystem cannot be larger than 4096 MiB.\n\n'
        exitclean
    fi
fi

if [[ -n $swapsizeb ]] && [[ $TGTFS == @(vfat|msdos) ]]; then
    if ((swapsizeb >= 4<<30)); then
        echo "Can't have a swap file greater than 4096 MB on VFAT"
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
    d=($(losetup -nO NAME -j $SRC))
    # ^ Use compound array assignment to accommodate multiple attachments.
    if [[ -n $d ]]; then
        SRCwasMounted=($(lsblk -nro MOUNTPOINT $d))
        [[ -z $SRCwasMounted ]] && SRC=$d
    else
        srcmountopts+=,loop
    fi
elif [[ -d $SRC ]]; then
    srcmountopts+=\ --bind
elif ! [[ -b $SRC ]]; then
    if [[ $1 == live ]]; then
        msg='The source is not a LiveOS booted image.'
    else
        msg="'$1' is not a file, block device, or directory.\n"
    fi
    printf "\n    ATTENTION:
        $msg\n        Exiting...\n\n"
    exitclean
elif [[ -b $SRC ]] && [[ $(lsblk -ndo TYPE $SRC) == part ]]; then
    SRCwasMounted=$(lsblk -nro MOUNTPOINT $SRC)
    [[ $SRC -ef $TGTDEV ]] && srcmountopts=''
else
    printf "\n    ATTENTION:
    '%s' is not a block device partition.
    Perhaps you want partition '%s'.\n\n" $SRC $(get_partition_name $SRC '1')
    exitclean
fi

if [[ -n $SRCwasMounted ]]; then
    rmdir $SRCMNT
    SRCMNT=$SRCwasMounted
else
    mount $srcmountopts "$SRC" $SRCMNT || exitclean
fi
trap exitclean SIGINT SIGTERM

# Figure out what needs to be done based on the source image.
detectsrctype

if [[ -n $flat_squashfs ]]; then
    if [[ -z $overlayfs ]]; then
        if [[ $TGTFS == @(vfat|msdos) ]] && [[ -z $overlaysizeb ]]; then
            printf  "\n        ALERT:
            The source has a flat SquashFS structure that requires an OverlayFS
            overlay specified by the --overlayfs option.\n
            Because the target device filesystem has a '"$TGTFS"' format, you
            must specify an --overlay-size-mb <size> value for an embedded
            OverlayFS.\n
            Exiting...\n\n"
            exitclean
        elif [[ -z $overlaysizeb ]]; then
            overlayfs=temp
        else
            overlayfs=$TGTFS
        fi
    elif [[ -n $overlaysizeb ]] && [[ $TGTFS != @(vfat|msdos) ]]; then
        printf  "\n        Notice:
        The source has a flat SquashFS structure that requires an OverlayFS
        overlay.\n
        Because the target device filesystem has an '"$TGTFS"' format, you need
        NOT specify an --overlay-size-mb <size> value to hold an embedded
        OverlayFS.\n
            That option will be ignored...\n\n"
        unset -v overlaysizeb
    fi
fi

if [[ $srctype != live ]]; then
    if [[ -n $homesizeb ]]; then
        printf '\n        ALERT:
        The source is not for a live installation. A home.img filesystem is not
        useful for netinst or installer installations.\n
        Please adjust your home.img options.  Exiting...\n\n'
        exitclean
    elif [[ -n $overlaysizeb ]]; then
        printf '\n        ALERT:
        The source is not for a live installation. A overlay file is not
        useful for netinst or installer installations.\n
        Please adjust your script options.  Exiting...\n\n'
        exitclean
    fi
fi

if [[ -n $copyoverlay ]]; then
    SRCOVL=($(find $SRCMNT/$srcdir/ -name overlay-* -print || :))
    if [[ ! -s $SRCOVL ]]; then
        printf '\n   NOTICE:
        There appears to be no persistent overlay on this image.
        Would you LIKE to continue with NO persistent overlay?\n\n
        Press Enter to continue, or Ctrl C to abort.\n\n'
        read
        copyoverlay=''
    fi
fi
if [[ -n $copyoverlay && -n $overlaysizeb ]]; then
    printf '\n        ERROR:
        You requested a new overlay AND to copy one from the source.\n
        Please request only one of these options.  Exiting...\n'
    exitclean
fi

efibootdir() {
    declare -n v
    v=$2
    v=/EFI/BOOT
    if [[ -d $1/EFI ]]; then
        local d=$(ls -d $1/EFI/*/)
        # This test is case sensitive in Bash on vfat filesystems.
        [[ $d =~ EFI/boot/ ]] && v=/EFI/boot || :
    fi
}

TGTMNT=$(mktemp -d /run/tgttmp.XXXXXX)
if ! [[ ${format[1]} ]]; then
    if [[ $TGTFS == f2fs ]]; then
        ! [[ $(dump.f2fs $TGTDEV) =~ extra_attr ]] || xa=force
    elif ! findmnt -no SOURCE $TGTDEV >/dev/null 2>&1; then
        fscheck $TGTFS $TGTDEV
    fi

    mount $tgtmountopts $TGTDEV $TGTMNT || exitclean

    efibootdir $TGTMNT T_EFI_BOOT

    [[ $TGTFS == f2fs ]] &&
        ! b=$(grep "a F2FS filesystem" $TGTMNT$T_EFI_BOOT/grubx64.efi \
                                       $TGTMNT$T_EFI_BOOT/BOOTX64.EFI 2>&1)
fi

efibootdir $SRCMNT EFI_BOOT

if [[ -n $efi && -z $EFI_BOOT ]]; then
    printf '\n        ATTENTION:
    You requested EFI booting, but this source image lacks support
    for EFI booting.  Exiting...\n'
    exitclean
elif [[ $TGTFS == f2fs ]] && [[ $xa != force ]] && xa=${format[*]:3} &&
    ! [[ $xa =~ extra_attr ]] && xa='' && ! [[ $xa ]] && ! [[ $b ]] &&
    ! b=$(grep "a F2FS filesystem" $SRCMNT$EFI_BOOT/grubx64.efi \
                                   $SRCMNT$EFI_BOOT/BOOTX64.EFI 2>&1) &&
    ! [[ -d /usr/lib/grub/x86_64-efi ]]; then
        printf '
        NOTICE:  The source GRUB EFI binary does not contain the F2FS module.
        grub2-efi-x64-modules must be installed in the host operating system
        in order to create a GRUB EFI binary with F2FS filesystem support on
        x86_64 architecture systems.\n
        Run the command "sudo dnf install grub2-efi-x64-modules".\n
        Press Ctrl C to abort,\n
        or press '\''Enter'\'' to continue, '
        # Trigger building an EFI Boot Stub instead.
        xa=nof2fs.mod
        if type objcopy >/dev/null 2>&1; then
            printf 'and an EFI Boot Stub loader will be built
            instead.\n\n'
        else
            nouefi=nouefi
            printf 'and space will be provided for
                         subsequent installation of a boot loader.\n\n'
        fi
        read
fi

if [[ -d $SRCMNT/isolinux/ ]]; then
    CONFIG_SRC=$SRCMNT/isolinux
# Adjust syslinux sources for replication of installed images
# between filesystem types.
elif [[ -d $SRCMNT/syslinux/ ]]; then
    [[ -d $SRCMNT/$srcdir/syslinux ]] && CONFIG_SRC="$srcdir"/
    CONFIG_SRC="$SRCMNT/${CONFIG_SRC}syslinux"
fi
i=${CONFIG_SRC}/initrd*.img
cd /tmp
rm -rf usr
ikernel=$(lsinitrd $i --unpack -f usr/lib/modules/*/kernel -v 2>&1)
ikernel=${ikernel%/*}; ikernel=${ikernel##*/}
rm -rf usr
cd - >/dev/null 2>&1
f=$(file ${CONFIG_SRC}/vmlinuz*)
f=${f#*version }; f=${f%% *}
a=''; d=''
if ! [[ "${kver[*]}" =~ $f ]]; then
    k="${kver[*]}"; k="${k// /$'\n'}"
    a="* is not among those installed in the base root filesystem:
$k"
fi
[[ $ikernel != $kver ]] &&
    d="* does not match that in the initial ram filesystem, '${ikernel}'"
if [[ $a || $d ]]; then
    printf "\n  NOTICE:  The boot kernel version, '%s',
    %s
    %s

    The kernel may have been upgraded and reside in an overlay.

    If the boot kernel version is not available in the root filesystem
    or match the initial ram filesystem version, the booted operating system
    will most likely fail.\n
    Press Ctrl C to abort, or, if this is expected,
                               press 'Enter' to continue.\n" $f "$a" "$d"
    read
fi

if [[ -n $overlayfs && -z $(lsinitrd $i\
    -f usr/lib/dracut/hooks/cmdline/30-parse-dmsquash-live.sh | \
    sed -n -r '/(dev\/root|rootfsbase)/p') ]]; then
    printf "\n    NOTICE:
    The --overlayfs option requires an initial boot image based on
    dracut version 045 or greater to use the OverlayFS feature.\n
    Lacking this, the device boots with a temporary Device-mapper overlay.\n
    Also, be sure that initrd.img contains the dracut module 'dmsquash-live'.\n
    Press Enter to continue, or Ctrl C to abort.\n"
    read
fi

to_be_added () {
# Determine file space to be added while loading this image configuration.

# var=($(du -b path)) uses the compound array assignment operator to extract
# the numeric result of du into the index zero position of var.  The index zero
# value is the default operative value for the array variable when no other
# indices are specified.
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
            livesize=($(du -b "$SRCIMG"))
            umount -l $SRCMNT
        else
            echo "WARNING: --skipcompress or --xo was specified but the
            currently-running kernel can not mount the SquashFS from the source
            file to extract it. Instead, the compressed SquashFS will be copied
            to the target device."
            skipcompress=""
        fi
    else
        livesize=($(du -b "$SRCIMG"))
    fi
    if ((livesize >= 4<<30)) &&  [[ $TGTFS == @(vfat|msdos) ]]; then
        echo "
        An image size greater than 4096 MiB is not suitable for a 
        VFAT-formatted partition.
        "
        if [[ -n $skipcompress ]]; then
            echo " The compressed SquashFS will instead be copied
            to the target device."
            skipcompress=''
            livesize=($(du -b "$SRCMNT/$srcdir/$squashimg"))
            SRCIMG="$SRCMNT/$srcdir/$squashimg"
        else
            echo "Exiting..."
            exitclean
        fi
    fi
    local sources
    if [[ -d $SRCMNT/$srcdir/syslinux ]]; then
        sources+=" $SRCMNT/$srcdir/syslinux $SRCMNT/$srcdir/images"
    else
        sources+=" $SRCMNT/isolinux $SRCMNT/syslinux $SRCMNT/images"
    fi
    [[ -n $EFI_BOOT ]] && sources+=" $SRCMNT$EFI_BOOT"
    duTable=($(du -c -b "$0" $sources 2> /dev/null || :))
    livesize=$((livesize + ${duTable[*]: -2:1}))
    [[ -s $SRCHOME  && -n $copyhome ]] && copyhomesize=($(du -s -b $SRCHOME))
    if [[ -s $SRCOVL && -n $copyoverlay ]]; then
        copyoverlaysize=($(du -c -b "$SRCOVL"))
        copyoverlaysize=${copyoverlaysize[*]: -2:1}
    fi
    tba=$((overlaysizeb + copyoverlaysize + homesizeb + copyhomesize +
            livesize + swapsizeb))
}

to_be_added

MiB () {
    # Round value to nearest 1 MiB.
    echo $((($1+(1<<19))>>20))
}

checkDiskSpace () {
    if [[ -n ${format[1]} ]]; then
        # f2fs has greater relative overhead at smaller sizes.
        ((m == 4)) && ((format < 2300<<20)) && m=3
        # Filesystem metadata allowance
        local m=$((format>>m))
        i=$((tba+m))
        if ((free < 0 )); then
            printf '\n  ALERT:
            The requested primary partition size, %s MiB, is %s MiB larger than
            the available free space on this device.\n' $(MiB format) $(MiB -free)
            d=$((p2s+p3s))
            ((d+free > 0)) && d="
                The --noesp option will avoid the $(MiB d) MiB needed for the
                EFI System Partition and Apple HFS+ partition.\n" && printf "$d"
            printf "\n          Please adjust your request.\n"
        fi
        if ((format < i )); then
            printf '\n  ALERT:
            The requested primary partition size, %s MiB, is %s MiB smaller
            than the %s MiB installation space estimated for this image.\n
            Please adjust your request.\n' $(MiB format) $(MiB i-format) $(MiB i)
        fi
        i=$format
        available=$((format-tba-m))
        if ((free < 0)); then
            available=$free
        fi
        ((tba+=m+p2s+p3s+oio+z))
        tbd=0
    else
        free=$((available+tbd))
        ((available-=tba-tbd)) || :
    fi
    if ((available < 100<<20)) || ((free < 0)); then
        local s t u
        if ((available < 0)); then
            s='may NOT fit in the space available on the target device.'
            t='fit the install and about 100  MiB
  of available space on the primary partition,'
            u='   Approximate needed'
        else
            s='leave less than 100 MiB of available space on the primary partition.'
            t='leave about 100 MiB of available space on the primary partition,'
            u='Approximate available'
        fi
        printf "\n  The live image + overlay, home, & swap space, if requested,
        \r  %s\n\n" "$s"
        [[ -n ${format[1]} ]] &&
            printf "    Total disk space: %12s  MiB\n" $(MiB f) &&
            printf "  + Allocated space: %13s  MiB\n" $(MiB i) ||
            printf "    Available space: %13s  MiB\n" $(MiB free)
        if [[ ${format[1]} ]]; then
            ((format != free)) &&
            printf "    Unallocated free space:  %5s\n" $(MiB $((free+z)))
        else
            printf "    Free space shortage: %9s\n" $(MiB available)
        fi
        printf "    ==============================\n"
        printf "\r    Size of live image: %10s  MiB\n" $(MiB livesize)
        [[ -n $overlaysizeb ]] &&
            printf "    Overlay size: %16s\n" $(MiB overlaysizeb)
        [[ -n $ovlsize ]] &&
            printf "    Overlay size: %16s\n" $(MiB ovlsize)
        [[ -n $copyoverlaysize ]] &&
            printf "    Copy overlay size: %11s\n" $(MiB copyoverlaysize)
        ((homesizeb > 0)) &&
            printf "    Home filesystem size: %8s\n" $(MiB homesizeb)
        [[ -n $copyhomesize ]] &&
            printf '    Copy home filesystem size: %3s\n' $(MiB copyhomesize)
        [[ -n $swapsizeb ]] &&
            printf "    Swap file size: %14s\n" $(MiB swapsizeb)
        if [[ -n ${format[1]} ]]; then
            printf "    Metadata allowance: %10s\n" $(MiB m)
            printf "    ==============================
            \r    Primary Partition used: %6s\n" $(MiB $((format-available)))
            printf "     %s:  %5s  MiB\n\n" "$u" $(MiB available)
            [[ -n $p2s ]] &&
            printf "    EFI System Partition: %8s\n" $(MiB p2s)
            [[ -n $p3s ]] &&
            printf "    Apple HFS+ Partition: %8s\n" $(MiB p3s)
            printf "    Storage alignment gaps: %6s\n" $(MiB $((oio+z)))
        fi
        printf "    ==============================\n"
        printf "  - Total required space:  %7s  MiB\n\n" $(MiB tba)
        printf "    ==============================\n"
        printf "\n  To %s
        \r  free space on the target, or adjust the
        \r  requested size total by:  %6s  MiB\n\n" "$t" $(MiB $((available-(100<<20))))
        IFS=: read -n 1 -p "
  ATTENTION:
      Press Ctrl C to Exit.  ...To Continue anyway, press Enter.
" s
        if [[ $s != '' ]]; then
            losetup -d $l2 $l3 &> /dev/null || :
            exitclean
        fi
    fi
}

# Format the device
if [[ -n ${format[1]} && -z $skipcopy ]]; then
    free=$(partSize $device)
    f=$free
    oio=$(lsblk -nrdo OPT-IO $device)
    ((oio <= 512)) && ((oio=4<<20))
    z=$((free%oio))
    # Assure at least 2 MiB free space at the end of the disk.
    ((z < 2<<20)) && ((z+=oio))
    if [[ -z $noesp ]]; then
        l2=$SRCMNT/images/efiboot.img
        # Another possible path for the image.
        ! [[ -f $l2 ]] && l2=$SRCMNT/isolinux/efiboot.img
        if [[ -f $l2 ]]; then
            l2=$(losetup --show -fr $l2)
            p2s=$(partSize $l2)
            if [[ $TGTFS == f2fs ]] && [[ $xa ]]; then
                # When extra_attr or compression is requested for F2FS, or a
                # GRUB EFI binary with the f2fs module is unavailable or cannot
                # be produced, allow space for a UEFI executable, which can be
                # produced by dracut --uefi, for use as an EFI Boot Stub.
                # Allow 128 MiB per 15 GB of device_size for multi boot stubs.
                ((free < 30*10**9)) && ((p2s+=1<<27)) ||
                    ((p2s+=free/(15*10**9)<<27))
            fi
            # Guarantee that there is at least 1 MiB of extra space for a gap.
            ((oio-p2s%oio < 1<<20)) && ((p2s+=1<<20))
            # Set partition size to whole 4-MiB or OPT-IO units.
            ((p2s=(p2s/oio+1)*oio))
        fi
        if [[ -z $nomac ]]; then
            l3=$SRCMNT/images/macboot.img
            ! [[ -f $l3 ]] && l3=$SRCMNT/isolinux/macboot.img
            if [[ -f $l3 ]]; then
                l3=$(losetup --show -fr $l3)
                ((p3s=($(partSize $l3)/oio+1)*oio))
            fi
        fi
    fi
    ((free-=oio+z+p2s+p3s))
    if [[ -z $format ]]; then
        # unspecified partition size case
        format=$free
    else
        ((free-=format)) || :
    fi
    # Reduce to OPT-IO units.
    ((format/=oio,format*=oio))
    checkDiskSpace
    printf '\n    WARNING: The requested formatting will DESTROY ALL DATA
             on: %s !!\n
      Press Enter to continue, or Ctrl C to abort.\n' $device
    read
    umount ${device}* &> /dev/null || :
    wipefs -af ${device} &> /dev/null

    createFSLayout $device
    resetMBR
fi

if [[ -n $efi ]] || [[ gpt == $(lsblk -ndro PTTYPE $TGTDEV) ]]; then
    checkGPT
else
# Because we can't set boot flag for EFI Protective on msdos partition tables.
    checkPartActive $TGTDEV
fi

[[ $resetmbr ]] && resetMBR

checkMBR

fs_label_msg() {
    case $TGTFS in
        vfat|msdos)
            printf '
            A label can be set with the fatlabel command.'
            ;;
        ext[432])
            printf '
            A label can be set with the e2label command.'
            ;;
        btrfs)
            printf '
            A label can be set with the btrfs filesystem label command.'
            ;;
        xfs)
            printf '
            A label can be set with the xfs_admin -L command.'
            ;;
        f2fs)
            printf '
            NOTE:  F2FS labels are set at creation time.'
    esac
    exitclean
}

labelTargetDevice() {
    local dev=$1
    TGTLABEL=$(get_label $dev)
    TGTLABEL=${TGTLABEL//[[:space:]]/_}
    [[ -z $TGTLABEL && -z $label ]] && label=LIVE
    if [[ -n $label && $TGTLABEL != "$label" ]]; then
        case $TGTFS in
            vfat|msdos)
                fatlabel $dev "$label"
                ;;
            ext[432])
                e2label $dev "$label"
                ;;
            btrfs)
                btrfs filesystem label $dev "$label"
                ;;
            xfs)
                xfs_admin -L "$label" $dev
                ;;
            f2fs)
                printf '
                ALERT:  F2FS labels are set at creation time.\n'
                ;;
            * )
                printf "
                ALERT:  Unknown filesystem type.
                Try setting its label to '$label' and re-running.\n"
                exitclean
        esac
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
    # Escape any special characters \/;& for sed replacement strings.
    TGTLABEL="LABEL=$(sed 's/[\/;&]/\\&/g' <<< $TGTLABEL)"
else
    printf '\n    ALERT:
    You need to have a filesystem label or
    UUID for your target device.\n'
    fs_label_msg
fi
OVLNAME="overlay-$label-$TGTUUID"

if [[ ${format[1]} ]]; then
    mount $tgtmountopts $TGTDEV $TGTMNT || exitclean
    T_EFI_BOOT=$EFI_BOOT
fi
# Use compound array assignment in case there are multiple files.
BOOTCONFIG_EFI=($(nocase_path "$TGTMNT$T_EFI_BOOT/boot*.conf"))

# Detect any pre-existing, subsequent or non-default installation directories.
multidirs=($(ls -1d $TGTMNT/*/syslinux 2>/dev/null || :))
if [[ -n $multidirs ]]; then
    multidirs=(${multidirs[@]%/syslinux})
    multidirs=(${multidirs[@]##*/})
fi

# Identify the initial installation directory name.
[[ -f $TGTMNT/syslinux/$CONFIG_FILE ]] &&
_1stindir=$(sed -n -r '/^\s*label\s+linux/I {n;n;n
                       s/^\s*append\s+.*rd\.live\.dir=(\S+)( .*|$)/\1/Ip}
                      ' $TGTMNT/syslinux/$CONFIG_FILE)
[[ -z $_1stindir ]] && _1stindir=LiveOS
# Special case for the reconfiguration of a non-default initial installation
# directory.
[[ -n $skipcopy && $LIVEOS == LiveOS ]] && LIVEOS=$_1stindir

# $multi signals the current installation directory as a subsequent one.
if [[ -n $multi ]]; then
    if ! [[ -e $TGTMNT/syslinux ]]; then
        unset -v multi
    elif [[ $LIVEOS == $_1stindir ]] && [[ -z $force ]]; then
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
    multi=$LIVEOS
fi

if [[ -e $TGTMNT/syslinux ]] && [[ -z $skipcopy ]] &&
   [[ -z $multi && -z $force ]]; then
    if [[ $srctype == @(netinst|installer) ]]; then
        d='the /images & boot configuration
                directories'
    else
        d="any image in the '$LIVEOS'
                directory"
    fi
    IFS=: read -n 1 -p "
    ATTENTION:

        >> There may be other LiveOS images on this device. <<

    Do you want a new Multi Live Image installation?

        If so, press 'Enter' to continue.

        Or, press the [space bar], and $d will be overwritten,
                and any others ignored.

    To abort the installation, press Ctrl C.
    " multi
    if [[ $multi != ' ' ]]; then
        if [[ $LIVEOS == $_1stindir ]] || [[ ${multidirs[@]} =~ $LIVEOS ]]; then
            LIVEOS=$(mktemp -d $TGTMNT/XXXX)
            rmdir $LIVEOS
            LIVEOS=${LIVEOS##*/}
        fi
        multi=$LIVEOS
    elif [[ -z $multidirs ]] && [[ $_1stindir == $LIVEOS ]]; then
        unset -v multi
    else
        multi=$LIVEOS
    fi
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
elif [[ ! -d $TGTMNT/syslinux ]] ||
    # Case of reconfiguring a nondefault --livedir initial installation.
    [[ -d $TGTMNT/$LIVEOS && ! -d $TGTMNT/$LIVEOS/syslinux ]]; then
    SYSLINUXPATH=syslinux
else
    SYSLINUXPATH=$LIVEOS/syslinux
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
    if [[ -n $overlaysizeb && -z $skipcopy ]]; then
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
if [[ -z $skipcopy && -f $HOMEPATH && -n $keephome && -n $homesizeb ]]; then
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
if [[ -s $SRCHOME && -n $copyhome && -n $homesizeb ]]; then
    printf '\n        ERROR:
        You requested a new home AND to copy one from the source.\n
        Please request only one of these options.  Exiting...\n'
    exitclean
fi
if [[ ! -s $SRCHOME && -n $copyhome ]] &&
    [[ -n $overlaysizeb || -n $resetoverlay || -n $copyoverlay ]]; then
    printf '\n        NOTICE:
        There appears to be no persistent home.img on this source.\n
        Would you LIKE to continue with just the persistent overlay?\n
        Press Enter to continue, or Ctrl C to abort.\n'
    read
    copyhome=''
fi

thisScriptpath=$(readlink -f "$0")

to_be_deleted() {
# Determine the file space to be deleted from the target device.

    if [[ -d $TGTMNT/$LIVEOS && -z $format ]]; then
        # du -c reports a grand total in the first column of the last row,
        # i.e., at ${array[*]: -2:1}, the penultimate index position.
        tbd=($(du -c -b $TGTMNT/$LIVEOS 2> /dev/null || :))
        tbd=${tbd[*]: -2:1}
        if [[ -s $HOMEPATH ]] && [[ -n $keephome ]]; then
            homesize=($(du -b $HOMEPATH))
            tbd=$((tbd - homesize))
        fi
        if [[ -s $OVLPATH ]] && [[ -n $resetoverlay ]]; then
            ovlsize=($(du -c -b $OVLPATH))
            ovlsize=${ovlsize[*]: -2:1}
            tbd=$((tbd - ovlsize))
        fi
    else
        tbd=0
    fi

    targets="$TGTMNT/$SYSLINUXPATH"
    [[ -n $T_EFI_BOOT ]] && targets+=" $TGTMNT$T_EFI_BOOT "
    [[ -n $xo ]] && targets+=$TGTMNT/boot/olpc.fth
    duTable=($(du -c -b $targets 2> /dev/null || :))
    tbd=$((tbd + ${duTable[*]: -2:1}))

    [[ -z ${format[1]} ]] && checkDiskSpace || :
}

if [[ -z ${format[1]} ]]; then
    available=($(df -B 1 $TGTMNT))
    available=${available[*]: -3:1}
fi

[[ -z $skipcopy && live == $srctype ]] && to_be_deleted

# Verify available space for DVD installer
if [[ $srctype == installer ]]; then
    if [[ $imgtype == install ]]; then
        imgpath=images/install.img
    else
        imgpath=isolinux/initrd.img
    fi
    duTable=($(du -s -b $SRCMNT/$imgpath))
    installimgsize=${duTable[0]}

    tbd=0
    if [[ -e $TGTMNT/$imgpath ]]; then
        duTable=($(du -s -b $TGTMNT/$imgpath))
        tbd=${duTable[0]}
    fi
    if [[ -e $TGTMNT/${SRC##*/} ]]; then
        duTable=($(du -s -b "$TGTMNT/${SRC##*/}"))
        tbd=$((tbd + ${duTable[0]}))
    fi
    printf '\nSize of %s:  %s
    \rAvailable space:  %s' $imgpath $installimgsize $((available + tbd)) 
    if (( installimgsize > available + tbd )); then
        printf '\nERROR: Unable to fit DVD image + install.img on the available
        space of the target device.\n'
        exitclean
    fi
fi

if [[ $srctype == live && -d $TGTMNT/$LIVEOS ]]; then
    if [[ ! -d $TGTMNT/$LIVEOS/syslinux ]]; then
        # When operating on a pre-existing, initial installation directory,
        # save any multi menus for later configuration.
        MENUS=$(sed -n -r '/^\s*label .*/I {
               /^\s*label\s+linux\>/I ! {N;N;N;N
               /\<kernel\s+[^ ]*menu.c32\>/p};}' $TGTMNT/syslinux/$CONFIG_FILE)
        MENUS=$(sed 's/.*/&\\/'  <<< "$MENUS")$'\n'
    fi
    if [[ -z $skipcopy ]]; then
        case $force in
        '')
          printf "\nThe '%s' directory is already set up with a LiveOS image.\n
                 " $LIVEOS
          if [[ -z $keephome ]] && [[ -e $HOMEPATH ]]; then
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
          fi ;&
             # The ;& terminator causes case to also execute the next block
             # without testing its pattern.
        force)
          rm -rf -- $TGTMNT/$LIVEOS
        esac
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

cp -p $CONFIG_SRC/* $TGTMNT/$SYSLINUXPATH >/dev/null 2>&1 || :

BOOTCONFIG=$TGTMNT/$SYSLINUXPATH/isolinux.cfg
# Adjust syslinux sources for replication of installed images
# between filesystem types.
if ! [[ -f $BOOTCONFIG ]]; then
    for f in extlinux.conf syslinux.cfg; do
        f=$TGTMNT/$SYSLINUXPATH/$f
        [[ -f $f ]] && mv $f $BOOTCONFIG && break
    done
fi
TITLE=$(sed -n -r '/^\s*label\s+linux/I {n
                   s/^\s*menu\s+label\s+\^\S+\s+(.*)/\1/Ip;q}
                  ' $BOOTCONFIG)
# # Escape special characters for sed regex and replacement strings.
_TITLE=$(sed 's/[]\/;$*.^?+|{}&[]/\\&/g' <<< $TITLE)

# Copy LICENSE and README.
if [[ -z $skipcopy ]]; then
    for f in $SRCMNT/LICENSE $SRCMNT/Fedora-Legal-README.txt; do
        [[ -f $f ]] && cp -p $f $TGTMNT >/dev/null 2>&1 || :
    done
fi

[[ -e $BOOTCONFIG_EFI.multi ]] && rm $BOOTCONFIG_EFI.multi

config_efi() {
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
    if [[ -f $BOOTCONFIG_EFI && ( -n $multi || -n $multidirs ) ]]; then
        mv -Tf $BOOTCONFIG_EFI $BOOTCONFIG_EFI.multi
    fi
    if [[ $TGTMNT/EFI -ef $SRCMNT/EFI ]]; then
        cp $BOOTCONFIG_EFI.multi $BOOTCONFIG_EFI
    else
        cp -Trup $SRCMNT$EFI_BOOT $TGTMNT$T_EFI_BOOT >/dev/null 2>&1 || :
        cp $SRCMNT$EFI_BOOT/grub.cfg $TGTMNT$T_EFI_BOOT

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

    # Test for presence of *.efi GRUB binary.
    local bootefi=($(nocase_path "$TGTMNT$T_EFI_BOOT/boot*efi"))
    #^ Use compound array assignment to accommodate presence of multiple files.
    if [[ ! -f $bootefi ]]; then
        if ! type dumpet >/dev/null 2>&1 && [[ -n $efi ]]; then
            echo "No /usr/bin/dumpet tool found. EFI image will not boot."
            echo "Source media is missing GRUB binary in /EFI/BOOT/*EFI."
            exitclean
        else
            # dump the eltorito image with dumpet, output is $SRC.1
            dumpet -i "$SRC" -d
            local EFIMNT=$(mktemp -d /run/srctmp.XXXXXX)
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
}

# Always install EFI components, when available, so that they are available to
# propagate, if desired from the installed system.
if [[ -n $EFI_BOOT ]]; then
    config_efi
else
    # So sed doesn't complain about missing input variable...
    BOOTCONFIG_EFI=''
fi

# DVD installer copy
# Always install /images directory, when available, so that they may be used
# to propagate a new installation from the installed system.
if [[ -z $skipcopy ]]; then
    echo "Copying /images directory to the target device."
    if [[ -d $SRCMNT/$srcdir/syslinux ]]; then
        sources="$SRCMNT/$srcdir/images"
    else
        sources="$SRCMNT/images"
    fi
    p=${sources%/images}
    for f in $(find $sources); do
        if [[ -d $f ]]; then
            if ! [[ -d $TGTMNT/$multi${f#$p} ]]; then
                mkdir $TGTMNT/$multi${f#$p} || exitclean
            fi
        else
            $copyFile $f $TGTMNT/$multi${f#$p} || exitclean
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
        --exclude TRANS.TBL --exclude LiveOS/ "$SRCMNT/" "$TGTMNT/"$multi
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
        sed -i -r '/^\s*label .*/I {
                   /^\s*label\s+linux\>/I ! {N;N;N;N
                   /\<kernel\s+[^ ]*menu.c32\>/d};}' $BOOTCONFIG
        sed -i -r '/^\s*menu\s+end/I,$ {
                   /^\s*menu\s+end/I ! d}' $BOOTCONFIG
        # Keep only the menu entries up through the first submenu as template.
        if [[ -n $BOOTCONFIG_EFI ]]; then
            sed -i -r "/\s+}$/ { N
                       /\n}$/ { n;Q}}" $BOOTCONFIG_EFI
        fi
        # Restore configuration entries to a base state.
        sed -i -r "s/^\s*timeout\s+.*/timeout 600/I
/^\s*totaltimeout\s+.*/Iz
0,/^\s*menu\s+title\s+Multi Live Image Boot Menu/I {
s/^\s*(menu\s+title\s+).*/\1$_TITLE/I}
s/^(\s*\<kernel)\>\s+\S*(vmlinuz.?)/\1 \2/
/^\s*append\>/I {
s/\<(initrd=).*(initrd.?\.img)\>/\1\2/
s/\<rd\.live\.[^c]\S+\s+//2g}
                  " $BOOTCONFIG
    fi

    # Escape special characters for sed regex and replacement strings.
    _LIVEOS=$(sed 's/[]\/;$*.^?+|{}&[]/\\&/g' <<< $LIVEOS)
    if [[ -n $BOOTCONFIG_EFI ]]; then
        # If --multi, distinguish the new grub menuentry with '$LIVEOS ~'.
        [[ -f $BOOTCONFIG_EFI.multi ]] && [[ $_1stindir != $LIVEOS ]] && livedir=$_LIVEOS\ ~
        sed -i -r "s/^\s*set\s+timeout=.*/set timeout=60/
/^\s*menuentry/ {
s/\S+\s+~$_TITLE/$_TITLE/
s/(^\s*menuentry\s+'.*)$_TITLE(.*')/\1$livedir$_TITLE\2/}
/^\s+linuxefi|initrdefi/ {
s_(linuxefi|initrdefi)\s+\S+(initrd.?\.img|vmlinuz.?)_\1 /images/pxeboot/\2_
s/\<rd\.live\.[^c]\S+\s+//2g}
                 " $BOOTCONFIG_EFI
    fi
fi

# Escape any special characters \/;& for sed replacement strings.
[[ -n $multi ]] && _multi=$(sed 's/[\/;&]/\\&/g' <<< "/$multi")

# Setup the updates.img
if [[ -n $updates ]]; then
    $copyFile "$updates" "$TGTMNT/$multi/updates.img"
    kernelargs+=" inst.updates=hd:$TGTLABEL:$_multi/updates.img"
fi

# Setup the kickstart
if [[ -n $ks ]]; then
    $copyFile "$ks" "$TGTMNT/$multi/ks.cfg"
    kernelargs+=" inst.ks=hd:$TGTLABEL:$_multi/ks.cfg"
fi

echo "Updating boot config files."
# adjust label and fstype
sed -i -r "s/\<root=[^ ]*/root=live:$TGTLABEL/g
        s;inst.stage2=hd:LABEL=[^ ]*;inst.stage2=hd:$TGTLABEL:$_multi/images/install.img;g
        s/\<rootfstype=[^ ]*\>/rootfstype=$TGTFS/" $BOOTCONFIG $BOOTCONFIG_EFI

if [[ -n $kernelargs ]]; then
    sed -i -r "/^\s*append|linuxefi/I {
    s/\s+(rd\.live\.image)(.*)$/ \1 ${kernelargs} \2/
    }" $BOOTCONFIG $BOOTCONFIG_EFI
fi

if [[ -n $BOOTCONFIG_EFI ]]; then
    # EFI images are in $SYSLINUXPATH now.
    _SYSLINUXPATH=$(sed 's/[]\/;$*.^?+|{}&[]/\\&/g' <<< $SYSLINUXPATH)
    f=$(lsblk -ndro PTTYPE $device)
    [[ $f == dos ]] && f=msdos
    f="/^\s*insmod\s+part_(gpt|msdos)\s*$/ s;(gpt|msdos);$f;
      "
    case $TGTFS in
        vfat|msdos)
            i=fat
            ;;
        ext[432])
            i=ext2
            ;;
        *)
            i=$TGTFS
    esac
    f+="/^\s*insmod\s+(ext2|fat|xfs|f2fs|btrfs)\s*$/ s;(ext2|fat|xfs|f2fs|btrfs);$i;
       "
    sed -i -r "$f/^\s*search.*--set=root\s+/ s/-(l|u).*/-u '$TGTUUID'/
               s;/isolinux/;/$_SYSLINUXPATH/;g
               s;/images/pxeboot/;/$_SYSLINUXPATH/;g
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

if [[ -n $overlaysizeb || -n $overlayfs ]] &&
    [[ -z $resetoverlay && -z $copyoverlay ]]; then
    if [[ -z $skipcopy ]]; then
        echo "Initializing persistent overlay..."
        case $overlayfs in
            ext[432]|xfs|btrfs|f2fs)
                mkdir -m 0755 --context=system_u:object_r:root_t:s0 \
                    $OVLPATH $OVLPATH/../ovlwork
                ;;
            vfat|msdos)
                echo 'Formatting overlayfs...'
                mkfs_config ovl OVERLAY overlaysizeb $OVLPATH
                $mkfs $ops
                [[ ${overlaysizeb[1]} == ext[432] ]] &&
                    tune2fs -c0 -i0 -ouser_xattr,acl $OVLPATH
                [[ -n $loop ]] && losetup -d $loop
                ovl=$(mktemp -d)
                mount $OVLPATH $ovl
                mkdir -m 0755 --context=system_u:object_r:root_t:s0 \
                    $ovl/overlayfs $ovl/ovlwork
                umount $ovl
                chmod 0600 $OVLPATH &> /dev/null || :
                ;;
            '')
                falloc $overlaysizeb $OVLPATH
                chmod 0600 $OVLPATH &> /dev/null || :
        esac
    fi
    if [[ -n $overlayfs ]]; then
        sed -i -r 's/rd\.live\.image|liveimg/& rd.live.overlay.overlayfs/
                  ' $BOOTCONFIG $BOOTCONFIG_EFI
    fi
    if [[ -n $overlaysizeb || x${overlayfs#temp} != x ]]; then
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
        mkdir -m 0755 --context=system_u:object_r:root_t:s0 $ovl/overlayfs
        umount $ovl
    elif [[ -d $OVLPATH ]]; then
        rm -r -- $OVLPATH
        mkdir -m 0755 --context=system_u:object_r:root_t:s0 \
            $OVLPATH $OVLPATH/../ovlwork
    else
        dd if=/dev/zero of=$OVLPATH bs=64k count=1 conv=notrunc,fsync
    fi
fi
[[ $overlayfs == @(vfat|msdos) ]] && fscheck ${overlaysizeb[1]} $OVLPATH
if [[ -n $resetoverlay || -n $copyoverlay ]]; then
    ovl=''
    [[ -n $overlayfs ]] && ovl=' rd.live.overlay.overlayfs'
    sed -i -r "s/rd\.live\.image|liveimg/& rd.live.overlay=${TGTLABEL}$ovl/
              " $BOOTCONFIG $BOOTCONFIG_EFI
fi

if ((swapsizeb > 0)); then
    echo "Initializing swap file."
    if [[ -z $skipcopy ]]; then
        falloc $swapsizeb $TGTMNT/$LIVEOS/swap.img
        [[ $TGTFS == btrfs ]] && chattr +C $TGTMNT/$LIVEOS/swap.img
        chmod 0600 $TGTMNT/$LIVEOS/swap.img &> /dev/null || :
    fi
    mkswap -f $TGTMNT/$LIVEOS/swap.img
fi

if ((homesizeb > 0)) && [[ -z $skipcopy ]]; then
    echo "Initializing persistent /home directory filesystem."
    if [[ -n $cryptedhome ]]; then
        dd if=/dev/urandom of=$HOMEPATH count=$((homesizeb>>20)) bs=1MiB\
        status=progress
        cloop=$(losetup -f --show $HOMEPATH)

        echo "Encrypting persistent home.img"
        while ! cryptsetup luksFormat -y -q $cloop; do :; done;

        echo "Please enter the password again to unlock the device"
        while ! cryptsetup luksOpen $cloop EncHomeFoo; do :; done;

        mkfs_config home HOME homesizeb
        $mkfs $ops /dev/mapper/EncHomeFoo
        [[ ${homesizeb[1]} == ext[432] ]] &&
            tune2fs -c0 -i0 -ouser_xattr,acl /dev/mapper/EncHomeFoo
        sleep 2
        fscheck ${homesizeb[1]} /dev/mapper/EncHomeFoo
        cryptsetup luksClose EncHomeFoo
        losetup -d $cloop
    else
        echo "Formatting unencrypted home.img"
        mkfs_config home HOME homesizeb $HOMEPATH
        $mkfs $ops
        [[ ${homesizeb[1]} == ext[432] ]] &&
            tune2fs -c0 -i0 -ouser_xattr,acl $HOMEPATH
        fscheck ${homesizeb[1]} $HOMEPATH
        [[ -n $loop ]] && losetup -d $loop
    fi
    chmod 0600 $HOMEPATH &> /dev/null || :
fi

if [[ $LIVEOS != LiveOS ]]; then
    sed -i -r "s;rd\.live\.image|liveimg;& rd.live.dir=$_LIVEOS;
              " $BOOTCONFIG $BOOTCONFIG_EFI
fi

if [[ live = $srctype ]]; then
    sed -i -r '/^\s*append|linuxefi/I {
              s/\s+ro\>//g
              s/rd\.live\.image|liveimg/rw &/}' $BOOTCONFIG $BOOTCONFIG_EFI
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
                cp -p $d/$f $TGTMNT/$BOOTPATH/$f >/dev/null 2>&1 || :
                break 2
            fi
        done
    fi
done

if [[ $multi == $LIVEOS ]] && [[ $_1stindir != $LIVEOS ]]; then
    # We need to do some more config file tweaks for multi-image mode.
    sed -i -r "s;\s+[^ ]*menu\.c32\>; $UI;g
               s;kernel\s+vm;kernel /$_LIVEOS/syslinux/vm;
               s;initrd=i;initrd=/$_LIVEOS/syslinux/i;
              " $TGTMNT/$SYSLINUXPATH/isolinux.cfg
    sed -i -r "/^\s*label\s+$_LIVEOS\>/I { N;N;N;N; d }
               0,/^\s*label\s+.*/I {
               /^\s*label\s+.*/I i\
               label $LIVEOS\\
\  menu label ^Go to $LIVEOS ~$TITLE menu\\
\  kernel $UI\\
\  APPEND /$LIVEOS/syslinux/$CONFIG_FILE\\

               }" $TGTMNT/syslinux/$CONFIG_FILE

    cat << EOF >> $TGTMNT/$SYSLINUXPATH/isolinux.cfg
menu separator
LABEL multimain
  MENU LABEL Return to Multi Live Image Boot Menu
  KERNEL $UI
  APPEND ~
EOF
_LIVEOS=*$_LIVEOS
fi

# Remove duplicated entries (mid/end line) and double whitespace after words.
sed  -i -r '/^\s*append|linuxefi/I {
            :w;s/(\s+\S+)\s*(.*)\1(\s+|$)/\1 \2\3/g;tw
            s/\>\s\s+/ /g
            s/\s+$//}' $BOOTCONFIG $BOOTCONFIG_EFI

mv $TGTMNT/$SYSLINUXPATH/isolinux.cfg $TGTMNT/$SYSLINUXPATH/$CONFIG_FILE

if [[ -n $MENUS ]]; then
    sed -i -r "/^\s*label\s+linux/I i\
    $MENUS
    " $TGTMNT/$SYSLINUXPATH/$CONFIG_FILE
fi
[[ -n $multi || -n $multidirs ]] &&
    sed -i -r "1,20 s/^\s*(menu\s+title)\s+.*/\1 Multi Live Image Boot Menu/I
              " $TGTMNT/syslinux/$CONFIG_FILE

sed -i -r "s/\s+[^ ]*menu\.c32\>/ $UI/g" $TGTMNT/$SYSLINUXPATH/$CONFIG_FILE

if [[ -f $BOOTCONFIG_EFI.multi ]]; then
    # (Implies --multi and the presence of EFI components.)
    # Insert marker and delete any menu entries with conflicting paths.
    sed -i -r "1 i\
...
               /^\s*menuentry\s+.*/ {N;N;N;N;N;N;N;N;N;N;N;N;N
               \,\s+\/$_SYSLINUXPATH, d }" $BOOTCONFIG_EFI.multi
    # Append other pre-existing menus.
    cat $BOOTCONFIG_EFI.multi >> $BOOTCONFIG_EFI
    # Clear header that came from $BOOTCONFIG_EFI.multi.
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
        cp -p /usr/share/syslinux/$f $TGTMNT/$BOOTPATH/$f >/dev/null 2>&1 || :
    elif [[ $syslinuxboot == missing ]]; then
        break
    else
        printf "\n        ATTENTION:
        Failed to find /usr/share/syslinux/$f.
        The installed device may not boot.
                Press Enter to continue, or Ctrl C to abort.\n"
        read
    fi
done

if [[ -n $BOOTCONFIG_EFI ]]; then
    if [[ $(lsblk -no PARTTYPE $p2 2>/dev/null) == \
        @(c12a7328-f81f-11d2-ba4b-00a0c93ec93b|0xef) ]]; then
        d=$(mktemp -d)
        mount $p2 $d
        if ! [[ $nouefi ]] && [[ $TGTFS == f2fs ]] && [[ $xa ]]; then
            # Build a UEFI executable for use as an EFI Boot Stub.
            if ! [[ $flat_squashfs ]]; then
                mount -r "$SRCIMG" $IMGMNT || exitclean
            fi
            mount -r $RFSIMG $IMGMNT || exitclean
            f="dracut $d/linux_$LIVEOS.efi  --uefi --kmoddir \
            $IMGMNT/usr/lib/modules/$kver --kver $kver --no-machineid \
            --kernel-image $CONFIG_SRC/vmlinuz* --no-hostonly \
            --add dmsquash-live --add-drivers f2fs"
            p=''
            [[ $overlay == none ]] && p=rd.live.overlay=none
            [[ $overlaysizeb ]] || [[ x${overlayfs#temp} != x ]] &&
                p+="rd.live.overlay=$TGTLABEL"
            [[ $overlayfs ]] && p+=' rd.live.overlay.overlayfs'
            [[ ${_LIVEOS:0:1} == \* ]] && p+=" rd.live.dir=$LIVEOS"
            [[ $kernelargs ]] && p+=" $kernelargs"
            f=$(sed 's/ \+/ /g' <<< $f)
            printf "
       \rPlease wait...  Building a UEFI executable for use as an EFI Boot Stub
       \rwith the following dracut command:\n
       \r$f --kernel-cmdline \"root=live:$TGTLABEL rd.live.image rw $p\"\n\n"
      efi=$($f --kernel-cmdline "root=live:$TGTLABEL rd.live.image rw $p" 2>&1)
            # 'Silence is golden' here.
            [[ $efi ]] && printf "\nNOTICE:  $efi\n\n" && cleansrc && exitclean
            p=$srcdev
            [[ $SRCFS == iso9660 ]] && p=$(findmnt -no SOURCE $SRCMNT)
            efi=$label-$LIVEOS-$(blkid -s LABEL -o value $p)
            f="efibootmgr --create --disk $device --part 2 \
--loader \\linux_$LIVEOS.efi \\
--label "
            y=$(date +%Y)
            p="
    NOTICE:
            Flash-Friendly File System (F2FS) formatted devices with
            extra_attr or compression fail to boot with
            year $y versions of SYSLINUX-EXTLINUX or GNU GRUB.

            Booting is possible with an EFI Boot Stub loader.\n"
            if ! [[ $force ]]; then
                if [[ -d /sys/firmware/efi ]]; then
                    IFS=: read -r -p "$p
            If you would like to write the following, new boot entry into
            your computer system's UEFI Boot Manager, press 'Enter', or
            first input a substitute for the proposed label:

$f$efi

            Or, press the [space bar] + 'Enter' to skip this step.
            " msg
                    case $msg in
                        +(' '))
                            :
                            ;;
                        '')
                            f+="$efi"
                            ;&
                        *)
                            f+="$msg"
                            $f
                    esac
                    unset -v msg
                else
                    msg="$p
            From a UEFI booted image, the following command would write a
            new boot entry into the computers's UEFI Boot Manager:

sudo $f$efi\n\n        (You may choose any suitable label.)\n"
                fi
            fi
            cleansrc
        fi
        [[ -f $d$T_EFI_BOOT/grub.cfg ]] &&
            cp -p $d$T_EFI_BOOT/grub.cfg $TGTMNT$T_EFI_BOOT/grub.cfg.prev
        cp -a $TGTMNT/EFI $d >/dev/null 2>&1 || :

        if [[ $TGTFS == f2fs ]] && ! [[ $xa ]] && ! [[ $b ]]; then
            mv $TGTMNT$T_EFI_BOOT/BOOTX64.EFI $TGTMNT$T_EFI_BOOT/BOOTX64.EFI.orig
            p="grub2-mkimage --format=x86_64-efi --prefix=/EFI/BOOT \
            --output=$d/EFI/BOOT/BOOTX64.EFI --compression=xz fat ext2 f2fs \
            iso9660 ls loopback part_gpt part_msdos normal configfile boot \
            linux reboot search search_label search_fs_uuid gfxterm_background \
            gfxterm gfxterm_menu all_video video_cirrus video_bochs efi_gop \
            efi_uga"
            p=$(sed 's/ \+/ /g' <<< $p)
            efi=$($p 2>&1)
            [[ $efi ]] && printf $efi
            msg="    NOTICE:
            A GRUB EFI boot binary with F2FS filesystem support for
            x86_64 architecture systems has been built in the
            EFI System Partition at the fallback boot loader path
            <ESP>/EFI/BOOT/BOOTX64.EFI using this command:\n\n$p\n
            \rOther EFI binaries in /EFI/BOOT lack FSFS support at this time."
            cp $d/EFI/BOOT/BOOTX64.EFI $TGTMNT$T_EFI_BOOT/BOOTX64.EFI
        fi
        umount $d && rmdir $d
        fsck.fat -avVw $p2 || :
        echo
    fi
    if [[ $(lsblk -no PARTTYPE $p3 2>/dev/null) == \
        @(48465300-0000-11aa-aa11-00306543ecac|0xaf) ]]; then
        d=$(mktemp -d)
        mount -t hfsplus $p3 $d
        for f in $TGTMNT$T_EFI_BOOT/BOOT.conf $TGTMNT$T_EFI_BOOT/grub.cfg \
            $TGTMNT$T_EFI_BOOT/BOOTX64.EFI; do
            [[ -f $f ]] && cp $f $d$T_EFI_BOOT
        done
        cp $TGTMNT$T_EFI_BOOT/grub.cfg $d/System/Library/CoreServices
        [[ -f $BOOTCONFIG_EFI.prev ]] && cp $BOOTCONFIG_EFI.prev $d$T_EFI_BOOT
        umount $d && rmdir $d
        fsck.hfsplus -yrdfp $p3
        echo
    fi
fi

case $TGTFS in
    vfat|msdos)
        # syslinux expects the config to be named syslinux.cfg
        # and has to run with the file system unmounted.

        # Deal with mtools complaining about ldlinux.sys
        if [[ -f $TGTMNT/$BOOTPATH/ldlinux.sys ]]; then
            rm -f $TGTMNT/$BOOTPATH/ldlinux.sys
        fi
        cleanup
        if [[ -n $BOOTPATH ]]; then
            # Show error message if syslinux fails.
            syslinux -d $BOOTPATH $TGTDEV || :
        elif [[ $syslinuxboot != missing ]]; then
            syslinux $TGTDEV || :
        fi
        ;;
    ext[432]|btrfs|xfs)
        # extlinux expects the config to be named extlinux.conf
        # and has to be run with the file system mounted.
        if [[ $syslinuxboot != missing ]]; then
            extlinux -i $TGTMNT/$BOOTPATH || :
        fi
        # Starting with syslinux 4, ldlinux.sys is used on all file systems.
        if [[ -f $TGTMNT/$BOOTPATH/extlinux.sys ]]; then
            chattr -i $TGTMNT/$BOOTPATH/extlinux.sys
        elif [[ -f $TGTMNT/$BOOTPATH/ldlinux.sys ]]; then
            chattr -i $TGTMNT/$BOOTPATH/ldlinux.sys
        fi
        ;&
    f2fs)
        cleanup
esac

[[ -n $multi || -n $multidirs ]] && multi=Multi\ 
echo -e "\nTarget device is now set up with a ${multi}Live image!\n"
if [[ $xa == nof2fs.mod && $nouefi ]]; then
    printf 'HOWEVER:  Please note, a boot loader suitable for F2FS is lacking.\n
    Either run "sudo dnf install grub2-efi-x64-modules" to install
    the tools needed to build a new GRUB EFI binary, or\n
    run the command "sudo dnf install binutils" to install a
    dependency needed to build an EFI Boot Stub, which bypasses GRUB.\n
    And then rerun this installation with the --reconfig option
    and targeting '\''%s'\''.\n
See https://fedoraproject.org/wiki/LiveOS_image#Flash-Friendly_File_System_.28F2FS.29
    for more information.\n\n' $TGTDEV
fi
[[ $msg ]] && printf "$msg\n\n" || :
trap - EXIT
