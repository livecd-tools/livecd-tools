#!/bin/bash
# Convert a live CD iso so that it can be booted over the network
# using PXELINUX.
# Copyright 2008 Red Hat, Inc.
# Written by Richard W.M. Jones <rjones@redhat.com>
# Based on a script by Jeremy Katz <katzj@redhat.com>
# Based on original work by Chris Lalancette <clalance@redhat.com>
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
    echo "Usage: livecd-iso-to-pxeboot <isopath>"
    exit 1
}

cleanup() {
    [ -d "$STRIPPEDISO" ] && rm -rf $STRIPPEDISO
    [ -d "$CDMNT" ] && umount $CDMNT && rmdir $CDMNT
}

cleanup_error() {
    echo "Cleaning up to exit..."
    cleanup
    exit 1
}

if [ $(id -u) != 0 ]; then
    echo "You need to be root to run this script."
    exit 1
fi

# Check pxelinux.0 exists.
if [ ! -f /usr/share/syslinux/pxelinux.0 -a ! -f /usr/lib/syslinux/pxelinux.0 ]; then
    echo "Warning: pxelinux.0 not found."
    echo "Make sure syslinux or pxelinux is installed on this system."
fi

while [ $# -gt 1 ]; do
    case "$1" in
	*) usage ;;
    esac
    shift
done

ISO="$1"

if [ -z "$ISO" -o ! -e "$ISO" ]; then
    usage
fi

if [ -d tftpboot ]; then
    echo "Subdirectory tftpboot exists already.  I won't overwrite it."
    echo "Delete the subdirectory before running."
    exit 1
fi

# Mount the ISO.
CDMNT=$(mktemp -d /var/tmp/$(basename $0)-mount.XXXXXX)
STRIPPEDISO=$(mktemp -d /var/tmp/$(basename $0)-stripped.XXXXXX)
mount -o loop "$ISO" $CDMNT || cleanup_error

trap cleanup_error SIGINT SIGTERM
trap cleanup EXIT

# Does it look like an ISO?
if [[ ( ! -d $CDMNT/isolinux ) || ( ! -f $CDMNT/isolinux/initrd0.img && ! -f $CDMNT/isolinux/initrd.img  ) ]]; then
    echo "The ISO image doesn't look like a LiveCD ISO image to me."
    cleanup_error
fi

if [[ -f $CDMNT/isolinux/initrd0.img ]]; then
    INITRD=initrd0.img
    VMLINUZ=vmlinuz0
else
    INITRD=initrd.img
    VMLINUZ=vmlinuz
fi

mkdir tftpboot

# Create a cpio archive of just the ISO and append it to the
# initrd image.  The Linux kernel will do the right thing,
# aggregating both cpio archives (initrd + ISO) into a single
# filesystem.
NEWISO=$STRIPPEDISO/`basename "$ISO"`
xorrisofs -quiet -joliet -joliet-long -rational-rock -output $NEWISO -root LiveOS $CDMNT/LiveOS/squashfs.img
ISOBASENAME=`basename "$NEWISO"`
ISODIRNAME=`dirname "$NEWISO"`
( cd "$STRIPPEDISO" && echo "$ISOBASENAME" | cpio -H newc --quiet -L -o ) |
  gzip -9 |
  cat $CDMNT/isolinux/$INITRD - > tftpboot/$INITRD

# Kernel image.
cp $CDMNT/isolinux/$VMLINUZ tftpboot/$VMLINUZ

# pxelinux bootloader.
if [ -f /usr/share/syslinux/pxelinux.0 ]; then
    cp /usr/share/syslinux/pxelinux.0 tftpboot
    cp /usr/share/syslinux/ldlinux.c32 tftpboot
elif [ -f /usr/lib/syslinux/pxelinux.0 ]; then
    cp /usr/lib/syslinux/pxelinux.0 tftpboot
    cp /usr/lib/syslinux/ldlinux.c32 tftpboot
else
    echo "Warning: You need to add pxelinux.0 to tftpboot/ subdirectory"
fi

# Get boot append line from original cd image.
if [ -f $CDMNT/isolinux/isolinux.cfg ]; then
    APPEND=$(grep -m1 append $CDMNT/isolinux/isolinux.cfg | sed -e "s#CDLABEL=[^ ]*#/$ISOBASENAME#" -e "s/ *append *//")
fi

# pxelinux configuration.
mkdir tftpboot/pxelinux.cfg
cat > tftpboot/pxelinux.cfg/default <<EOF
DEFAULT pxeboot
TIMEOUT 20
PROMPT 0
LABEL pxeboot
	KERNEL $VMLINUZ
	APPEND rootflags=loop $APPEND
ONERROR LOCALBOOT 0
EOF

echo "Your pxeboot image is complete."
echo
echo "Copy tftpboot/ subdirectory to /tftpboot or a subdirectory of /tftpboot."
echo "Set up your DHCP, TFTP and PXE server to serve /tftpboot/.../pxeboot.0"
echo
echo "Note: The initrd image contains the whole CD ISO and is consequently"
echo "very large.  You will notice when pxebooting that initrd can take a"
echo "long time to download.  This is normal behaviour."

exit 0
