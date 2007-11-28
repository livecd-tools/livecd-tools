#!/usr/bin/python -tt
#
# live.py : LiveImageCreator class for creating Live CD images
#
# Copyright 2007, Red Hat  Inc.
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

import os
import os.path
import glob
import shutil
import subprocess

from imgcreate.fs import *
from imgcreate.creator import *

class LiveImageCreatorBase(LoopImageCreator):
    def __init__(self, *args):
        LoopImageCreator.__init__(self, *args)
        self.skip_compression = False
        self.isobase = None

    def _baseOnIso(self, base_on):
        """helper function to extract ext3 file system from a live CD ISO"""

        isoloop = LoopbackMount(base_on, "%s/base_on_iso" %(self._builddir,))

        try:
            isoloop.mount()
        except MountError, e:
            raise InstallationError("Failed to loopback mount '%s' : %s" % (base_on, e))

        # legacy LiveOS filesystem layout support, remove for F9 or F10
        if os.path.exists("%s/LiveOS/squashfs.img" %(isoloop.mountdir,)):
            squashloop = LoopbackMount("%s/LiveOS/squashfs.img" %(isoloop.mountdir,),
                                       "%s/base_on_squashfs" %(self._builddir,),
                                       "squashfs")
        else:
            squashloop = LoopbackMount("%s/squashfs.img" %(isoloop.mountdir,),
                                       "%s/base_on_squashfs" %(self._builddir,),
                                       "squashfs")

        try:
            if not os.path.exists(squashloop.lofile):
                raise InstallationError("'%s' is not a valid live CD ISO : squashfs.img doesn't exist" % base_on)

            try:
                squashloop.mount()
            except MountError, e:
                raise InstallationError("Failed to loopback mount squashfs.img from '%s' : %s" % (base_on, e))

            # legacy LiveOS filesystem layout support, remove for F9 or F10
            if os.path.exists(self._builddir + "/base_on_squashfs/os.img"):
                os_image = self._builddir + "/base_on_squashfs/os.img"
            elif os.path.exists(self._builddir + "/base_on_squashfs/LiveOS/ext3fs.img"):
                os_image = self._builddir + "/base_on_squashfs/LiveOS/ext3fs.img"
            else:
                raise InstallationError("'%s' is not a valid live CD ISO : os.img doesn't exist" % base_on)

            shutil.copyfile(os_image, self._builddir + "/data/LiveOS/ext3fs.img")
        finally:
            # unmount and tear down the mount points and loop devices used
            squashloop.cleanup()
            isoloop.cleanup()

    def _mountInstallRoot(self):
        if self.isobase:
            self._baseOnIso(self.isobase)
        LoopImageCreator._mountInstallRoot(self)

    def _hasCheckIsoMD5(self):
        if os.path.exists("%s/usr/lib/anaconda-runtime/checkisomd5" %(self._instroot,)) or os.path.exists("%s/usr/bin/checkisomd5" %(self._instroot,)):
            return True
        return False

    def configBoot(self):
        """Configure the image so that it's bootable."""
        self._createInitramfs()
        self._configureBootloader()

    def _createInitramfs(self):
        mpath = "/usr/lib/livecd-creator/mayflower"

        # look to see if we're running from a git tree; in which case,
        # we should use the git mayflower too
        if globals().has_key("__file__") and \
           not os.path.abspath(__file__).startswith("/usr/bin"):
            f = os.path.join(os.path.abspath(os.path.dirname(__file__)),
                             "mayflower")
            if os.path.exists(f):
                mpath = f

        # Create initramfs
        if not os.path.isfile(mpath):
            raise InstallationError("livecd-creator not correctly installed : "+
                                    "/usr/lib/livecd-creator/mayflower not found")
        shutil.copy(mpath, "%s/sbin/mayflower" %(self._instroot,))
        # modules we want to support for booting
        mcfg = open(self._instroot + "/etc/mayflower.conf", "a")
        mcfg.write('MODULES+="squashfs ext3 ext2 vfat msdos "\n')
        mcfg.write('MODULES+="sr_mod sd_mod ide-cd "\n')

        if "=usb" in self._modules:
            mcfg.write('MODULES+="ehci_hcd uhci_hcd ohci_hcd usb_storage usbhid "\n')
            self._modules.remove("=usb")
        if "=firewire" in self._modules:
            mcfg.write('MODULES+="firewire-sbp2 firewire-ohci "\n')
            mcfg.write('MODULES+="sbp2 ohci1394 ieee1394 "\n')
            self._modules.remove("=firewire")
        mcfg.write('MODULES+="%s "\n' %(string.join(self._modules),))
        mcfg.close()

        map(lambda ver: subprocess.call(["/sbin/mayflower", "-f",
                                       "/boot/livecd-initramfs-%s.img" %(ver,), 
                                       ver], preexec_fn=self._rootRun),
            self.getKernelVersions().values())
        for f in ("/sbin/mayflower", "/etc/mayflower.conf"):
            os.unlink("%s/%s" %(self._instroot, f))

    def _configureBootloader(self):
        raise InstallationError("Bootloader configuration is arch-specific, but not implemented for this arch!")

    def _createIso(self):
        # WARNING: if you don't override this, your CD probably won't be
        # bootable
        rc = subprocess.call(["/usr/bin/mkisofs", "-o", "%s.iso" %(self.fsLabel,),
                         "-J", "-r", "-hide-rr-moved", "-hide-joliet-trans-tbl",
                         "-V", "%s" %(self.fsLabel,),
                         "%s/out" %(self._builddir)])

    def _implantIsoMD5(self):
        """Implant an isomd5sum."""
        if os.path.exists("/usr/bin/implantisomd5"):
            subprocess.call(["/usr/bin/implantisomd5",
                             "%s.iso" %(self.fsLabel,)])
        elif os.path.exists("/usr/lib/anaconda-runtime/implantisomd5"):
            subprocess.call(["/usr/lib/anaconda-runtime/implantisomd5",
                             "%s.iso" %(self.fsLabel,)])
        else:
            print >> sys.stderr, "isomd5sum not installed; not setting up mediacheck"

    def _createSquashFS(self):
        """create compressed squashfs file system"""
        if not self.skip_compression:
            ret = mksquashfs("out/LiveOS/squashfs.img", ["data"],
                             self._builddir)
            if ret != 0:
                raise InstallationError("mksquashfs exited with error (%d)" %(ret,))
        else:
            shutil.move("%s/data/LiveOS/ext3fs.img" %(self._builddir,),
                        "%s/out/LiveOS/ext3fs.img" %(self._builddir,))


    def package(self):
        LoopImageCreator.package(self)
        self._createSquashFS()
        self._createIso()
        self._implantIsoMD5()

