#
# live.py : LiveImageCreator class for creating Live CD images
#
# Copyright 2007-2012, Red Hat, Inc.
# Copyright 2016-2018, Kevin Kofler
# Copyright 2016, Neal Gompa
# Copyright 2017-2018, Fedora Project
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

import sys
import os
import errno
import os.path
import glob
import shutil
import subprocess
import logging
import re
import hawkey
import dnf.rpm

from imgcreate.errors import *
from imgcreate.fs import *
from imgcreate.creator import *

class LiveImageCreatorBase(LoopImageCreator):
    """A base class for LiveCD image creators.

    This class serves as a base class for the architecture-specific LiveCD
    image creator subclass, LiveImageCreator.

    LiveImageCreator creates a bootable ISO containing the system image,
    bootloader, bootloader configuration, kernel and initramfs.

    """

    def __init__(self, ks, name, fslabel=None, releasever=None, tmpdir="/tmp",
                 title="Linux", product="Linux", useplugins=False, cacheonly=False,
                 docleanup=True):
        """Initialise a LiveImageCreator instance.

        This method takes the same arguments as LoopImageCreator.__init__().

        """
        LoopImageCreator.__init__(self, ks, name,
                                  fslabel=fslabel,
                                  releasever=releasever,
                                  tmpdir=tmpdir,
                                  useplugins=useplugins,
                                  cacheonly=cacheonly,
                                  docleanup=docleanup)

        self.compress_type = "xz"
        """mksquashfs compressor to use."""

        self.skip_compression = False
        """Controls whether to use squashfs to compress the image."""

        self.skip_minimize = False
        """Controls whether an image minimizing snapshot should be created.

        This snapshot can be used when copying the system image from the ISO in
        order to minimize the amount of data that needs to be copied; simply,
        it makes it possible to create a version of the image's filesystem with
        no spare space.

        """

        self._timeout = kickstart.get_timeout(self.ks, 10)
        """The bootloader timeout from kickstart."""

        self._default_kernel = kickstart.get_default_kernel(self.ks, "kernel")
        """The default kernel type from kickstart."""

        self.__isodir = None

        self.__modules = ["=ata", "sym53c8xx", "aic7xxx", "=usb", "=firewire",
                          "=mmc", "=pcmcia", "mptsas", "virtio_blk",
                          "virtio_pci", "virtio_scsi", "virtio_net", "virtio_mmio",
                          "virtio_balloon", "virtio-rng"]

        self._isofstype = "iso9660"
        self.base_on = False

        self.title = title
        self.product = product

    #
    # Hooks for subclasses
    #
    def _configure_bootloader(self, isodir):
        """Create the architecture specific booloader configuration.

        This is the hook where subclasses must create the booloader
        configuration in order to allow a bootable ISO to be built.

        isodir -- the directory where the contents of the ISO are to be staged

        """
        raise CreatorError("Bootloader configuration is arch-specific, "
                           "but not implemented for this arch!")

    def _get_kernel_options(self):
        """Return a kernel options string for bootloader configuration.

        This is the hook where subclasses may specify a set of kernel options
        which should be included in the images bootloader configuration.

        A sensible default implementation is provided.

        """
        r = kickstart.get_kernel_args(self.ks)
        if (chrootentitycheck('rhgb', self._instroot) or
            chrootentitycheck('plymouth', self._instroot)):
            r += " rhgb"
        return r

    def _get_xorrisofs_options(self, isodir):
        """Return the architecture specific xorrisofs options.

        This is the hook where subclasses may specify additional arguments to
        xorrisofs, e.g. to enable a bootable ISO to be built.

        By default, an empty list is returned.

        """
        return []

    #
    # Helpers for subclasses
    #
    def _has_checkisomd5(self):
        """Check whether checkisomd5 is available in the install root."""
        for c in '/usr/lib/anaconda-runtime/checkisomd5', 'checkisomd5':
            if chrootentitycheck(c, self._instroot):
                return True
                break
        else:
            return False

    #
    # Actual implementation
    #
    def _base_on(self, base_on):
        """helper function to extract ext3 file system from a live CD ISO"""
        isoloop = DiskMount(LoopbackDisk(base_on, 0), self._mkdtemp())

        try:
            isoloop.mount()
        except MountError as e:
            raise CreatorError("Failed to loopback mount '%s' : %s" %
                               (base_on, e))

        # Copy the initrd%d.img and xen%d.gz files over to /isolinux
        # This is because the originals in /boot are removed when the
        # original .iso was created.
        src = isoloop.mountdir + "/isolinux/"
        dest = self.__ensure_isodir() + "/isolinux/"
        makedirs(dest)
        pattern = re.compile(r"(initrd\d+\.img|xen\d+\.gz)")
        files = [f for f in os.listdir(src) if pattern.search(f)
                                               and os.path.isfile(src+f)]
        for f in files:
            shutil.copyfile(src+f, dest+f)

        # legacy LiveOS filesystem layout support, remove for F9 or F10
        if os.path.exists(isoloop.mountdir + "/squashfs.img"):
            squashimg = isoloop.mountdir + "/squashfs.img"
        else:
            squashimg = isoloop.mountdir + "/LiveOS/squashfs.img"

        squashloop = DiskMount(LoopbackDisk(squashimg, 0), self._mkdtemp(), "squashfs")

        # 'self.compress_type = None' will force reading it from base_on.
        if self.compress_type is None:
            self.compress_type = squashfs_compression_type(squashimg)
            if self.compress_type == 'undetermined':
                # Default to 'gzip' for compatibility with older versions.
                self.compress_type = 'gzip'
        try:
            if not squashloop.disk.exists():
                raise CreatorError("'%s' is not a valid live CD ISO : "
                                   "squashfs.img doesn't exist" % base_on)

            try:
                squashloop.mount()
            except MountError as e:
                raise CreatorError("Failed to loopback mount squashfs.img "
                                   "from '%s' : %s" % (base_on, e))

            # Test for flattened squashfs.
            os_image = os.path.join(squashloop.mountdir, 'proc')
            if os.path.isdir(os_image):
                os_image = squashimg
            else:
                for f in ('rootfs.img', 'ext3fs.img'):
                    os_image = os.path.join(squashloop.mountdir, 'LiveOS', f)
                    if os.path.exists(os_image):
                        break

            if not os.path.exists(os_image):
                raise CreatorError("'%s' is not a valid live CD ISO : neither "
                "LiveOS/rootfs.img, ext3fs.img, nor squashfs.img exist" %
                base_on)

            try:
                shutil.copyfile(os_image, self._image)
            except IOError as e:
                raise CreatorError("Failed to copy base live image to %s for modification: %s" %(self._image, e))
        finally:
            squashloop.cleanup()
            isoloop.cleanup()

    def _mount_instroot(self, base_on = None):
        self.base_on = True
        LoopImageCreator._mount_instroot(self, base_on)
        self.__write_initrd_conf(self._instroot + "/etc/sysconfig/mkinitrd")
        self.__write_dracut_conf(self._instroot + "/etc/dracut.conf.d/99-liveos.conf")

    def _unmount_instroot(self):
        self.__restore_file(self._instroot + "/etc/sysconfig/mkinitrd")
        self.__restore_file(self._instroot + "/etc/dracut.conf.d/99-liveos.conf")
        LoopImageCreator._unmount_instroot(self)

    def __ensure_isodir(self):
        if self.__isodir is None:
            self.__isodir = self._mkdtemp("iso-")
        return self.__isodir

    def _generate_efiboot(self, isodir):
        """Generate EFI boot images."""
        if not glob.glob(self._instroot+"/boot/efi/EFI/*/shim.efi"):
            logging.error("Missing shim.efi, skipping efiboot.img creation.")
            return

        # XXX-BCL: does this need --label?
        subprocess.call(["mkefiboot", isodir + "/EFI/BOOT",
                         isodir + "/isolinux/efiboot.img"])
        subprocess.call(["mkefiboot", "-a", isodir + "/EFI/BOOT",
                         isodir + "/isolinux/macboot.img", "-l", self.product,
                         "-n", "/usr/share/pixmaps/bootloader/fedora-media.vol",
                         "-i", "/usr/share/pixmaps/bootloader/fedora.icns",
                         "-p", self.product])

    def _create_bootconfig(self):
        """Configure the image so that it's bootable."""
        self._configure_bootloader(self.__ensure_isodir())
        self._generate_efiboot(self.__ensure_isodir())

    def _get_post_scripts_env(self, in_chroot):
        env = LoopImageCreator._get_post_scripts_env(self, in_chroot)

        if not in_chroot:
            env["LIVE_ROOT"] = self.__ensure_isodir()

        return env

    def __extra_filesystems(self):
        return "vfat msdos isofs ext4 xfs btrfs squashfs";

    def __extra_drivers(self):
        retval = "sr_mod sd_mod ide-cd cdrom "
        for module in self.__modules:
            if module == "=usb":
                retval = retval + "ehci_hcd uhci_hcd ohci_hcd "
                retval = retval + "usb_storage usbhid uas "
            elif module == "=firewire":
                retval = retval + "firewire-sbp2 firewire-ohci "
                retval = retval + "sbp2 ohci1394 ieee1394 "
            elif module == "=mmc":
                retval = retval + "mmc_block sdhci sdhci-pci "
            elif module == "=pcmcia":
                retval = retval + "pata_pcmcia "
            else:
                retval = retval + module + " "
        return retval

    def __restore_file(self,path):
        try:
            os.unlink(path)
        except:
            pass
        if os.path.exists(path + '.rpmnew'):
            os.rename(path + '.rpmnew', path)

    def __write_initrd_conf(self, path):
        if not os.path.exists(os.path.dirname(path)):
            makedirs(os.path.dirname(path))
        f = open(path, "a")
        f.write('LIVEOS="yes"\n')
        f.write('PROBE="no"\n')
        f.write('MODULES+="' + self.__extra_filesystems() + '"\n')
        f.write('MODULES+="' + self.__extra_drivers() + '"\n')
        f.close()

    def __write_dracut_conf(self, path):
        if not os.path.exists(os.path.dirname(path)):
            makedirs(os.path.dirname(path))
        f = open(path, "a")
        f.write('filesystems+="' + self.__extra_filesystems() + ' "\n')
        f.write('add_drivers+="' + self.__extra_drivers() + ' "\n')
        f.write('add_dracutmodules+=" dmsquash-live pollcdrom "\n')
        f.write('hostonly="no"\n')
        f.write('dracut_rescue_image="no"\n')
        f.close()

    def __create_iso(self, isodir):
        iso = self._outdir + "/" + self.name + ".iso"

        args = ["xorrisofs",
                "-joliet", "-rational-rock",
                "-hide-rr-moved",
                "-volid", self.fslabel,
                "-output", iso]

        args.extend(self._get_xorrisofs_options(isodir))

        args.append(isodir)

        if subprocess.call(args) != 0:
            raise CreatorError("ISO creation failed!")

        self.__implant_md5sum(iso)

    def __implant_md5sum(self, iso):
        """Implant an isomd5sum."""
        for c in 'implantisomd5', '/usr/lib/anaconda-runtime/implantisomd5':
            try:
                subprocess.call([c, iso])
                break
            except OSError as e:
                if e.errno == errno.ENOENT:
                    continue
        else:
            logging.warning('isomd5sum not installed; '
                            'not setting up mediacheck')
        return

    def _stage_final_image(self, ops=[]):
        try:
            makedirs(self.__ensure_isodir() + "/LiveOS")

            self._resparse()

            if not self.skip_minimize:
                create_image_minimizer(self.__isodir + "/LiveOS/osmin.img",
                                       self._image, self.compress_type)

            os_image = os.path.join('LiveOS', 'rootfs.img')
            if self.skip_compression:
                os_image = os.path.join(self.__isodir, os_image)
                shutil.move(self._image, os_image)
            else:
                if 'flatten-squashfs' in ops:
                    ops.remove('flatten-squashfs')
                    self._LoopImageCreator__instloop.mount('ro')
                    os_image = self._instroot
                else:
                    makedirs(os.path.join(
                                     os.path.dirname(self._image), "LiveOS"))
                    os_image = os.path.join(
                                       os.path.dirname(self._image), os_image)
                    shutil.move(self._image, os_image)
                    os_image = os.path.dirname(self._image)
                mksquashfs(os_image,
                           self.__isodir + "/LiveOS/squashfs.img",
                           self.compress_type, ops)
                self._LoopImageCreator__instloop.cleanup()

            self.__create_iso(self.__isodir)
        finally:
            shutil.rmtree(self.__isodir, ignore_errors = True)
            self.__isodir = None


