#!/usr/bin/python -tt
#
# creator.py : ImageCreatorBase and LoopImageCreator base classes
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
import stat
import sys
import tempfile
import shutil

import yum
import rpm
import pykickstart.commands
import pykickstart.constants
import pykickstart.parser

from imgcreate.fs import *
from imgcreate.kickstart import *
from imgcreate.yuminst import *

class InstallationError(Exception):
    def __init__(self, msg):
        Exception.__init__(self, msg)

class ImageCreatorBase(object):
    def __init__(self, ks, fsLabel):
        self.ks = ks
        self.fsLabel = fsLabel
        self.tmpdir = "/var/tmp"

        self.__ayum = None
        self._builddir = None
        self._bindmounts = []

        # defaults to allow some kickstart options to not be specified
        self._modules = ["=ata","sym53c8xx","aic7xxx","=usb","=firewire"]
        self._timeout = 10
        self._defaultKernel = "kernel"
        self._imageSizeMB = 4096
        self.__setDefaultsFromKS()
        self.__sanityCheckKS()

    def __del__(self):
        self.teardown()

    def create(self):
        """This is the simplest method to generate an image from the given
        configuration."""
        self.mountImage()
        self.installPackages()
        self.configureImage()
        self.unmountImage()
        self.package()

    def _getRequiredPackages(self):
        return []
    def _getRequiredExcludePackages(self):
        return []

    def _get_instroot(self):
        return "%s/install_root" %(self._builddir,)
    _instroot = property(_get_instroot)

    def _getKernelOptions(self):
        r = "ro quiet liveimg"
        if os.path.exists("%s/usr/bin/rhgb" %(self._instroot,)):
            r += " rhgb"
        return r
        
    def __setDefaultsFromKS(self):
        """Set up some options based on the config."""
        # image size
        for p in self.ks.handler.partition.partitions:
            if p.mountpoint == "/" and p.size:
                self._imageSizeMB = int(p.size)

        # modules for initramfs
        if isinstance(self.ks.handler.device, pykickstart.commands.device.FC3_Device):
            if self.ks.handler.device.moduleName:
                self._modules = self.ks.handler.device.moduleName.split(":")
        elif len(self.ks.handler.device.deviceList) > 0:
            map(lambda x: self._modules.extend(x.moduleName.split(":")),
                self.ks.handler.device.deviceList)

        # bootloader defaults
        if hasattr(self.ks.handler.bootloader, "timeout") and self.ks.handler.bootloader.timeout is not None:
            self._timeout = int(self.ks.handler.bootloader.timeout)
        if hasattr(self.ks.handler.bootloader, "default") and self.ks.handler.bootloader.default:
            self._defaultKernel = self.ks.handler.bootloader.default

        # if there's a method specified; turn it into a repo definition
        try:
            self.ks.handler.repo.methodToRepo()
        except:
            pass


    def __sanityCheckKS(self):
        """Ensure that the config we've been given is sane."""
        if len(self.ks.handler.packages.packageList) == 0 and len(self.ks.handler.packages.groupList) == 0:
            raise InstallationError("No packages or groups specified")

        if not self.ks.handler.repo.repoList:
            raise InstallationError("No repositories specified")

        if self.ks.handler.selinux.selinux and not \
               os.path.exists("/selinux/enforce"):
            raise InstallationError("SELinux requested but not enabled on host system")

    def getFstabContents(self):
        contents =  "/dev/root               /                       ext3    defaults,noatime 0 0\n"
        contents += "devpts                  /dev/pts                devpts  gid=5,mode=620  0 0\n"
        contents += "tmpfs                   /dev/shm                tmpfs   defaults        0 0\n"
        contents += "proc                    /proc                   proc    defaults        0 0\n"
        contents += "sysfs                   /sys                    sysfs   defaults        0 0\n"
        return contents

    def __writeFstab(self):
        fstab = open(self._builddir + "/install_root/etc/fstab", "w")
        fstab.write(self.getFstabContents())
        fstab.close()

    def _mountInstallRoot(self):
        """Do any creation necessary and mount the install root"""
        # IMAGE-SPECIFIC-IMPLEMENT
        raise RuntimeError, "I shouldn't ever get here."

    def _unmountInstallRoot(self):
        """Tear down the install root."""
        # IMAGE-SPECIFIC-IMPLEMENT
        raise RuntimeError, "I shouldn't ever get here."

    def _doBindMounts(self):
        for b in self._bindmounts:
            b.mount()

    def _undoBindMounts(self):
        self._bindmounts.reverse()
        for b in self._bindmounts:
            b.umount()

    def mountImage(self, cachedir = None):
        """setup target ext3 file system in preparation for an install"""

        # setup temporary build dirs
        try:
            self._builddir = tempfile.mkdtemp(dir=self.tmpdir, prefix="livecd-creator-")
        except OSError, (err, msg):
            raise InstallationError("Failed create build directory in %s: %s" % (self.tmpdir, msg))

        os.makedirs(self._builddir + "/install_root")
        os.makedirs(self._builddir + "/data")
        os.makedirs(self._builddir + "/out")

        self._mountInstallRoot()

        # create a few directories that have to exist
        for d in ("/etc", "/boot", "/var/log", "/var/cache/yum"):
            makedirs("%s/%s" %(self._instroot,d))

        cachesrc = (cachedir or self._builddir) + "/yum-cache"
        makedirs(cachesrc)

        for (f, dest) in [("/sys", None), ("/proc", None), ("/dev", None),
                          ("/dev/pts", None), ("/selinux", None),
                          (cachesrc, "/var/cache/yum")]:
            self._bindmounts.append(BindChrootMount(f, self._builddir + "/install_root", dest))

        self._doBindMounts()

        # make sure /etc/mtab is current inside install_root
        os.symlink("../proc/mounts", self._instroot + "/etc/mtab")

        self.__writeFstab()

    def unmountImage(self):
        """detaches system bind mounts and install_root for the file system and tears down loop devices used"""
        if self.__ayum:
            self.__ayum.close()
            self.__ayum = None

        try:
            os.unlink(self._builddir + "/install_root/etc/mtab")
        except OSError:
            pass

        self._undoBindMounts()

        self._unmountInstallRoot()

    def teardown(self):
        if self._builddir:
            self.unmountImage()
            shutil.rmtree(self._builddir, ignore_errors = True)
            self._builddir = None

    def _rootRun(self):
        os.chroot(self._instroot)
        os.chdir("/")

    def installPackages(self, repoUrls = {}):
        """Install packages into install_root"""

        self.__ayum = LiveCDYum()
        self.__ayum.setup(self._builddir + "/data",
                        self._builddir + "/install_root")

        for repo in self.ks.handler.repo.repoList:
            if repo.name in repoUrls:
                baseurl = repoUrls[repo.name]
                mirrorlist = None
            else:
                baseurl = repo.baseurl
                mirrorlist = repo.mirrorlist
            yr = self.__ayum.addRepository(repo.name, baseurl, mirrorlist)
            if hasattr(repo, "includepkgs"):
                yr.includepkgs = repo.includepkgs
            if hasattr(repo, "excludepkgs"):
                yr.exclude = repo.excludepkgs

        if self.ks.handler.packages.excludeDocs:
            rpm.addMacro("_excludedocs","1")

        try:
            try:
                for pkg in (self.ks.handler.packages.packageList + self._getRequiredPackages()):
                    try:
                        self.__ayum.selectPackage(pkg)
                    except yum.Errors.InstallError, e:
                        if self.ks.handler.packages.handleMissing != \
                               pykickstart.constants.KS_MISSING_IGNORE:
                            raise InstallationError("Failed to find package '%s' : %s" % (pkg, e))
                        else:
                            print >> sys.stderr, "Unable to find package '%s'; skipping" %(pkg,)

                for group in self.ks.handler.packages.groupList:
                    try:
                        self.__ayum.selectGroup(group.name, group.include)
                    except (yum.Errors.InstallError, yum.Errors.GroupsError), e:
                        if self.ks.handler.packages.handleMissing != \
                               pykickstart.constants.KS_MISSING_IGNORE:
                            raise InstallationError("Failed to find group '%s' : %s" % (group.name, e))
                        else:
                            print >> sys.stderr, "Unable to find group '%s'; skipping" %(group.name,)

                map(lambda pkg: self.__ayum.deselectPackage(pkg),
                    self.ks.handler.packages.excludedList +
                    self._getRequiredExcludePackages())

                self.__ayum.runInstall()
            except yum.Errors.RepoError, e:
                raise InstallationError("Unable to download from repo : %s" %(e,))
            except yum.Errors.YumBaseError, e:
                raise InstallationError("Unable to install: %s" %(e,))
        finally:
            self.__ayum.closeRpmDB()

        # do some clean up to avoid lvm info leakage.  this sucks.
        for subdir in ("cache", "backup", "archive"):
            try:
                for f in os.listdir("%s/etc/lvm/%s" %(self._instroot, subdir)):
                    os.unlink("%s/etc/lvm/%s/%s" %(self._instroot, subdir, f))
            except:
                pass

    def _configureImage(self):
        # FIXME: this is a bit ugly, but with the current pykickstart
        # API, we don't really have a lot of choice.  it'd be nice to
        # be able to do something different, but so it goes

        # set up the language
        lang = self.ks.handler.lang.lang or "en_US.UTF-8"
        f = open("%s/etc/sysconfig/i18n" %(self._instroot,), "w+")
        f.write("LANG=\"%s\"\n" %(lang,))
        f.close()

        # next, the keyboard
        # FIXME: should this impact the X keyboard config too???
        # or do we want to make X be able to do this mapping
        import rhpl.keyboard
        k = rhpl.keyboard.Keyboard()
        if self.ks.handler.keyboard.keyboard:
            k.set(self.ks.handler.keyboard.keyboard)
        k.write(self._instroot)

        # next up is timezone
        tz = self.ks.handler.timezone.timezone or "America/New_York"
        utc = self.ks.handler.timezone.isUtc
        f = open("%s/etc/sysconfig/clock" %(self._instroot,), "w+")
        f.write("ZONE=\"%s\"\n" %(tz,))
        f.write("UTC=%s\n" %(utc,))
        f.close()

        # do any authconfig bits
        auth = self.ks.handler.authconfig.authconfig or "--useshadow --enablemd5"
        if os.path.exists("%s/usr/sbin/authconfig" %(self._instroot,)):
            args = ["/usr/sbin/authconfig", "--update", "--nostart"]
            args.extend(auth.split())
            subprocess.call(args, preexec_fn=self._rootRun)

        # firewall.  FIXME: should handle the rest of the options
        if self.ks.handler.firewall.enabled and os.path.exists("%s/usr/sbin/lokkit" %(self._instroot,)):
            subprocess.call(["/usr/sbin/lokkit", "-f", "--quiet",
                             "--nostart", "--enabled"],
                            preexec_fn=self._rootRun)

        # selinux
        if os.path.exists("%s/usr/sbin/lokkit" %(self._instroot,)):
            args = ["/usr/sbin/lokkit", "-f", "--quiet", "--nostart"]
            if self.ks.handler.selinux.selinux:
                args.append("--selinux=enforcing")
            else:
                args.append("--selinux=disabled")
            subprocess.call(args, preexec_fn=self._rootRun)

        # Set the root password
        if self.ks.handler.rootpw.isCrypted:
            subprocess.call(["/usr/sbin/usermod", "-p", self.ks.handler.rootpw.password, "root"], preexec_fn=self._rootRun)
        elif self.ks.handler.rootpw.password == "":
            # Root password is not set and not crypted, empty it
            subprocess.call(["/usr/bin/passwd", "-d", "root"], preexec_fn=self._rootRun)
        else:
            # Root password is set and not crypted
            p1 = subprocess.Popen(["/bin/echo", self.ks.handler.rootpw.password], stdout=subprocess.PIPE, preexec_fn=self._rootRun)
            p2 = subprocess.Popen(["/usr/bin/passwd", "--stdin", "root"], stdin=p1.stdout, stdout=subprocess.PIPE, preexec_fn=self._rootRun)
            output = p2.communicate()[0]

        # enable/disable services appropriately
        if os.path.exists("%s/sbin/chkconfig" %(self._instroot,)):
            for s in self.ks.handler.services.enabled:
                subprocess.call(["/sbin/chkconfig", s, "on"],
                                preexec_fn=self._rootRun)
            for s in self.ks.handler.services.disabled:
                subprocess.call(["/sbin/chkconfig", s, "off"],
                                preexec_fn=self._rootRun)

        # x by default?
        if self.ks.handler.xconfig.startX:
            f = open("%s/etc/inittab" %(self._instroot,), "rw+")
            buf = f.read()
            buf = buf.replace("id:3:initdefault", "id:5:initdefault")
            f.seek(0)
            f.write(buf)
            f.close()

        # touch some files which get unhappy if they're not labeled correctly
        for fn in ("/etc/modprobe.conf", "/etc/resolv.conf"):
            path = self._instroot + fn
            f = file(path, "w+")
            os.chmod(path, 0644)

    def runPost(self, env = {}):
        # and now, for arbitrary %post scripts
        for s in filter(lambda s: s.type == pykickstart.parser.KS_SCRIPT_POST,
                        self.ks.handler.scripts):
            (fd, path) = tempfile.mkstemp("", "ks-script-", "%s/tmp" %(self._instroot,))
            os.write(fd, s.script)
            os.close(fd)
            os.chmod(path, 0700)

            if not s.inChroot:
                env["BUILD_DIR"] = self._builddir,
                env["INSTALL_ROOT"] = self._instroot
                env["LIVE_ROOT"] = "%s/out" %(self._builddir,)
                preexec = lambda: os.chdir(self._builddir,)
                script = path
            else:
                preexec = self._rootRun
                script = "/tmp/%s" %(os.path.basename(path),)

            try:
                subprocess.call([s.interp, script],
                                preexec_fn = preexec, env = env)
            except OSError, (err, msg):
                os.unlink(path)
                raise InstallationError("Failed to execute %%post script with '%s' : %s" % (s.interp, msg))
            os.unlink(path)

    def getKernelVersions(self):
        # find the kernel versions.  this iterates over everything providing
        # 'kernel' and finds /boot/vmlinuz-* and grabbing the version based
        # on the filename being /boot/vmlinuz-version
        ts = rpm.TransactionSet(self._instroot)
        mi = ts.dbMatch('provides', 'kernel')
        ret = {}
        for h in mi:
            name = h['name']
            for f in h['filenames']:
                if f.startswith("/boot/vmlinuz-"):
                    ret[name] = f[14:]
        return ret

    def __relabelSystem(self):
        # finally relabel all files
        if self.ks.handler.selinux.selinux:
            if os.path.exists("%s/sbin/restorecon" %(self._instroot,)):
                subprocess.call(["/sbin/restorecon", "-l", "-v", "-r", "/"],
                                preexec_fn=self._rootRun)

    def launchShell(self):
        subprocess.call(["/bin/bash"], preexec_fn=self._rootRun)

    def configureImage(self):
        try:
            self._configureImage()
        except Exception, e: #FIXME: we should be a little bit more fine-grained
            raise InstallationError("Error configuring live image: %s" %(e,))
        net = ImageNetworkConfig(self.ks.handler.network, self._instroot)
        net.write()
        self.__relabelSystem()

        self.configBoot()

        self.runPost()

    def configBoot(self):
        """Configure the image so that it's bootable."""
        # IMAGE-SPECIFIC-IMPLEMENT
        print >> sys.stderr, "Nothing to do to make a generic image bootable"

    def package(self):
        """Create a nice package for delivery of the image."""
        # IMAGE-SPECIFIC-IMPLEMENT
        print >> sys.stderr, "Nothing to do to make a generic image packaged"