class x86LiveImageCreator(LiveImageCreatorBase):
    """ImageCreator for x86 machines"""
    def _getImageStanza(self):
        return """label %(short)s
  menu label %(long)s
  kernel vmlinuz%(index)d
  append initrd=initrd%(index)d.img root=CDLABEL=%(label)s rootfstype=iso9660 %(liveargs)s %(extra)s
"""
    def _getImageStanzaXen(self):
        return """label %(short)s
  menu label %(long)s
  kernel mboot.c32
  append xen%(index)d.gz --- vmlinuz%(index)d --- initrd%(index)d.img  root=CDLABEL=%(label)s rootfstype=iso9660 %(liveargs)s %(extra)s
"""

    def _configureBootloader(self):
        """configure the boot loader"""
        os.makedirs(self._builddir + "/out/isolinux")

        syslinuxfiles = ["isolinux.bin"]
        menus = ["vesamenu.c32", "menu.c32"]
        syslinuxMenu = None

        for m in menus:
            path = "%s/usr/lib/syslinux/%s" % (self._instroot, m)
            if os.path.isfile(path):
                syslinuxfiles.append(m)
                syslinuxMenu=m
                break
        if syslinuxMenu is None:
            raise InstallationError("syslinux not installed : no suitable *menu.c32 found")

        # if we have any xen hypervisors, make sure we have the mboot module
        xen = glob.glob("%s/boot/xen.gz-*" %(self._instroot,))
        if len(xen) > 0:
            syslinuxfiles.append("mboot.c32")

        for p in syslinuxfiles:
            path = "%s/usr/lib/syslinux/%s" % (self._instroot, p)
            if not os.path.isfile(path):
                raise InstallationError("syslinux not installed : %s not found" % path)

            shutil.copy(path, "%s/out/isolinux/%s" % (self._builddir, p))

        if os.path.exists("%s/usr/lib/anaconda-runtime/syslinux-vesa-splash.jpg" %(self._instroot,)):
            shutil.copy("%s/usr/lib/anaconda-runtime/syslinux-vesa-splash.jpg" %(self._instroot,),
                        "%s/out/isolinux/splash.jpg" %(self._builddir,))
            have_background = "menu background splash.jpg"
        else:
            have_background = ""

        cfg = """
default %(menu)s
timeout %(timeout)d

%(background)s
menu title Welcome to %(label)s!
menu color border 0 #ffffffff #00000000
menu color sel 7 #ffffffff #ff000000
menu color title 0 #ffffffff #00000000
menu color tabmsg 0 #ffffffff #00000000
menu color unsel 0 #ffffffff #00000000
menu color hotsel 0 #ff000000 #ffffffff
menu color hotkey 7 #ffffffff #ff000000
menu color timeout_msg 0 #ffffffff #00000000
menu color timeout 0 #ffffffff #00000000
menu color cmdline 0 #ffffffff #00000000
menu hidden
menu hiddenrow 5
""" %{"menu" : syslinuxMenu, "label": self.fsLabel, "background" : have_background, "timeout": self._timeout * 10}

        stanzas = []
        count = 0
        for (name, ver) in self.getKernelVersions().items():
            shutil.copyfile("%s/boot/vmlinuz-%s"
                            %(self._instroot, ver),
                            "%s/out/isolinux/vmlinuz%d" %(self._builddir,count))
            shutil.copyfile("%s/boot/livecd-initramfs-%s.img"
                            %(self._instroot, ver),
                            "%s/out/isolinux/initrd%d.img" 
                            %(self._builddir, count))
            os.unlink("%s/boot/livecd-initramfs-%s.img" %(self._instroot, ver))

            isXen = False
            if os.path.exists("%s/boot/xen.gz-%s" %(self._instroot, ver[:-3])):
                shutil.copy("%s/boot/xen.gz-%s" %(self._instroot, ver[:-3]), 
                            "%s/out/isolinux/xen%d.gz" %(self._builddir, count))
                isXen = True

            default = False
            if (len(self.getKernelVersions().items()) == 1 or 
                name == self._defaultKernel or (name.startswith("kernel-") 
                              and name[7:] == self._defaultKernel)):
                default = True
                q = ""
            elif name.startswith("kernel-"):
                q = " (%s)" %(name[7:],)
            else:
                q = " (%s)" %(name,)


            if not isXen:
                s = self._getImageStanza()
            else:
                s = self._getImageStanzaXen()

            short = "linux%s" %(count,)
            long = "Boot %s%s" %(self.fsLabel,q)
            extra = ""

            cfg += s %{"label": self.fsLabel,
                       "short": short, "long": long, "extra": extra,
                       "liveargs": self._getKernelOptions(), "index": count}
            if default:
                cfg += "menu default\n"

            if self._hasCheckIsoMD5:
                short = "check%s" %(count,)
                long = "Verify and boot %s%s" %(self.fsLabel,q)
                extra = "check"
                cfg += s %{"label": self.fsLabel,
                           "short": short, "long": long, "extra": extra,
                           "liveargs": self._getKernelOptions(), "index": count}

            count += 1

        memtest = glob.glob("%s/boot/memtest86*" %(self._instroot,))
        if len(memtest) > 0:
            shutil.copy(memtest[0], "%s/out/isolinux/memtest" %(self._builddir,))
            cfg += """label memtest
  menu label Memory Test
  kernel memtest
"""

        # add local boot
        cfg += """label local
  menu label Boot from local drive
  localboot 0xffff
"""

        cfgf = open("%s/out/isolinux/isolinux.cfg" %(self._builddir,), "w")
        cfgf.write(cfg)
        cfgf.close()
        
        # TODO: enable external entitity to partipate in adding boot entries

    def _createIso(self):
        """Write out the live CD ISO."""
        rc = subprocess.call(["/usr/bin/mkisofs", "-o", "%s.iso" %(self.fsLabel,),
                         "-b", "isolinux/isolinux.bin",
                         "-c", "isolinux/boot.cat",
                         "-no-emul-boot", "-boot-load-size", "4",
                         "-boot-info-table",
                         "-J", "-r", "-hide-rr-moved", "-hide-joliet-trans-tbl",
                         "-V", "%s" %(self.fsLabel,),
                         "%s/out" %(self._builddir)])
        if rc != 0:
            raise InstallationError("ISO creation failed!")

    def _getRequiredPackages(self):
        ret = ["syslinux"]
        ret.extend(ImageCreatorBase._getRequiredPackages(self))
        return ret