class x86LiveImageCreator(LiveImageCreatorBase):
    """ImageCreator for x86 machines"""
    def __init__(self, *args, **kwargs):
        LiveImageCreatorBase.__init__(self, *args, **kwargs)
        self._efiarch = None

    def _get_xorrisofs_options(self, isodir):
        options = [ "-isohybrid-mbr", "/usr/share/syslinux/isohdpfx.bin",
                    "-eltorito-boot", "isolinux/isolinux.bin",
                    "-eltorito-catalog", "isolinux/boot.cat",
                    "-no-emul-boot", "-boot-info-table",
                    "-boot-load-size", "4" ]
        if os.path.exists(isodir + "/isolinux/efiboot.img"):
            options.extend([ "-eltorito-alt-boot",
                             "-e", "isolinux/efiboot.img",
                             "-no-emul-boot",
                             "-isohybrid-gpt-basdat", "-isohybrid-apm-hfsplus",
                             "-eltorito-alt-boot",
                             "-e", "isolinux/macboot.img",
                             "-no-emul-boot",
                             "-isohybrid-gpt-basdat", "-isohybrid-apm-hfsplus"])
        return options

    def _get_required_packages(self):
        return ["syslinux"] \
               + LiveImageCreatorBase._get_required_packages(self)

    def _get_isolinux_stanzas(self, isodir):
        return ""

    def __find_syslinux_menu(self):
        for menu in ("vesamenu.c32", "menu.c32"):
            for dir in ("/usr/lib/syslinux/", "/usr/share/syslinux/"):
                if os.path.isfile(self._instroot + dir + menu):
                    return menu

        raise CreatorError("syslinux not installed : "
                           "no suitable *menu.c32 found")

    def __find_syslinux_mboot(self):
        #
        # We only need the mboot module if we have any xen hypervisors
        #
        if not glob.glob(self._instroot + "/boot/xen.gz*"):
            return None

        return "mboot.c32"

    def __copy_syslinux_files(self, isodir, menu, mboot = None):
        files = ["isolinux.bin", "ldlinux.c32", "libcom32.c32", "libutil.c32", menu]
        if mboot:
            files += [mboot]

        for f in files:
            if os.path.exists(self._instroot + "/usr/lib/syslinux/" + f):
                path = self._instroot + "/usr/lib/syslinux/" + f
            elif os.path.exists(self._instroot + "/usr/share/syslinux/" + f):
                path = self._instroot + "/usr/share/syslinux/" + f
            if not os.path.isfile(path):
                raise CreatorError("syslinux not installed : "
                                   "%s not found" % path)

            shutil.copy(path, isodir + "/isolinux/")

    def __copy_syslinux_background(self, isodest):
        background_path = self._instroot + \
                          "/usr/share/anaconda/boot/syslinux-vesa-splash.jpg"

        if not os.path.exists(background_path):
            # fallback to F13 location
            background_path = self._instroot + \
                              "/usr/lib/anaconda-runtime/syslinux-vesa-splash.jpg"

            if not os.path.exists(background_path):
                return False

        shutil.copyfile(background_path, isodest)

        return True

    def __copy_kernel_and_initramfs(self, isodir, version, index):
        bootdir = self._instroot + "/boot"

        shutil.copyfile(bootdir + "/vmlinuz-" + version,
                        isodir + "/isolinux/vmlinuz" + index)

        isDracut = False
        if os.path.exists(self._instroot + "/usr/bin/dracut"):
            isDracut = True

        # FIXME: Implement a better check for how the initramfs is named...
        if os.path.exists(bootdir + "/initramfs-" + version + ".img"):
            shutil.copyfile(bootdir + "/initramfs-" + version + ".img",
                            isodir + "/isolinux/initrd" + index + ".img")
        elif os.path.exists(bootdir + "/initrd-" + version + ".img"):
            shutil.copyfile(bootdir + "/initrd-" + version + ".img",
                            isodir + "/isolinux/initrd" + index + ".img")
        elif not self.base_on:
            logging.error("No initramfs or initrd found for %s" % (version,))

        is_xen = False
        if os.path.exists(bootdir + "/xen.gz-" + version[:-3]):
            shutil.copyfile(bootdir + "/xen.gz-" + version[:-3],
                            isodir + "/isolinux/xen" + index + ".gz")
            is_xen = True

        return (is_xen, isDracut)

    def __is_default_kernel(self, kernel, kernels):
        if len(kernels) == 1:
            return True

        if kernel == self._default_kernel:
            return True

        if kernel.startswith(b"kernel-") and kernel[7:] == self._default_kernel:
            return True

        return False

    def __get_basic_syslinux_config(self, **args):
        return """
default %(menu)s
timeout %(timeout)d
menu background %(background)s
menu autoboot Starting %(title)s in # second{,s}. Press any key to interrupt.

menu clear
menu title %(title)s
menu vshift 8
menu rows 18
menu margin 8
#menu hidden
menu helpmsgrow 15
menu tabmsgrow 13

menu color border * #00000000 #00000000 none
menu color sel 0 #ffffffff #00000000 none
menu color title 0 #ff7ba3d0 #00000000 none
menu color tabmsg 0 #ff3a6496 #00000000 none
menu color unsel 0 #84b8ffff #00000000 none
menu color hotsel 0 #84b8ffff #00000000 none
menu color hotkey 0 #ffffffff #00000000 none
menu color help 0 #ffffffff #00000000 none
menu color scrollbar 0 #ffffffff #ff355594 none
menu color timeout 0 #ffffffff #00000000 none
menu color timeout_msg 0 #ffffffff #00000000 none
menu color cmdmark 0 #84b8ffff #00000000 none
menu color cmdline 0 #ffffffff #00000000 none

menu tabmsg Press Tab for full configuration options on menu items.
menu separator
""" % args

    def __get_image_stanza(self, is_xen, isDracut, **args):
        if isDracut:
            args["rootlabel"] = "live:CDLABEL=%(fslabel)s" % args
        else:
            args["rootlabel"] = "CDLABEL=%(fslabel)s" % args

        if not is_xen:
            template = """label %(short)s
  menu label %(long)s
  kernel vmlinuz%(index)s
  append initrd=initrd%(index)s.img root=%(rootlabel)s rootfstype=%(isofstype)s %(liveargs)s %(extra)s
"""
        else:
            template = """label %(short)s
  menu label %(long)s
  kernel mboot.c32
  append xen%(index)s.gz --- vmlinuz%(index)s root=%(rootlabel)s rootfstype=%(isofstype)s %(liveargs)s %(extra)s --- initrd%(index)s.img
"""
        if args.get("help"):
            template += """  text help
      %(help)s
  endtext
"""
        return template % args

    def __get_image_stanzas(self, isodir):
        kernels = self._get_kernel_versions()
        kernel_options = self._get_kernel_options()
        checkisomd5 = self._has_checkisomd5()

        # Stanzas for insertion into the config template
        linux = []
        basic = []
        check = []

        index = "0"
        for kernel, version in ((k,v) for k in kernels for v in kernels[k]):
            (is_xen, isDracut) = self.__copy_kernel_and_initramfs(isodir, version, index)
            if index == "0":
                self._isDracut = isDracut

            default = self.__is_default_kernel(kernel, kernels)

            if default:
                long = self.product
            elif kernel.startswith(b"kernel-"):
                long = "%s (%s)" % (self.product, kernel[7:])
            else:
                long = "%s (%s)" % (self.product, kernel)

            # tell dracut not to ask for LUKS passwords or activate mdraid sets
            if isDracut:
                kern_opts = kernel_options + " rd.luks=0 rd.md=0 rd.dm=0"
            else:
                kern_opts = kernel_options

            linux.append(self.__get_image_stanza(is_xen, isDracut,
                                           fslabel = self.fslabel,
                                           isofstype = "auto",
                                           liveargs = kern_opts,
                                           long = "^Start " + long,
                                           short = "linux" + index,
                                           extra = "",
                                           help = "",
                                           index = index))

            if default:
                linux[-1] += "  menu default\n"

            basic.append(self.__get_image_stanza(is_xen, isDracut,
                                           fslabel = self.fslabel,
                                           isofstype = "auto",
                                           liveargs = kern_opts,
                                           long = "Start " + long + " in ^basic graphics mode.",
                                           short = "basic" + index,
                                           extra = "nomodeset",
                                           help = "Try this option out if you're having trouble starting.",
                                           index = index))

            if checkisomd5:
                check.append(self.__get_image_stanza(is_xen, isDracut,
                                               fslabel = self.fslabel,
                                               isofstype = "auto",
                                               liveargs = kern_opts,
                                               long = "^Test this media & start " + long,
                                               short = "check" + index,
                                               extra = "rd.live.check",
                                               help = "",
                                               index = index))
            else:
                check.append(None)

            index = str(int(index) + 1)

        return (linux, basic, check)

    def __get_memtest_stanza(self, isodir):
        memtest = glob.glob(self._instroot + "/boot/memtest86*")
        if not memtest:
            return ""

        shutil.copyfile(memtest[0], isodir + "/isolinux/memtest")

        return """label memtest
  menu label Run a ^memory test.
  text help
    If your system is having issues, an problem with your 
    system's memory may be the cause. Use this utility to 
    see if the memory is working correctly.
  endtext
  kernel memtest
"""

    def __get_local_stanza(self, isodir):
        return """label local
  menu label Boot from ^local drive
  localboot 0xffff
"""

    def _configure_syslinux_bootloader(self, isodir):
        """configure the boot loader"""
        makedirs(isodir + "/isolinux")

        menu = self.__find_syslinux_menu()

        self.__copy_syslinux_files(isodir, menu,
                                   self.__find_syslinux_mboot())

        background = ""
        if self.__copy_syslinux_background(isodir + "/isolinux/splash.jpg"):
            background = "splash.jpg"

        cfg = self.__get_basic_syslinux_config(menu = menu,
                                               background = background,
                                               title = self.title,
                                               timeout = self._timeout * 10)
        cfg += "menu separator\n"

        linux, basic, check = self.__get_image_stanzas(isodir)
        # Add linux stanzas to main menu
        for s in linux:
            cfg += s
        cfg += "menu separator\n"

        cfg += """menu begin ^Troubleshooting
  menu title Troubleshooting
"""
        # Add basic video and check to submenu
        for b, c in zip(basic, check):
            cfg += b
            if c:
                cfg += c

        cfg += self.__get_memtest_stanza(isodir)
        cfg += "menu separator\n"

        cfg += self.__get_local_stanza(isodir)
        cfg += self._get_isolinux_stanzas(isodir)

        cfg += """menu separator
label returntomain
  menu label Return to ^main menu.
  menu exit
menu end
"""
        cfgf = open(isodir + "/isolinux/isolinux.cfg", "w")
        cfgf.write(cfg)
        cfgf.close()

    @property
    def efiarch(self):
        if not self._efiarch:
            # for most things, we want them named boot$efiarch
            efiarch = {"i386": "IA32", "x86_64": "X64"}
            self._efiarch = efiarch[dnf.rpm.basearch(hawkey.detect_arch())]
        return self._efiarch

    def __copy_efi_files(self, isodir):
        """ Copy the efi files into /EFI/BOOT/
            If any of them are missing, return False.
            requires:
              shim.efi
              gcdx64.efi
              fonts/unicode.pf2
        """
        fail = False
        files = [("/boot/efi/EFI/*/shim.efi", "/EFI/BOOT/BOOT%s.EFI" % (self.efiarch,), True),
                 ("/boot/efi/EFI/*/gcdx64.efi", "/EFI/BOOT/grubx64.efi", True),
                 ("/boot/efi/EFI/*/gcdia32.efi", "/EFI/BOOT/grubia32.efi", False),
                 ("/boot/efi/EFI/*/fonts/unicode.pf2", "/EFI/BOOT/fonts/", True),
                ]
        makedirs(isodir+"/EFI/BOOT/fonts/")
        for src, dest, required in files:
            src_glob = glob.glob(self._instroot+src)
            if not src_glob:
                if required:
                    logging.error("Missing EFI file (%s)" % (src,))
                    fail = True
            else:
                shutil.copy(src_glob[0], isodir+dest)
        return fail

    def __get_basic_efi_config(self, **args):
        return """
set default="1"

function load_video {
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod all_video
}

load_video
set gfxpayload=keep
insmod gzio
insmod part_gpt
insmod ext2

set timeout=%(timeout)d
### END /etc/grub.d/00_header ###

search --no-floppy --set=root -l '%(isolabel)s'

### BEGIN /etc/grub.d/10_linux ###
""" %args

    def __get_efi_image_stanza(self, **args):
        if self._isDracut:
            args["rootlabel"] = "live:LABEL=%(fslabel)s" % args
        else:
            args["rootlabel"] = "CDLABEL=%(fslabel)s" % args
        return """menuentry '%(long)s' --class fedora --class gnu-linux --class gnu --class os {
	linuxefi /isolinux/vmlinuz%(index)s root=%(rootlabel)s %(liveargs)s %(extra)s
	initrdefi /isolinux/initrd%(index)s.img
}
""" %args

    def __get_efi_image_stanzas(self, isodir, name):
        # FIXME: this only supports one kernel right now...

        kernel_options = self._get_kernel_options()
        checkisomd5 = self._has_checkisomd5()

        cfg = ""

        for index in range(0, 9):
            # we don't support xen kernels
            if os.path.exists("%s/EFI/BOOT/xen%d.gz" %(isodir, index)):
                continue
            cfg += self.__get_efi_image_stanza(fslabel = self.fslabel,
                                               liveargs = kernel_options,
                                               long = "Start " + self.product,
                                               extra = "", index = index)
            if checkisomd5:
                cfg += self.__get_efi_image_stanza(fslabel = self.fslabel,
                                                   liveargs = kernel_options,
                                                   long = "Test this media & start " + self.product,
                                                   extra = "rd.live.check",
                                                   index = index)
            cfg += """
submenu 'Troubleshooting -->' {
"""
            cfg += self.__get_efi_image_stanza(fslabel = self.fslabel,
                                               liveargs = kernel_options,
                                               long = "Start " + self.product + " in basic graphics mode",
                                               extra = "nomodeset", index = index)

            cfg+= """}
"""
            break

        return cfg

    def _configure_efi_bootloader(self, isodir):
        """Set up the configuration for an EFI bootloader"""
        if self.__copy_efi_files(isodir):
            shutil.rmtree(isodir + "/EFI")
            logging.warning("Failed to copy EFI files, no EFI Support will be included.")
            return

        cfg = self.__get_basic_efi_config(isolabel = self.fslabel,
                                          timeout = self._timeout)
        cfg += self.__get_efi_image_stanzas(isodir, self.name)

        cfgf = open(isodir + "/EFI/BOOT/grub.cfg", "w")
        cfgf.write(cfg)
        cfgf.close()

        # first gen mactel machines get the bootloader name wrong apparently
        if dnf.rpm.basearch(hawkey.detect_arch()) == "i386":
            os.link(isodir + "/EFI/BOOT/BOOT%s.EFI" % (self.efiarch),
                    isodir + "/EFI/BOOT/BOOT.EFI")


    def _configure_bootloader(self, isodir):
        self._configure_syslinux_bootloader(isodir)
        self._configure_efi_bootloader(isodir)