class LoopImageCreator(ImageCreatorBase):
    def __init__(self, *args):
        ImageCreatorBase.__init__(self, *args)
        self.__minsizeKB = 0
        self.__blocksize = 4096

        self._instloop = None
        self._imgbase = None

    def _get_blocksize(self):
        return self.__blocksize
    def _set_blocksize(self, val):
        if self._instloop:
            raise InstallationError("_blocksize must be set before calling mountImage()")
        try:
            self.__blocksize = int(val)
        except ValueError:
            raise InstallationError("'%s' is not a valid integer value for _blocksize" % val)
    _blocksize = property(_get_blocksize, _set_blocksize)

    def _mountInstallRoot(self):
        """Do any creation necessary and mount the install root"""
        if self._imgbase:
            shutil.copyfile(self._imgbase,
                            "%s/data/LiveOS/ext3fs.img" %(self._builddir,))

        self._instloop = SparseExt3LoopbackMount("%s/data/LiveOS/ext3fs.img"
                                                %(self._builddir,),
                                                self._instroot,
                                                self._imageSizeMB * 1024L * 1024L,
                                                self.__blocksize,
                                                self.fsLabel)

        try:
            self._instloop.mount()
        except MountError, e:
            raise InstallationError("Failed to loopback mount '%s' : %s" % (self.instloop.lofile, e))

    def _unmountInstallRoot(self):
        if self._instloop:
            self._instloop.cleanup()
            self._instloop = None

    def __resize2fs(self, image, n_blocks):
        dev_null = os.open("/dev/null", os.O_WRONLY)
        try:
            return subprocess.call(["/sbin/resize2fs", image, str(n_blocks)],
                                   stdout = dev_null,
                                   stderr = dev_null)
        finally:
            os.close(dev_null)

    # resize2fs doesn't have any kind of minimal setting, so use
    # a binary search to get it to minimal size.
    def _resize2fsToMinimal(self, image):
        def parseField(output, field):
            for line in output.split("\n"):
                if line.startswith(field + ":"):
                    return line[len(field) + 1:].strip()

            raise KeyError("Failed to find field '%s' in output" % field)

        bot = 0

        output = subprocess.Popen(['/sbin/dumpe2fs', '-h', image],
                                  stdout=subprocess.PIPE,
                                  stderr=open('/dev/null', 'w')
                                  ).communicate()[0]
        top = int(parseField(output, "Block count"))

        while top != (bot + 1):
            t = bot + ((top - bot) / 2)

            if not self.__resize2fs(image, t):
                top = t
            else:
                bot = t

        return top

    # cleanupDeleted removes unused data from the sparse ext3 os image file.
    # The process involves: resize2fs-to-minimal, truncation,
    # resize2fs-to-uncompressed-size (with implicit resparsification)
    def cleanupDeleted(self, imageSizeMB = None):
        image = "%s/data/LiveOS/ext3fs.img" %(self._builddir,)

        subprocess.call(["/sbin/e2fsck", "-f", "-y", image])

        if imageSizeMB is None:
            n_blocks = os.stat(image)[stat.ST_SIZE] / self.__blocksize
        else:
            n_blocks = imageSizeMB * 1024 / self.__blocksize

        min_blocks = self._resize2fsToMinimal(image)

        # truncate the unused excess portion of the sparse file
        fd = os.open(image, os.O_WRONLY )
        os.ftruncate(fd, min_blocks * self.__blocksize)
        os.close(fd)

        self.__minsizeKB = min_blocks * self.__blocksize / 1024L
        print >> sys.stderr, "Installation target minimized to %dK" % (self.__minsizeKB)

        self.__resize2fs(image, n_blocks)


    # genMinInstDelta: generates an osmin overlay file to sit alongside
    #                  ext3fs.img.  liveinst may then detect the existence of
    #                  osmin, and use it to create a minimized ext3fs.img
    #                  which can be installed more quickly, and to smaller
    #                  destination volumes.
    def genMinInstDelta(self):
        # create the sparse file for the minimized overlay
        fd = os.open("%s/out/LiveOS/osmin" %(self._builddir,),
                     os.O_WRONLY | os.O_CREAT)
        off = long(64L * 1024L * 1024L)
        os.lseek(fd, off, 0)
        os.write(fd, '\x00')
        os.close(fd)

        # associate os image with loop device
        osloop = LoopbackMount("%s/data/LiveOS/ext3fs.img" %(self._builddir,), \
                               "None")

        # associate overlay with loop device
        minloop = LoopbackMount("%s/out/LiveOS/osmin" %(self._builddir,), \
                                "None")

        try:
            osloop.loopsetup()
            minloop.loopsetup()

            # create a snapshot device
            rc = subprocess.call(["/sbin/dmsetup",
                                  "--table",
                                  "0 %d snapshot %s %s p 8"
                                  %(self._imageSizeMB * 1024L * 2L,
                                    osloop.loopdev, minloop.loopdev),
                                  "create",
                                  "livecd-creator-%d" %(os.getpid(),) ])
            if rc != 0:
                raise InstallationError("Could not create genMinInstDelta snapshot device")

            try:
                # resize snapshot device back to minimal (self.__minsizeKB)
                rc = self.__resize2fs("/dev/mapper/livecd-creator-%d" %(os.getpid(),),
                                      "%dK" %(self.__minsizeKB,))
                if rc != 0:
                    raise InstallationError("Could not shrink ext3fs image")

                # calculate how much delta data to keep
                dmsetupOutput = subprocess.Popen(['/sbin/dmsetup', 'status',
                                                  "livecd-creator-%d" %(os.getpid(),)],
                                                 stdout=subprocess.PIPE,
                                                 stderr=open('/dev/null', 'w')
                                                 ).communicate()[0]

                # The format for dmsetup status on a snapshot device that we are
                # counting on here is as follows.
                # e.g. "0 8388608 snapshot 416/1048576" or "A B snapshot C/D"
                try:
                    minInstDeltaDataLength = int((dmsetupOutput.split()[3]).split('/')[0])
                    print >> sys.stderr, "genMinInstDelta data length is %d 512 byte sectors" % (minInstDeltaDataLength)
                except ValueError:
                    raise InstallationError("Could not calculate amount of data used by genMinInstDelta")
            finally:
                # tear down snapshot and loop devices
                rc = subprocess.call(["/sbin/dmsetup", "remove",
                                      "livecd-creator-%d" %(os.getpid(),) ])
                if rc != 0 and not sys.exc_info()[0]:
                    raise InstallationError("Could not remove genMinInstDelta snapshot device")
        finally:
            osloop.cleanup()
            minloop.cleanup()

        # truncate the unused excess portion of the sparse file
        fd = os.open("%s/out/LiveOS/osmin" %(self._builddir,), os.O_WRONLY )
        os.ftruncate(fd, minInstDeltaDataLength * 512)
        os.close(fd)

        ret = mksquashfs("osmin.img", ["osmin"],
                         "%s/out/LiveOS" %(self._builddir,))
        if ret != 0:
                raise InstallationError("mksquashfs exited with error (%d)" %(ret,))
        try:
            os.unlink("%s/out/LiveOS/osmin" %(self._builddir))
        except:
            pass

    def minimizeImage(self):
        """Shrink the image to the minimal size it can be."""
        self.cleanupDeleted()
        self.genMinInstDelta()

    def configBoot(self):
        pass

    def package(self):
        os.makedirs(self._outdir + "/LiveOS")
        self.minimizeImage()
