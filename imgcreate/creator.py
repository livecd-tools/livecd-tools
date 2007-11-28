#!/usr/bin/python -tt
#
# creator.py : ImageCreator and LoopImageCreator base classes
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

from imgcreate.errors import *
from imgcreate.fs import *
from imgcreate.yuminst import *
from imgcreate import kickstart

class ImageCreator(object):
    def __init__(self, ks, fslabel):
        self.ks = ks.handler
        self.fslabel = fslabel
        self.tmpdir = "/var/tmp"

        self.__builddir = None
        self.__bindmounts = []

        self.__sanity_check()

    def __del__(self):
        self.cleanup()

    #
    # Properties
    #
    def __get_instroot(self):
        if self.__builddir is None:
            raise CreatorError("_instroot is not valid before calling mount()")
        return self.__builddir + "/install_root"
    _instroot = property(__get_instroot)

    def __get_outdir(self):
        if self.__builddir is None:
            raise CreatorError("_outdir is not valid before calling mount()")
        return self.__builddir + "/out"
    _outdir = property(__get_outdir)

    #
    # Hooks for subclasses
    #
    def _mount_instroot(self, base_on = None):
        """Do any creation necessary and mount the install root"""
        pass

    def _unmount_instroot(self):
        """Tear down the install root."""
        pass

    def _create_bootconfig(self):
        """Configure the image so that it's bootable."""
        pass

    def _stage_final_image(self):
        shutil.move(self._instroot, self._outdir + "/" + self.fslabel)

    def _get_required_packages(self):
        return []
    def _get_excluded_packages(self):
        return []

    def _get_kernel_options(self):
        r = "ro quiet liveimg"
        if os.path.exists(self._instroot + "/usr/bin/rhgb"):
            r += " rhgb"
        return r
        
    def _get_fstab(self):
        s =  "/dev/root  /         ext3    defaults,noatime 0 0\n"
        s += "devpts     /dev/pts  devpts  gid=5,mode=620   0 0\n"
        s += "tmpfs      /dev/shm  tmpfs   defaults         0 0\n"
        s += "proc       /proc     proc    defaults         0 0\n"
        s += "sysfs      /sys      sysfs   defaults         0 0\n"
        return s

    def _get_post_scripts_env(self, in_chroot):
        return {}

    def _get_kernel_versions(self):
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

    #
    # Helpers for subclasses
    #
    def _do_bindmounts(self):
        for b in self.__bindmounts:
            b.mount()

    def _undo_bindmounts(self):
        self.__bindmounts.reverse()
        for b in self.__bindmounts:
            b.unmount()

    def _chroot(self):
        os.chroot(self._instroot)
        os.chdir("/")

    def _mkdtemp(self, prefix = "tmp-"):
        self.__ensure_builddir()
        return tempfile.mkdtemp(dir = self.__builddir, prefix = prefix)

    def _mkstemp(self, prefix = "tmp-"):
        self.__ensure_builddir()
        return tempfile.mkstemp(dir = self.__builddir, prefix = prefix)

    def _mktemp(self, prefix = "tmp-"):
        (f, path) = self._mkstemp(prefix)
        os.close(f)
        return path

    #
    # Actual implementation
    #
    def __ensure_builddir(self):
        if not self.__builddir is None:
            return

        try:
            self.__builddir = tempfile.mkdtemp(dir = self.tmpdir,
                                               prefix = "imgcreate-")
        except OSError, (err, msg):
            raise CreatorError("Failed create build directory in %s: %s" %
                               (self.tmpdir, msg))

    def __sanity_check(self):
        """Ensure that the config we've been given is sane."""
        if not (kickstart.get_packages(self.ks) or
                kickstart.get_groups(self.ks)):
            raise CreatorError("No packages or groups specified")

        kickstart.convert_method_to_repo(self.ks)

        if not kickstart.get_repos(self.ks):
            raise CreatorError("No repositories specified")

        if (kickstart.selinux_enabled(self.ks) and
            not os.path.exists("/selinux/enforce")):
            raise CreatorError("SELinux requested but not enabled on host")

    def __write_fstab(self):
        fstab = open(self._instroot + "/etc/fstab", "w")
        fstab.write(self._get_fstab())
        fstab.close()

    def mount(self, base_on = None, cachedir = None):
        """setup target ext3 file system in preparation for an install"""
        self.__ensure_builddir()

        os.makedirs(self._instroot)
        os.makedirs(self._outdir)

        self._mount_instroot(base_on)

        for d in ("/etc", "/boot", "/var/log", "/var/cache/yum"):
            makedirs(self._instroot + d)

        cachesrc = (cachedir or self.__builddir) + "/yum-cache"
        makedirs(cachesrc)

        # bind mount system directories into _instroot
        for (f, dest) in [("/sys", None), ("/proc", None), ("/dev", None),
                          ("/dev/pts", None), ("/selinux", None),
                          (cachesrc, "/var/cache/yum")]:
            self.__bindmounts.append(BindChrootMount(f, self._instroot, dest))

        self._do_bindmounts()

        os.symlink("../proc/mounts", self._instroot + "/etc/mtab")

        self.__write_fstab()

    def unmount(self):
        """detaches system bind mounts and _instroot for the file system and
        tears down loop devices used"""
        try:
            os.unlink(self._instroot + "/etc/mtab")
        except OSError:
            pass

        self._undo_bindmounts()

        self._unmount_instroot()

    def cleanup(self):
        if not self.__builddir:
            return

        self.unmount()

        shutil.rmtree(self.__builddir, ignore_errors = True)
        self.__builddir = None

    def __select_packages(self, ayum):
        skipped_pkgs = []
        for pkg in kickstart.get_packages(self.ks,
                                          self._get_required_packages()):
            try:
                ayum.selectPackage(pkg)
            except yum.Errors.InstallError, e:
                if kickstart.ignore_missing(self.ks):
                    raise CreatorError("Failed to find package '%s' : %s" %
                                       (pkg, e))
                else:
                    skipped_pkgs.append(pkg)

        for pkg in skipped_pkgs:
            print >> sys.stderr, "Skipping missing package '%s'" % (pkg,)

    def __select_groups(self, ayum):
        skipped_groups = []
        for group in kickstart.get_groups(self.ks):
            try:
                ayum.selectGroup(group.name, group.include)
            except (yum.Errors.InstallError, yum.Errors.GroupsError), e:
                if kickstart.ignore_missing(self.ks):
                    raise CreatorError("Failed to find group '%s' : %s" %
                                       (group.name, e))
                else:
                    skipped_groups.append(group)

        for group in skipped_groups:
            print >> sys.stderr, "Skipping missing group '%s'" % (group.name,)

    def __deselect_packages(self, ayum):
        for pkg in kickstart.get_excluded(self.ks,
                                          self._get_excluded_packages()):
            ayum.deselectPackage(pkg)
        
    def install(self, repo_urls = {}):
        """Install packages into _instroot"""
        yum_conf = self._mktemp(prefix = "yum.conf-")

        ayum = LiveCDYum()
        ayum.setup(yum_conf, self._instroot)

        for repo in kickstart.get_repos(self.ks, repo_urls):
            (name, baseurl, mirrorlist, inc, exc) = repo
            
            yr = ayum.addRepository(name, baseurl, mirrorlist)
            if inc:
                yr.includepkgs = inc
            if exc:
                yr.exclude = exc

        if kickstart.exclude_docs(self.ks):
            rpm.addMacro("_excludedocs", "1")

        try:
            self.__select_packages(ayum)
            self.__select_groups(ayum)
            self.__deselect_packages(ayum)
            ayum.runInstall()
        except yum.Errors.RepoError, e:
            raise CreatorError("Unable to download from repo : %s" % (e,))
        except yum.Errors.YumBaseError, e:
            raise CreatorError("Unable to install: %s" % (e,))
        finally:
            ayum.closeRpmDB()
            ayum.close()
            os.unlink(yum_conf)

        # do some clean up to avoid lvm info leakage.  this sucks.
        for subdir in ("cache", "backup", "archive"):
            lvmdir = self._instroot + "/etc/lvm/" + subdir
            try:
                for f in os.listdir(lvmdir):
                    os.unlink(lvmdir + "/" + f)
            except:
                pass

    def __run_post_scripts(self):
        for s in kickstart.get_post_scripts(self.ks):
            (fd, path) = tempfile.mkstemp(prefix = "ks-script-",
                                          dir = self._instroot + "/tmp")

            os.write(fd, s.script)
            os.close(fd)
            os.chmod(path, 0700)

            env = self._get_post_scripts_env(s.inChroot)

            if not s.inChroot:
                env["INSTALL_ROOT"] = self._instroot
                preexec = None
                script = path
            else:
                preexec = self._chroot
                script = "/tmp/" + os.path.basename(path)

            try:
                subprocess.call([s.interp, script],
                                preexec_fn = preexec, env = env)
            except OSError, (err, msg):
                raise CreatorError("Failed to execute %%post script "
                                   "with '%s' : %s" % (s.interp, msg))
            finally:
                os.unlink(path)

    def configure(self):
        kickstart.LanguageConfig(self._instroot).apply(self.ks.lang)
        kickstart.KeyboardConfig(self._instroot).apply(self.ks.keyboard)
        kickstart.TimezoneConfig(self._instroot).apply(self.ks.timezone)
        kickstart.AuthConfig(self._instroot).apply(self.ks.authconfig)
        kickstart.FirewallConfig(self._instroot).apply(self.ks.firewall)
        kickstart.SelinuxConfig(self._instroot).apply(self.ks.selinux)
        kickstart.RootPasswordConfig(self._instroot).apply(self.ks.rootpw)
        kickstart.ServicesConfig(self._instroot).apply(self.ks.services)
        kickstart.XConfig(self._instroot).apply(self.ks.xconfig)
        kickstart.NetworkConfig(self._instroot).apply(self.ks.network)
        kickstart.SelinuxConfig(self._instroot).apply(self.ks.selinux)

        self._create_bootconfig()

        self.__run_post_scripts()

    def launch_shell(self):
        subprocess.call(["/bin/bash"], preexec_fn = self._chroot)

    def package(self, destdir = "."):
        """Create a nice package for delivery of the image."""
        self._stage_final_image()

        for f in os.listdir(self._outdir):
            shutil.move(os.path.join(self._outdir, f),
                        os.path.join(destdir, f))

    def create(self):
        """This is the simplest method to generate an image from the given
        configuration."""
        self.mount()
        self.install()
        self.configure()
        self.unmount()
        self.package()