class ppcLiveImageCreator(LiveImageCreatorBase):
    def _get_xorrisofs_options(self, isodir):
        return [ "-hfsplus",
                 "-hfs-bless", isodir + "/ppc/mac"]

    def _get_required_packages(self):
        return ["yaboot"] + \
               LiveImageCreatorBase._get_required_packages(self)

    def _get_excluded_packages(self):
        # kind of hacky, but exclude memtest86+ on ppc so it can stay in cfg
        return ["memtest86+"] + \
               LiveImageCreatorBase._get_excluded_packages(self)

    def __copy_boot_file(self, destdir, file):
        for dir in [self._instroot+"/usr/share/ppc64-utils",
                    self._instroot+"/usr/lib/anaconda-runtime/boot",
                    "/usr/share/lorax/config_files/ppc"]:
            path = self._instroot + dir + "/" + file
            if not os.path.exists(path):
                continue

            makedirs(destdir)
            shutil.copy(path, destdir)
            return

        raise CreatorError("Unable to find boot file " + file)

    def __kernel_bits(self, kernel):
        testpath = (self._instroot + "/lib/modules/" +
                    kernel + "/kernel/arch/powerpc/platforms")

        if not os.path.exists(testpath):
            return { "32" : True, "64" : False }
        else:
            return { "32" : False, "64" : True }

    def __copy_kernel_and_initramfs(self, destdir, version):
        isDracut = False
        bootdir = self._instroot + "/boot"

        makedirs(destdir)

        shutil.copyfile(bootdir + "/vmlinuz-" + version,
                        destdir + "/vmlinuz")

        if os.path.exists(bootdir + "/initramfs-" + version + ".img"):
            shutil.copyfile(bootdir + "/initramfs-" + version + ".img",
                            destdir + "/initrd.img")
            isDracut = True
        else:
            shutil.copyfile(bootdir + "/initrd-" + version + ".img",
                            destdir + "/initrd.img")

        return isDracut

    def __get_basic_yaboot_config(self, **args):
        return """
init-message = "Welcome to %(name)s"
timeout=%(timeout)d
""" % args

    def __get_image_stanza(self, **args):
        if args["isDracut"]:
            args["rootlabel"] = "live:LABEL=%(fslabel)s" % args
        else:
            args["rootlabel"] = "CDLABEL=%(fslabel)s" % args
        return """

image=/ppc/ppc%(bit)s/vmlinuz
  label=%(short)s
  initrd=/ppc/ppc%(bit)s/initrd.img
  read-only
  append="root=%(rootlabel)s rootfstype=%(isofstype)s %(liveargs)s %(extra)s"
""" % args


    def __write_yaboot_config(self, isodir, bit, isDracut = False):
        cfg = self.__get_basic_yaboot_config(name = self.name,
                                             timeout = self._timeout * 100)

        kernel_options = self._get_kernel_options()

        cfg += self.__get_image_stanza(fslabel = self.fslabel,
                                       isofstype = "auto",
                                       short = "linux",
                                       long = "Run from image",
                                       extra = "",
                                       bit = bit,
                                       liveargs = kernel_options,
                                       isDracut = isDracut)

        if self._has_checkisomd5():
            cfg += self.__get_image_stanza(fslabel = self.fslabel,
                                           isofstype = "auto",
                                           short = "rd.live.check",
                                           long = "Verify and run from image",
                                           extra = "rd.live.check",
                                           bit = bit,
                                           liveargs = kernel_options,
                                           isDracut = isDracut)

        f = open(isodir + "/ppc/ppc" + bit + "/yaboot.conf", "w")
        f.write(cfg)
        f.close()

    def __write_not_supported(self, isodir, bit):
        makedirs(isodir + "/ppc/ppc" + bit)

        message = "Sorry, this LiveCD does not support your hardware"

        f = open(isodir + "/ppc/ppc" + bit + "/yaboot.conf", "w")
        f.write('init-message = "' + message + '"')
        f.close()


    def __write_dualbits_yaboot_config(isodir, **args):
        cfg = """
init-message = "\nWelcome to %(name)s!\nUse 'linux32' for 32-bit kernel.\n\n"
timeout=%(timeout)d
default=linux

image=/ppc/ppc64/vmlinuz
	label=linux64
	alias=linux
	initrd=/ppc/ppc64/initrd.img
	read-only

image=/ppc/ppc32/vmlinuz
	label=linux32
	initrd=/ppc/ppc32/initrd.img
	read-only
""" % args

        f = open(isodir + "/etc/yaboot.conf", "w")
        f.write(cfg)
        f.close()

    def _configure_bootloader(self, isodir):
        """configure the boot loader"""
        havekernel = { 32: False, 64: False }

        self.__copy_boot_file(isodir + "/ppc", "mapping")
        self.__copy_boot_file(isodir + "/ppc", "bootinfo.txt")
        self.__copy_boot_file(isodir + "/ppc/mac", "ofboot.b")

        shutil.copyfile(self._instroot + "/usr/lib/yaboot/yaboot",
                        isodir + "/ppc/mac/yaboot")

        makedirs(isodir + "/ppc/chrp")
        shutil.copyfile(self._instroot + "/usr/lib/yaboot/yaboot",
                        isodir + "/ppc/chrp/yaboot")

        subprocess.call(["addnote", isodir + "/ppc/chrp/yaboot"])

        #
        # FIXME: ppc should support multiple kernels too...
        #
        kernel = self._get_kernel_versions().values()[0][0]

        kernel_bits = self.__kernel_bits(kernel)

        for (bit, present) in kernel_bits.items():
            if not present:
                self.__write_not_supported(isodir, bit)
                continue

            isDracut = self.__copy_kernel_and_initramfs(isodir + "/ppc/ppc" + bit, kernel)
            self.__write_yaboot_config(isodir, bit, isDracut)

        makedirs(isodir + "/etc")
        if kernel_bits["32"] and not kernel_bits["64"]:
            shutil.copyfile(isodir + "/ppc/ppc32/yaboot.conf",
                            isodir + "/etc/yaboot.conf")
        elif kernel_bits["64"] and not kernel_bits["32"]:
            shutil.copyfile(isodir + "/ppc/ppc64/yaboot.conf",
                            isodir + "/etc/yaboot.conf")
        else:
            self.__write_dualbits_yaboot_config(isodir,
                                                name = self.name,
                                                timeout = self._timeout * 100)

        #
        # FIXME: build 'netboot' images with kernel+initrd, like mk-images.ppc
        #

class ppc64LiveImageCreator(ppcLiveImageCreator):
    def _get_excluded_packages(self):
        # FIXME:
        #   while kernel.ppc and kernel.ppc64 co-exist,
        #   we can't have both
        return ["kernel.ppc"] + \
               ppcLiveImageCreator._get_excluded_packages(self)

arch = dnf.rpm.basearch(hawkey.detect_arch())
if arch in ("i386", "x86_64"):
    LiveImageCreator = x86LiveImageCreator
elif arch in ("ppc",):
    LiveImageCreator = ppcLiveImageCreator
elif arch in ("ppc64",):
    LiveImageCreator = ppc64LiveImageCreator
elif arch.startswith(("arm", "aarch64")):
    LiveImageCreator = LiveImageCreatorBase
elif arch in ("riscv64",):
    LiveImageCreator = LiveImageCreatorBase
else:
    raise CreatorError("Architecture not supported!")