class ppcLiveImageCreator(ImageCreatorBase):
    def _createIso(self):
        """write out the live CD ISO"""
        rc = subprocess.call(["/usr/bin/mkisofs", "-o", "%s.iso" %(self.fsLabel,),
                         "-hfs", "-hfs-bless", "%s/out/ppc/mac" %(self._builddir),
                         "-hfs-volid", "%s" %(self.fsLabel,), "-part",
                         "-map", "%s/out/ppc/mapping" %(self._builddir,),
                         "-J", "-r", "-hide-rr-moved", "-no-desktop",
                         "-V", "%s" %(self.fsLabel,), "%s/out" %(self._builddir)])
        if rc != 0:
            raise InstallationError("ISO creation failed!")

    def _copyBootFile(self, file, dest):
        # get the file from either anaconda-runtime or ppc64-utils
        if os.path.exists("%s/usr/share/ppc64-utils/%s" %(self._instroot, file)):
            shutil.copyfile("%s/usr/share/ppc64-utils/%s"
                            %(self._instroot, file), dest)
        elif os.path.exists("%s/usr/lib/anaconda-runtime/boot/%s" %(self._instroot, file)):
            shutil.copyfile("%s/usr/lib/anaconda-runtime/boot/%s"
                            %(self._instroot, file), dest)
        else:
            raise InstallationError("Unable to find boot file %s" %(file,))

    def _configureBootloader(self):
        """configure the boot loader"""
        havekernel = { 32: False, 64: False }

        os.makedirs(self._builddir + "/out/ppc")

        # copy the mapping file to somewhere we can get to it later
        self._copyBootFile("mapping", "%s/out/ppc/mapping" %(self._builddir,))

        # Copy yaboot and ofboot.b in to mac directory
        os.makedirs(self._builddir + "/out/ppc/mac")
        self._copyBootFile("ofboot.b", "%s/out/ppc/mac/ofboot.b" %(self._builddir,))
        shutil.copyfile("%s/usr/lib/yaboot/yaboot" %(self._instroot),
                        "%s/out/ppc/mac/yaboot" %(self._builddir,))

        # Copy yaboot and ofboot.b in to chrp directory
        os.makedirs(self._builddir + "/out/ppc/chrp")
        self._copyBootFile("bootinfo.txt", "%s/out/ppc/bootinfo.txt" %(self._builddir,))
        shutil.copyfile("%s/usr/lib/yaboot/yaboot" %(self._instroot),
                        "%s/out/ppc/chrp/yaboot" %(self._builddir,))
        subprocess.call(["/usr/sbin/addnote", "%s/out/ppc/chrp/yaboot" %(self._builddir,)])

        # FIXME: ppc should support multiple kernels too...
        ver = self.getKernelVersions().values()[0]

        os.makedirs(self._builddir + "/out/ppc/ppc32")
        if not os.path.exists("%s/lib/modules/%s/kernel/arch/powerpc/platforms" %(self._instroot, ver)):
            havekernel[32] = True
            shutil.copyfile("%s/boot/vmlinuz-%s" %(self._instroot, ver),
                            "%s/out/ppc/ppc32/vmlinuz" %(self._builddir,))
            shutil.copyfile("%s/boot/livecd-initramfs-%s.img" %(self._instroot, ver),
                            "%s/out/ppc/ppc32/initrd.img" %(self._builddir,))
            os.unlink("%s/boot/livecd-initramfs-%s.img" %(self._instroot, ver))

        os.makedirs(self._builddir + "/out/ppc/ppc64")
        if os.path.exists("%s/lib/modules/%s/kernel/arch/powerpc/platforms" %(self._instroot, ver)):
            havekernel[64] = True
            shutil.copyfile("%s/boot/vmlinuz-%s" %(self._instroot, ver),
                            "%s/out/ppc/ppc64/vmlinuz" %(self._builddir,))
            shutil.copyfile("%s/boot/livecd-initramfs-%s.img" %(self._instroot, ver),
                            "%s/out/ppc/ppc64/initrd.img" %(self._builddir,))
            os.unlink("%s/boot/livecd-initramfs-%s.img" %(self._instroot, ver))

        for bit in havekernel.keys():
            cfg = """
init-message = "Welcome to %(label)s"
timeout=%(timeout)d

""" %{"label": self.fsLabel, "timeout": self._timeout * 100}

            stanzas = [("linux", "Run from image", "")]
            if self._hasCheckIsoMD5():
                stanzas.append( ("check", "Verify and run from image", "check") )

            for (short, long, extra) in stanzas:
                cfg += """

image=/ppc/ppc%(bit)s/vmlinuz
  label=%(short)s
  initrd=/ppc/ppc%(bit)s/initrd.img
  read-only
  append="root=CDLABEL=%(label)s rootfstype=iso9660 %(liveargs)s %(extra)s"
""" %{"label": self.fsLabel, "short": short, "long": long, "extra": extra, "bit": bit, "liveargs": self._getKernelOptions()}

                if havekernel[bit]:
                    cfgf = open("%s/out/ppc/ppc%d/yaboot.conf" %(self._builddir, bit), "w")
                    cfgf.write(cfg)
                    cfgf.close()
                else:
                    cfgf = open("%s/out/ppc/ppc%d/yaboot.conf" %(self._builddir, bit), "w")
                    cfgf.write('init-message = "Sorry, this LiveCD does not support your hardware"')
                    cfgf.close()


        os.makedirs(self._builddir + "/out/etc")
        if havekernel[32] and not havekernel[64]:
            shutil.copyfile("%s/out/ppc/ppc32/yaboot.conf" %(self._builddir,),
                            "%s/out/etc/yaboot.conf" %(self._builddir,))
        elif havekernel[64] and not havekernel[32]:
            shutil.copyfile("%s/out/ppc/ppc64/yaboot.conf" %(self._builddir,),
                            "%s/out/etc/yaboot.conf" %(self._builddir,))
        else:
            cfg = """
init-message = "\nWelcome to %(label)s!\nUse 'linux32' for 32-bit kernel.\n\n"
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
""" %{"label": self.fsLabel, "timeout": self._timeout * 100}

            cfgf = open("%s/out/etc/yaboot.conf" %(self._builddir,), "w")
            cfgf.write(cfg)
            cfgf.close()

        # TODO: build 'netboot' images with kernel+initrd, like mk-images.ppc

    def _getRequiredPackages(self):
        ret = ["yaboot"]
        ret.extend(ImageCreatorBase._getRequiredPackages(self))
        return ret

    def _getRequiredExcludePackages(self):
        # kind of hacky, but exclude memtest86+ on ppc so it can stay in cfg
        return ["memtest86+"]

class ppc64LiveImageCreator(ppcLiveImageCreator):
    def _getRequiredExcludePackages(self):
        # FIXME: while kernel.ppc and kernel.ppc64 co-exist, we can't
        # have both
        return ["kernel.ppc", "memtest86+"]

arch = rpmUtils.arch.getBaseArch()
if arch in ("i386", "x86_64"):
    LiveImageCreator = x86LiveImageCreator
elif arch in ("ppc",):
    LiveImageCreator = ppcLiveImageCreator
elif arch in ("ppc64",):
    LiveImageCreator = ppc64LiveImageCreator(fs_label)
else:
    raise InstallationError("Architecture not supported!")