class LoopImageCreator(ImageCreator):
    def __init__(self, *args):
        ImageCreator.__init__(self, *args)
        self.__minsize_KB = 0
        self.__blocksize = 4096
        self.__fstype = "ext3"

        self.__instloop = None
        self.__imgdir = None

        self.__image_size = kickstart.get_image_size(self.ks,
                                                     4096L * 1024 * 1024)

    def __get_image(self):
        if self.__imgdir is None:
            raise CreatorError("_image is not valid before calling mount()")
        return self.__imgdir + "/ext3fs.img"
    _image = property(__get_image)

    def __get_blocksize(self):
        return self.__blocksize
    def __set_blocksize(self, val):
        if self.__instloop:
            raise CreatorError("_blocksize must be set before calling mount()")
        try:
            self.__blocksize = int(val)
        except ValueError:
            raise CreatorError("'%s' is not a valid integer value "
                               "for _blocksize" % val)
    _blocksize = property(__get_blocksize, __set_blocksize)

    def __get_fstype(self):
        return self.__fstype
    def __set_fstype(self, val):
        if val != "ext2" and val != "ext3":
            raise CreatorError("Unknown _fstype '%s' supplied" % val)
        self.__fstype = val
    _fstype = property(__get_fstype, __set_fstype)

    def _mount_instroot(self, base_on = None):
        """Do any creation necessary and mount the install root"""
        self.__imgdir = self._mkdtemp()

        if not base_on is None:
            shutil.copyfile(base_on, self._image)

        self.__instloop = SparseExtLoopbackMount(self._image,
                                                 self._instroot,
                                                 self.__image_size,
                                                 self.__fstype,
                                                 self.__blocksize,
                                                 self.fslabel)

        try:
            self.__instloop.mount()
        except MountError, e:
            raise CreatorError("Failed to loopback mount '%s' : %s" %
                               (self._image, e))

    def _unmount_instroot(self):
        if not self.__instloop is None:
            self.__instloop.cleanup()

    def _resparse(self):
        return self.__instloop.resparse()
        
    def _stage_final_image(self):
        self._resparse()
        shutil.move(self._image, self._outdir + "/" + self.fslabel + ".img")
