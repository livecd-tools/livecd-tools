#
# creator.py : ImageCreator and LoopImageCreator base classes
#
# Copyright 2007, Red Hat, Inc.
# Copyright 2016, Kevin Kofler
# Copyright 2016, Neal Gompa
# Copyright 2017, Fedora Project
#
# Portions from Anaconda dnfpayload.py
# DNF/rpm software payload management.
#
# Copyright (C) 2013-2015  Red Hat, Inc.
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
import logging
import subprocess

import selinux
import dnf
import rpm

from imgcreate.errors import *
from imgcreate.fs import *
from imgcreate.dnfinst import *
from imgcreate import kickstart

FSLABEL_MAXLEN = 32
"""The maximum string length supported for LoopImageCreator.fslabel."""


class ImageCreator(object):
    """Installs a system to a chroot directory.

    ImageCreator is the simplest creator class available; it will install and
    configure a system image according to the supplied kickstart file.

    e.g.

      import imgcreate
      ks = imgcreate.read_kickstart("foo.ks")
      imgcreate.ImageCreator(ks, "foo").create()

    """

    def __init__(self, ks, name, releasever=None, tmpdir="/tmp", useplugins=False,
                 cacheonly=False, docleanup=True):
        """Initialize an ImageCreator instance.

        ks -- a pykickstart.KickstartParser instance; this instance will be
              used to drive the install by e.g. providing the list of packages
              to be installed, the system configuration and %post scripts

        name -- a name for the image; used for e.g. image filenames or
                filesystem labels

        releasever -- Value to substitute for $releasever in repo urls

        tmpdir -- Top level directory to use for temporary files and dirs

        cacheonly -- Only read from cache, work offline
        """
        self.ks = ks
        """A pykickstart.KickstartParser instance."""

        self.name = name
        """A name for the image."""

        self.releasever = releasever
        self.useplugins = useplugins

        self.tmpdir = tmpdir
        """The directory in which all temporary files will be created."""
        if not os.path.exists(self.tmpdir):
            makedirs(self.tmpdir)

        self.cacheonly = cacheonly
        self.docleanup = docleanup
        self.excludeWeakdeps = kickstart.exclude_weakdeps(self.ks)

        self.__builddir = None
        self.__bindmounts = []
        self.__fstype = kickstart.get_image_fstype(self.ks, "ext4")

        self.__sanity_check()

        # get selinuxfs mountpoint
        self.__selinux_mountpoint = "/sys/fs/selinux"
        with open("/proc/self/mountinfo", "r") as f:
            for line in f.readlines():
                fields = line.split()
                if fields[-2] == "selinuxfs":
                    self.__selinux_mountpoint = fields[4]
                    break

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
    """The location of the install root directory.

    This is the directory into which the system is installed. Subclasses may
    mount a filesystem image here or copy files to/from here.

    Note, this directory does not exist before ImageCreator.mount() is called.

    Note also, this is a read-only attribute.

    """

    def __get_outdir(self):
        if self.__builddir is None:
            raise CreatorError("_outdir is not valid before calling mount()")
        return self.__builddir + "/out"
    _outdir = property(__get_outdir)
    """The staging location for the final image.

    This is where subclasses should stage any files that are part of the final
    image. ImageCreator.package() will copy any files found here into the
    requested destination directory.

    Note, this directory does not exist before ImageCreator.mount() is called.

    Note also, this is a read-only attribute.

    """

    def __get_fstype(self):
        return self.__fstype
    def __set_fstype(self, val):
        if val not in ("ext2", "ext3", "ext4"):
            raise CreatorError("Unknown _fstype '%s' supplied" % val)
        self.__fstype = val
    _fstype = property(__get_fstype, __set_fstype)
    """The type of filesystem used for the image.

    This is the filesystem type used when creating the filesystem image.
    Subclasses may change this if they wish to use something other ext3.

    Note, only ext2, ext3, ext4 are currently supported.

    Note also, this attribute may only be set before calling mount().

    """

    #
    # Hooks for subclasses
    #
    def _mount_instroot(self, base_on = None):
        """Mount or prepare the install root directory.

        This is the hook where subclasses may prepare the install root by e.g.
        mounting creating and loopback mounting a filesystem image to
        _instroot.

        There is no default implementation.

        base_on -- this is the value passed to mount() and can be interpreted
                   as the subclass wishes; it might e.g. be the location of
                   a previously created ISO containing a system image.

        """
        pass

    def _unmount_instroot(self):
        """Undo anything performed in _mount_instroot().

        This is the hook where subclasses must undo anything which was done
        in _mount_instroot(). For example, if a filesystem image was mounted
        onto _instroot, it should be unmounted here.

        There is no default implementation.

        """
        pass

    def _create_bootconfig(self):
        """Configure the image so that it's bootable.

        This is the hook where subclasses may prepare the image for booting by
        e.g. creating an initramfs and bootloader configuration.

        This hook is called while the install root is still mounted, after the
        packages have been installed and the kickstart configuration has been
        applied, but before the %post scripts have been executed.

        There is no default implementation.

        """
        pass

    def _stage_final_image(self):
        """Stage the final system image in _outdir.

        This is the hook where subclasses should place the image in _outdir
        so that package() can copy it to the requested destination directory.

        By default, this moves the install root into _outdir.

        """
        shutil.move(self._instroot, self._outdir + "/" + self.name)

    def _get_required_packages(self):
        """Return a list of required packages.

        This is the hook where subclasses may specify a set of packages which
        it requires to be installed.

        This returns an empty list by default.

        Note, subclasses should usually chain up to the base class
        implementation of this hook.

        """
        return []

    def _get_excluded_packages(self):
        """Return a list of excluded packages.

        This is the hook where subclasses may specify a set of packages which
        it requires _not_ to be installed.

        This returns an empty list by default.

        Note, subclasses should usually chain up to the base class
        implementation of this hook.

        """
        return []

    def _get_fstab(self):
        """Return the desired contents of /etc/fstab.

        This is the hook where subclasses may specify the contents of
        /etc/fstab by returning a string containing the desired contents.

        A sensible default implementation is provided.

        """
        s =  "/dev/root  /         %s    defaults,noatime 0 0\n" %(self._fstype)
        s += self._get_fstab_special()
        return s

    def _get_fstab_special(self):
        s = "devpts     /dev/pts  devpts  gid=5,mode=620   0 0\n"
        s += "tmpfs      /dev/shm  tmpfs   defaults         0 0\n"
        s += "proc       /proc     proc    defaults         0 0\n"
        s += "sysfs      /sys      sysfs   defaults         0 0\n"
        return s

    def _get_post_scripts_env(self, in_chroot):
        """Return an environment dict for %post scripts.

        This is the hook where subclasses may specify some environment
        variables for %post scripts by return a dict containing the desired
        environment.

        By default, this returns an empty dict.

        in_chroot -- whether this %post script is to be executed chroot()ed
                     into _instroot.

        """
        return {}

    def _get_kernel_versions(self):
        """Return a dict detailing the available kernel types/versions.

        This is the hook where subclasses may override what kernel types and
        versions should be available for e.g. creating the booloader
        configuration.

        A dict should be returned mapping the available kernel types to a list
        of the available versions for those kernels.

        The default implementation uses rpm to iterate over everything
        providing 'kernel', finds /boot/vmlinuz-* and returns the version
        obtained from the vmlinuz filename. (This can differ from the kernel
        RPM's n-v-r in the case of e.g. xen)

        """
        def get_version(header):
            for f in header['filenames']:
                if not isinstance(f, str):
                    f = f.decode("utf-8")
                if f.startswith('/boot/vmlinuz-'):
                    return f[14:]
            return None

        ts = rpm.TransactionSet(self._instroot)

        ret = {}
        for header in ts.dbMatch('provides', 'kernel'):
            version = get_version(header)
            if version is None:
                continue

            name = header['name']
            if not name in ret:
                ret[name] = [version]
            elif not version in ret[name]:
                ret[name].append(version)

        return ret

    #
    # Helpers for subclasses
    #
    def _do_bindmounts(self):
        """Mount various system directories onto _instroot.

        This method is called by mount(), but may also be used by subclasses
        in order to re-mount the bindmounts after modifying the underlying
        filesystem.

        """
        for b in self.__bindmounts:
            b.mount()

    def _undo_bindmounts(self):
        """Unmount the bind-mounted system directories from _instroot.

        This method is usually only called by unmount(), but may also be used
        by subclasses in order to gain access to the filesystem obscured by
        the bindmounts - e.g. in order to create device nodes on the image
        filesystem.

        """
        self.__bindmounts.reverse()
        for b in self.__bindmounts:
            b.unmount()

    def _chroot(self):
        """Chroot into the install root.

        This method may be used by subclasses when executing programs inside
        the install root, e.g.,

          subprocess.call("ls", preexec_fn=self.chroot)

        """
        os.chroot(self._instroot)
        os.chdir("/")

    def _mkdtemp(self, prefix = "tmp-"):
        """Create a temporary directory.

        This method may be used by subclasses to create a temporary directory
        for use in building the final image - e.g. a subclass might create
        a temporary directory in order to bundle a set of files into a package.

        The subclass may delete this directory if it wishes, but it will be
        automatically deleted by cleanup().

        The absolute path to the temporary directory is returned.

        Note, this method should only be called after mount() has been called.

        prefix -- a prefix which should be used when creating the directory;
                  defaults to "tmp-".

        """
        self.__ensure_builddir()
        return tempfile.mkdtemp(dir = self.__builddir, prefix = prefix)

    def _mkstemp(self, prefix = "tmp-"):
        """Create a temporary file.

        This method may be used by subclasses to create a temporary file
        for use in building the final image - e.g. a subclass might need
        a temporary location to unpack a compressed file.

        The subclass may delete this file if it wishes, but it will be
        automatically deleted by cleanup().

        A tuple containing a file descriptor (returned from os.open() and the
        absolute path to the temporary directory is returned.

        Note, this method should only be called after mount() has been called.

        prefix -- a prefix which should be used when creating the file;
                  defaults to "tmp-".

        """
        self.__ensure_builddir()
        return tempfile.mkstemp(dir = self.__builddir, prefix = prefix)

    def _mktemp(self, prefix = "tmp-"):
        """Create a temporary file.

        This method simply calls _mkstemp() and closes the returned file
        descriptor.

        The absolute path to the temporary file is returned.

        Note, this method should only be called after mount() has been called.

        prefix -- a prefix which should be used when creating the file;
                  defaults to "tmp-".

        """

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
            self.__builddir = tempfile.mkdtemp(dir =  os.path.abspath(self.tmpdir),
                                               prefix = "imgcreate-")
        except OSError as e:
            raise CreatorError("Failed create build directory in %s: %s" %
                               (self.tmpdir, e.strerror))

    def __sanity_check(self):
        """Ensure that the config we've been given is sane."""
        if not (kickstart.get_packages(self.ks) or
                kickstart.get_groups(self.ks)):
            raise CreatorError("No packages or groups specified")

        kickstart.convert_method_to_repo(self.ks)

        if not kickstart.get_repos(self.ks):
            raise CreatorError("No repositories specified")

    def __write_fstab(self):
        fstab = open(self._instroot + "/etc/fstab", "w")
        fstab.write(self._get_fstab())
        fstab.close()

    def __create_minimal_dev(self):
        """Create a minimal /dev so that we don't corrupt the host /dev"""
        origumask = os.umask(0000)
        devices = (('null',   1, 3, 0o666),
                   ('urandom',1, 9, 0o666),
                   ('random', 1, 8, 0o666),
                   ('full',   1, 7, 0o666),
                   ('ptmx',   5, 2, 0o666),
                   ('tty',    5, 0, 0o666),
                   ('zero',   1, 5, 0o666))
        links = (("/proc/self/fd", "/dev/fd"),
                 ("/proc/self/fd/0", "/dev/stdin"),
                 ("/proc/self/fd/1", "/dev/stdout"),
                 ("/proc/self/fd/2", "/dev/stderr"))

        for (node, major, minor, perm) in devices:
            if not os.path.exists(self._instroot + "/dev/" + node):
                os.mknod(self._instroot + "/dev/" + node, perm | stat.S_IFCHR, os.makedev(major,minor))
        for (src, dest) in links:
            if not os.path.exists(self._instroot + dest):
                os.symlink(src, self._instroot + dest)
        os.umask(origumask)

    def __create_selinuxfs(self, force=False):
        if not os.path.exists(self.__selinux_mountpoint):
            return

        arglist = ["mount", "--bind", "/dev/null",
                   self._instroot + self.__selinux_mountpoint + "/load"]
        subprocess.call(arglist, close_fds = True)

        if force or kickstart.selinux_enabled(self.ks):
            # label the fs like it is a root before the bind mounting
            arglist = ["setfiles", "-F", "-r", self._instroot,
                       selinux.selinux_file_context_path(), self._instroot]
            subprocess.call(arglist, close_fds = True)
            # these dumb things don't get magically fixed, so make the user generic
        # if selinux exists on the host we need to lie to the chroot
        if selinux.is_selinux_enabled():
            for f in ("/proc", "/sys"):
                arglist = ["chcon", "-u", "system_u", self._instroot + f]
                subprocess.call(arglist, close_fds = True)

    def __destroy_selinuxfs(self):
        if not os.path.exists(self.__selinux_mountpoint):
            return

        # if the system was running selinux clean up our lies
        path = self._instroot + self.__selinux_mountpoint + "/load"
        if os.path.exists(path):
            arglist = ["umount", path]
            subprocess.call(arglist, close_fds = True)

    def mount(self, base_on = None, cachedir = None):
        """Setup the target filesystem in preparation for an install.

        This function sets up the filesystem which the ImageCreator will
        install into and configure. The ImageCreator class merely creates an
        install root directory, bind mounts some system directories (e.g. /dev)
        and writes out /etc/fstab. Other subclasses may also e.g. create a
        sparse file, format it and loopback mount it to the install root.

        base_on -- a previous install on which to base this install; defaults
                   to None, causing a new image to be created

        cachedir -- a directory in which to store the DNF cache; defaults to
                    None, causing a new cache to be created; by setting this
                    to another directory, the same cache can be reused across
                    multiple installs.

        """
        self.__ensure_builddir()

        makedirs(self._instroot)
        makedirs(self._outdir)

        self._mount_instroot(base_on)

        for d in ("/dev/pts", "/etc", "/boot", "/var/log", "/var/cache/dnf", "/sys", "/proc"):
            makedirs(self._instroot + d)

        cachesrc = cachedir or (self.__builddir + "/dnf-cache")
        makedirs(cachesrc)

        # delete any leftover @System.solv from a previous run from the cache,
        # which confuses Hawkey/DNF very badly (it thinks the rpmdb is corrupt
        # when it is actually just the cache that is stale)
        try:
            os.unlink(cachesrc + "/@System.solv")
        except OSError:
            pass

        # bind mount system directories into _instroot
        for (f, dest) in [("/sys", None), ("/proc", None),
                          ("/dev/pts", None), ("/dev/shm", None),
                          (self.__selinux_mountpoint, self.__selinux_mountpoint),
                          (cachesrc, "/var/cache/dnf")]:
            if os.path.exists(f):
                self.__bindmounts.append(BindChrootMount(f, self._instroot, dest))
            else:
                logging.warning("Skipping (%s,%s) because source doesn't exist." % (f, dest))

        self._do_bindmounts()

        makedirs(self._instroot + "/var/lib/dnf")

        self.__create_selinuxfs()

        self.__create_minimal_dev()

        os.symlink("/proc/self/mounts", self._instroot + "/etc/mtab")

        self.__write_fstab()

    def unmount(self):
        """Unmounts the target filesystem.

        The ImageCreator class detaches the system from the install root, but
        other subclasses may also detach the loopback mounted filesystem image
        from the install root.

        """
        self.__destroy_selinuxfs()

        self._undo_bindmounts()

        self._unmount_instroot()

    def cleanup(self):
        """Unmounts the target filesystem and deletes temporary files.

        This method calls unmount() and then deletes any temporary files and
        directories that were created on the host system while building the
        image.

        Note, make sure to call this method once finished with the creator
        instance in order to ensure no stale files are left on the host e.g.:

          creator = ImageCreator(ks, name)
          try:
              creator.create()
          finally:
              creator.cleanup()

        """
        if not self.docleanup:
            logging.warning("Skipping cleanup of temporary files")
            return

        if not self.__builddir:
            return

        self.unmount()

        shutil.rmtree(self.__builddir, ignore_errors = True)
        self.__builddir = None

    def __apply_selections(self, dbo):
        excludedPkgs = kickstart.get_excluded(self.ks, self._get_excluded_packages())

        if kickstart.nocore(self.ks):
            logging.info("skipping core group due to %%packages --nocore; system may not be complete")
        else:
            try:
                dbo.selectGroup('core', excludedPkgs)
                logging.info("selected group: core")
            except dnf.exceptions.MarkingError as e:
                if kickstart.ignore_missing(self.ks):
                    logging.warning("Skipping missing group 'core'")
                else:
                    raise CreatorError("Failed to find group 'core' : %s" %
                                       (e,))

        env = kickstart.get_environment(self.ks)

        excludedGroups = [group.name for group in kickstart.get_excluded_groups(self.ks)]

        if env:
            try:
                dbo.selectEnvironment(env, excludedGroups, excludedPkgs)
                logging.info("selected env: %s", env)
            except dnf.exceptions.MarkingError as e:
                if kickstart.ignore_missing(self.ks):
                    logging.warning("Skipping missing environment '%s'" % (env,))
                else:
                    raise CreatorError("Failed to find environment '%s' : %s" %
                                       (env, e))

        for group in kickstart.get_groups(self.ks):
            if group.name == 'core' or group.name in excludedGroups:
                continue

            try:
                dbo.selectGroup(group.name, excludedPkgs, group.include)
                logging.info("selected group: %s", group.name)
            except dnf.exceptions.MarkingError as e:
                if kickstart.ignore_missing(self.ks):
                    logging.warning("Skipping missing group '%s'" % (group.name,))
                else:
                    raise CreatorError("Failed to find group '%s' : %s" %
                                       (group.name, e))

        for pkg_name in set(excludedPkgs):
            dbo.deselectPackage(pkg_name)
            logging.info("excluding package: '%s'", pkg_name)

        for pkg_name in set(kickstart.get_packages(self.ks,
                                                   self._get_required_packages())) - set(excludedPkgs):
            try:
                dbo.selectPackage(pkg_name)
                logging.info("selected package: '%s'", pkg_name)
            except dnf.exceptions.MarkingError as e:
                if kickstart.ignore_missing(self.ks):
                    logging.warning("Skipping missing package '%s'" % (pkg_name,))
                else:
                    raise CreatorError("Failed to find package '%s' : %s" %
                                       (pkg_name, e))

    def install(self, repo_urls = {}):
        """Install packages into the install root.

        This function installs the packages listed in the supplied kickstart
        into the install root. By default, the packages are installed from the
        repository URLs specified in the kickstart.

        repo_urls -- a dict which maps a repository name to a repository URL;
                     if supplied, this causes any repository URLs specified in
                     the kickstart to be overridden.

        """
        dnf_conf = self._mktemp(prefix = "dnf.conf-")

        dbo = DnfLiveCD(releasever=self.releasever, useplugins=self.useplugins)
        dbo.setup(dnf_conf, self._instroot, cacheonly=self.cacheonly,
                   excludeWeakdeps=self.excludeWeakdeps)

        for repo in kickstart.get_repos(self.ks, repo_urls):
            (name, baseurl, mirrorlist, proxy, inc, exc, cost, sslverify) = repo

            yr = dbo.addRepository(name, baseurl, mirrorlist)
            if inc:
                yr.includepkgs = inc
            if exc:
                yr.exclude = exc
            if proxy:
                yr.proxy = proxy
            if cost is not None:
                yr.cost = cost
            yr.sslverify = sslverify

        if kickstart.exclude_docs(self.ks):
            rpm.addMacro("_excludedocs", "1")
        if not kickstart.selinux_enabled(self.ks):
            rpm.addMacro("__file_context_path", "%{nil}")
        if kickstart.inst_langs(self.ks) != None:
            rpm.addMacro("_install_langs", kickstart.inst_langs(self.ks))

        dbo.fill_sack(load_system_repo = os.path.exists(self._instroot + "/var/lib/rpm/Packages"))
        dbo.read_comps()

        try:
            self.__apply_selections(dbo)

            dbo.runInstall()
        except (dnf.exceptions.DownloadError, dnf.exceptions.RepoError) as e:
            raise CreatorError("Unable to download from repo : %s" % (e,))
        except dnf.exceptions.Error as e:
            raise CreatorError("Unable to install: %s" % (e,))
        finally:
            dbo.close()
            os.unlink(dnf_conf)

        # do some clean up to avoid lvm info leakage.  this sucks.
        for subdir in ("cache", "backup", "archive"):
            lvmdir = self._instroot + "/etc/lvm/" + subdir
            try:
                for f in os.listdir(lvmdir):
                    os.unlink(lvmdir + "/" + f)
            except:
                pass

    def _run_post_scripts(self):
        for s in kickstart.get_post_scripts(self.ks):
            (fd, path) = tempfile.mkstemp(prefix = "ks-script-",
                                          dir = self._instroot + "/tmp")

            os.write(fd, s.script.encode("utf-8"))
            os.close(fd)
            os.chmod(path, 0o700)

            env = self._get_post_scripts_env(s.inChroot)

            if not s.inChroot:
                env["INSTALL_ROOT"] = self._instroot
                preexec = None
                script = path
            else:
                preexec = self._chroot
                script = "/tmp/" + os.path.basename(path)

            try:
                subprocess.check_call([s.interp, script],
                                      preexec_fn = preexec, env = env)
            except OSError as e:
                raise CreatorError("Failed to execute %%post script "
                                   "with '%s' : %s" % (s.interp, e.strerror))
            except subprocess.CalledProcessError as err:
                if s.errorOnFail:
                    raise CreatorError("%%post script failed with code %d "
                                       % err.returncode)
                logging.warning("ignoring %%post failure (code %d)"
                                % err.returncode)
            finally:
                os.unlink(path)

    def configure(self):
        """Configure the system image according to the kickstart.

        This method applies the (e.g. keyboard or network) configuration
        specified in the kickstart and executes the kickstart %post scripts.

        If neccessary, it also prepares the image to be bootable by e.g.
        creating an initrd and bootloader configuration.

        """
        ksh = self.ks.handler

        kickstart.LanguageConfig(self._instroot).apply(ksh.lang)
        kickstart.KeyboardConfig(self._instroot).apply(ksh.keyboard)
        kickstart.TimezoneConfig(self._instroot).apply(ksh.timezone)
        kickstart.AuthConfig(self._instroot).apply(ksh.authconfig)
        kickstart.FirewallConfig(self._instroot).apply(ksh.firewall)
        kickstart.RootPasswordConfig(self._instroot).apply(ksh.rootpw)
        kickstart.ServicesConfig(self._instroot).apply(ksh.services)
        kickstart.XConfig(self._instroot).apply(ksh.xconfig)
        kickstart.NetworkConfig(self._instroot).apply(ksh.network)
        kickstart.RPMMacroConfig(self._instroot).apply(self.ks)

        self._create_bootconfig()

        self._run_post_scripts()
        kickstart.SelinuxConfig(self._instroot).apply(ksh.selinux)

    def launch_shell(self):
        """Launch a shell in the install root.

        This method is launches a bash shell chroot()ed in the install root;
        this can be useful for debugging.

        """
        subprocess.call("bash", preexec_fn=self._chroot)

    def package(self, destdir='.', ops=[]):
        """Prepares the created image for final delivery.

        In its simplest form, this method merely copies the install root to the
        supplied destination directory; other subclasses may choose to package
        the image by e.g. creating a bootable ISO containing the image and
        bootloader configuration.

        destdir -- the directory into which the final image should be moved;
                   this defaults to the current directory.

        ops     -- options list, e.g., ['show-squashing'], passed to subsequent
                   procedures, such as, mksquashfs(), or ['flatten-squashfs']
                   passed to _stage_final_image().

        """
        self._stage_final_image(ops)

        for f in os.listdir(self._outdir):
            shutil.move(os.path.join(self._outdir, f),
                        os.path.join(destdir, f))

    def create(self):
        """Install, configure and package an image.

        This method is a utility method which creates and image by calling some
        of the other methods in the following order - mount(), install(),
        configure(), unmount and package().

        """
        self.mount()
        self.install()
        self.configure()
        self.unmount()
        self.package()

