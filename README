
                       The Fedora Live CD Tools
                    David Zeuthen <davidz@redhat.com>
                    Jeremy Katz <katzj@redhat.com>

                    Last Updated: October 2018

This project concerns tools to generate live CDs on Fedora based
systems including derived distributions such as RHEL, CentOS, and
others. See the project Wiki at 

 https://fedoraproject.org/wiki/FedoraLiveCD

for more details. Discussion of this project takes place at the
livecd@lists.fedoraproject.org mailing list

 https://lists.fedoraproject.org/admin/lists/livecd.lists.fedoraproject.org/

This project and its source files are licensed under the GPLv2
license. See the file COPYING for details.

1. LIVE CD DESIGN GOALS

The live CD is designed in such a way that when running from a
live CD, the system should appear as much as possible as a standard
system with all that entails; e.g., read-write rootfs (achieved using
dm-snapshot or OverlayFS with the --flat-squashfs option), standard ext4 file
system (for extended attributes) or a direct SquashFS, and so on. 

Another design goal is that the live CD should be ''installable'',
i.e., a user should be able to install the bits from the live CD onto
a hard disk without this process requiring network access or additional
media.

Finally, another design goal is that the tool set itself should be
separate from configuration; the same unmodified tool should be usable
for building various live CD flavors with vastly different
configurations, e.g., a GNOME live CD, a KDE live CD, a live CD with
music programs, and so on.

2. CREATING A LIVE CD

To create a live CD, the livecd-creator tool is used. Super user
privileges are needed. The tool is more or less self-documenting, use
the --help option to see options.

2.1 HOW THE LIVE CD CREATOR WORKS

In a nutshell, the livecd-creator program

 o Sets up a file for the ext4 file system that will contain all the
   data comprising the live CD

 o Loop mounts that file into the file system so there is an
   installation root

 o Bind mounts certain kernel file systems (/dev, /dev/pts, /proc,
   /sys, /selinux) inside the installation root

 o Uses a configuration file to define the requested packages and
   default configuration options.  The format of this file is the same
   as is used for installing a system via kickstart.

 o Installs, using DNF, the requested packages into the installation
   using the given repositories

 o Optionally runs scripts as specified by the live CD configuration file. 

 o Relabels the entire installation root (for SELinux)

 o Creates a live CD specific initramfs that matches the installed kernel

 o Unmounts the kernel file systems mounted inside the installation root

 o Unmounts the installation root

 o Runs resize2fs to minimize and unminimize the ext4 file to remove data
   from deleted files

 o Runs resize2fs to minimize on a device-mapper snapshot, to generate a
   small minimized delta image file which was historically used by anaconda to
   reduce installation time by not copying unused data to disk

 o Creates a SquashFS file system containing only the ext4 file (compression)
   or directly from the installation root (for OverlayFS overlays)

 o Configures the boot loader

 o Creates an iso9660 bootable CD


2.2 EXAMPLE: A BAREBONES LIVE CD

The command

# livecd-creator \
  --config=/usr/share/doc/livecd-tools/livecd-fedora-minimal.ks

will create a live CD that will boot to a login prompt. Note that in this
minimal example, since no configuration is done, the user will not be able to
login to the system as the root password is not set or cleared.

2.3 LIVE CD CONFIGURATION FILES

The configuration of the live CD is defined by a file that uses the
same format as installing a system via kickstart.  They can include
some basic system configuration items, the package manifest and a
script to be run at the end of the build process.

For the Fedora project, there are currently a variety of different live CD
configuration files.  The spin-kickstarts package includes all of the
kickstarts used to create the various spins. These include a minimal live image
(fedora-minimal-common.ks), a complete workstation image
(fedora-live-workstation.ks) and others.

2.4 EXAMPLE: SPINNING THE FEDORA WORKSTATION LIVE CD

Assuming that you use the fedora-live-workstation.ks configuration file,
then the following command

# livecd-creator \
  --config=/usr/share/spin-kickstarts/fedora-live-workstation.ks \
  --fslabel=Fedora-29-WS-Live-foo

will create a live CD called "Fedora-29-WS-Live-foo". The name
given by --fslabel is used.

 o as a file system label on the ext4 and iso9660 file systems
   (as such it's visible on the desktop as the CD name)

 o in the isolinux boot loader

If you have the repositories available locally and don't want to wait
for the download of packages, just substitute the URLs listed in the
configuration file to point to your local repositories.

3. LIVE CD INSTALLS

As of Fedora 7, Anaconda has support for doing an installation
from a live CD.  To use this, double click on the "Install to Hard
Drive" item on the desktop or run /usr/bin/liveinst if you don't have
such an icon.

4. LIVE CD MEDIA VERIFICATION

The live CD can incorporate functionality to verify itself.  To do so,
you need to have isomd5sum installed both on the system used for creating
the image and installed into the image.  This is so that the implantisomd5
and checkisomd5 utilities can be used. These utilities take advantage of
embedding an md5sum into the application area of the iso9660 image.
This then gets verified before mounting the real root filesystem.

These utilities used to be part of the anaconda-runtime package.

5. LOADING LIVE IMAGES ONTO USB MEDIA 

USB sticks are becoming increasingly prevalent and are a nice way to
use live images.  You can take a live CD iso image and transform it so
that it can be used on a USB stick.  To do so, use the
livecd-iso-to-disk script, like the following:

   livecd-iso-to-disk /path/to/live.iso /dev/sdb1

Replace the '/dev/sdb1' argument above with the (unmounted) partition where you
wish to load the live image.  This is not a destructive process; any data you 
currently have on your USB stick will be preserved.

Multiple images may be loaded onto a single USB stick.

See livecd-iso-to-disk --help for more options and instructions.

6. MOUNTING LIVE IMAGES 

A live CD .iso file or an installed live USB device may be mounted with the
liveimage-mount script to peer into the live OS filesystem, or even edit it on
a device loaded with a persistent storage overlay.

   liveimage-mount /path/to/live[.iso|device|directory] <mountpoint>

See liveimage-mount --help for more options.

7. EDITING LIVE IMAGES

Live OS images may be edited using the editliveos script:

   editliveos [options] <LiveOS_source>

This script may be used to merge a persistent overlay, insert files, clone a
customized instance, adjust the root or home filesystem or overlay sizes and
filesystem or overlay types, seclude private or user-specific files, rebuild
the image into a new, .iso image distribution file, and refresh the source's
persistent filesystem overlay.

See editliveos --help for more options and instructions.