class LoopImageCreator(ImageCreator):
    """Installs a system into a loopback-mountable filesystem image.

    LoopImageCreator is a straightforward ImageCreator subclass; the system
    is installed into an ext3 filesystem on a sparse file which can be
    subsequently loopback-mounted.

    """

    def __init__(self, ks, name, fslabel=None, releasever=None, tmpdir="/tmp",
                 useplugins=False, cacheonly=False, docleanup=True):
        """Initialize a LoopImageCreator instance.

        This method takes the same arguments as ImageCreator.__init__() with
        the addition of:

        fslabel -- A string used as a label for any filesystems created.

        """
        ImageCreator.__init__(self, ks, name, releasever=releasever, tmpdir=tmpdir,
                              useplugins=useplugins, cacheonly=cacheonly, docleanup=docleanup)

        self.__fslabel = None
        self.fslabel = fslabel

        self.__minsize_KB = 0
        self.__blocksize = 4096

        self.__instloop = None
        self.__imgdir = None

        self.__image_size = kickstart.get_image_size(self.ks,
                                                     4096 * 1024 * 1024)

    #
    # Properties
    #
    def __get_fslabel(self):
        if self.__fslabel is None:
            return self.name
        else:
            return self.__fslabel
    def __set_fslabel(self, val):
        if val is None:
            self.__fslabel = None
        else:
            self.__fslabel = val[:FSLABEL_MAXLEN]
    fslabel = property(__get_fslabel, __set_fslabel)
    """A string used to label any filesystems created.

    Some filesystems impose a constraint on the maximum allowed size of the
    filesystem label. In the case of ext3 it's 16 characters, but in the case
    of ISO9660 it's 32 characters.

    mke2fs silently truncates the label, but xorrisofs aborts if the label is
    too long. So, for convenience sake, any string assigned to this attribute is
    silently truncated to FSLABEL_MAXLEN (32) characters.

    """

    def __get_image(self):
        if self.__imgdir is None:
            raise CreatorError("_image is not valid before calling mount()")
        return self.__imgdir + "/ext3fs.img"
    _image = property(__get_image)
    """The location of the image file.

    This is the path to the filesystem image. Subclasses may use this path
    in order to package the image in _stage_final_image().

    Note, this directory does not exist before ImageCreator.mount() is called.

    Note also, this is a read-only attribute.

    """

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
    """The block size used by the image's filesystem.

    This is the block size used when creating the filesystem image. Subclasses
    may change this if they wish to use something other than a 4k block size.

    Note, this attribute may only be set before calling mount().

    """

    #
    # Helpers for subclasses
    #
    def _resparse(self, size = None):
        """Rebuild the filesystem image to be as sparse as possible.

        This method should be used by subclasses when staging the final image
        in order to reduce the actual space taken up by the sparse image file
        to be as little as possible.

        This is done by resizing the filesystem to the minimal size (thereby
        eliminating any space taken up by deleted files) and then resizing it
        back to the supplied size.

        size -- the size in, in bytes, which the filesystem image should be
                resized to after it has been minimized; this defaults to None,
                causing the original size specified by the kickstart file to
                be used (or 4GiB if not specified in the kickstart).

        """
        return self.__instloop.resparse(size)

    def _base_on(self, base_on):
        shutil.copyfile(base_on, self._image)
        
    #
    # Actual implementation
    #
    def _mount_instroot(self, base_on = None):
        self.__imgdir = self._mkdtemp()

        if not base_on is None:
            self._base_on(base_on)

        self.__instloop = ExtDiskMount(SparseLoopbackDisk(self._image,
                                                          self.__image_size),
                                       self._instroot,
                                       self._fstype,
                                       self.__blocksize,
                                       self.fslabel)

        try:
            self.__instloop.mount()
        except MountError as e:
            raise CreatorError("Failed to loopback mount '%s' : %s" %
                               (self._image, e))

    def _unmount_instroot(self):
        if not self.__instloop is None:
            self.__instloop.cleanup()

    def _stage_final_image(self):
        self._resparse()
        shutil.move(self._image, self._outdir + "/" + self.name + ".img")
