#!/usr/bin/python -tt
#
# livecd-creator : Creates Live CD based for Fedora.
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
import glob
import sys
import errno
import string
import tempfile
import time
import traceback
import subprocess
import shutil
import optparse

import yum
import rpm
import rpmUtils.arch
import pykickstart
import pykickstart.parser
import pykickstart.version

class MountError(Exception):
    def __init__(self, msg):
        Exception.__init__(self, msg)

class InstallationError(Exception):
    def __init__(self, msg):
        Exception.__init__(self, msg)

def makedirs(dirname):
    """A version of os.makedirs() that doesn't throw an
    exception if the leaf directory already exists.
    """
    try:
        os.makedirs(dirname)
    except OSError, (err, msg):
        if err != errno.EEXIST:
            raise

class BindChrootMount:
    """Represents a bind mount of a directory into a chroot."""
    def __init__(self, src, chroot, dest = None):
        self.src = src
        self.root = chroot

        if not dest:
            dest = src
        self.dest = self.root + "/" + dest

        self.mounted = False

    def mount(self):
        if not self.mounted:
            makedirs(self.dest)
            rc = subprocess.call(["/bin/mount", "--bind", self.src, self.dest])
            if rc != 0:
                raise MountError("Bind-mounting '%s' to '%s' failed" % (self.src, self.dest))
            self.mounted = True

    def umount(self):
        if self.mounted:
            rc = subprocess.call(["/bin/umount", self.dest])
            self.mounted = False
        

class LoopbackMount:
    def __init__(self, lofile, mountdir, fstype = None):
        self.lofile = lofile
        self.mountdir = mountdir
        self.fstype = fstype

        self.mounted = False
        self.losetup = False
        self.rmdir   = False
        self.loopdev = None

    def cleanup(self):
        self.umount()
        self.lounsetup()

    def umount(self):
        if self.mounted:
            rc = subprocess.call(["/bin/umount", self.mountdir])
            self.mounted = False

        if self.rmdir:
            try:
                os.rmdir(self.mountdir)
            except OSError, e:
                pass
            self.rmdir = False

    def lounsetup(self):
        if self.losetup:
            rc = subprocess.call(["/sbin/losetup", "-d", self.loopdev])
            self.losetup = False
            self.loopdev = None

    def loopsetup(self):
        if self.losetup:
            return

        losetupProc = subprocess.Popen(["/sbin/losetup", "-f"],
                                       stdout=subprocess.PIPE)
        losetupOutput = losetupProc.communicate()[0]

        if losetupProc.returncode:
            raise MountError("Failed to allocate loop device for '%s'" % self.lofile)
        else:
            self.loopdev = losetupOutput.split()[0]

        rc = subprocess.call(["/sbin/losetup", self.loopdev, self.lofile])
        if rc != 0:
            raise MountError("Failed to allocate loop device for '%s'" % self.lofile)

        self.losetup = True

    def mount(self):
        if self.mounted:
            return

        self.loopsetup()

        if not os.path.isdir(self.mountdir):
            os.makedirs(self.mountdir)
            self.rmdir = True

        args = [ "/bin/mount", self.loopdev, self.mountdir ]
        if self.fstype:
            args.extend(["-t", self.fstype])

        rc = subprocess.call(args)
        if rc != 0:
            raise MountError("Failed to mount '%s' to '%s'" % (self.loopdev, self.mountdir))

        self.mounted = True

class SparseExt3LoopbackMount(LoopbackMount):
    def __init__(self, lofile, mountdir, size, blocksize, fslabel):
        LoopbackMount.__init__(self, lofile, mountdir, fstype = "ext3")
        self.size = size
        self.blocksize = blocksize
        self.fslabel = fslabel

    def _expandSparseFile(self, create = False):
        flags = os.O_WRONLY
        if create:
            flags |= os.O_CREAT
            makedirs(os.path.dirname(self.lofile))

        fd = os.open(self.lofile, flags)

        os.lseek(fd, self.size, 0)
        os.write(fd, '\x00')
        os.close(fd)

    def _truncateSparseFile(self):
        fd = os.open(self.lofile, os.O_WRONLY )
        os.ftruncate(fd, self.size)
        os.close(fd)

    def _formatFilesystem(self):
        rc = subprocess.call(["/sbin/mkfs.ext3", "-F", "-L", self.fslabel,
                              "-m", "1", "-b", str(self.blocksize), self.lofile,
                              str(self.size / self.blocksize)])
        if rc != 0:
            raise MountError("Error creating ext3 filesystem")
        rc = subprocess.call(["/sbin/tune2fs", "-c0", "-i0", "-Odir_index",
                              "-ouser_xattr,acl", self.lofile])

    def _resizeFilesystem(self):
        dev_null = os.open("/dev/null", os.O_WRONLY)
        try:
            return subprocess.call(["/sbin/resize2fs",
                                    self.lofile, "%sk" % (self.size / 1024,)],
                                   stdout = dev_null, stderr = dev_null)
        finally:
            os.close(dev_null)

    def create(self):
        self._expandSparseFile(create = True)
        self._formatFilesystem()

    def resize(self):
        current_size = os.stat(self.lofile)[stat.ST_SIZE]

        if self.size == current_size:
            return

        if self.size < current_size:
            self._expandSparseFile()

        self._resizeFilesystem()

        if self.size > current_size:
            self._truncateSparseFile()

    def mount(self):
        if not os.path.isfile(self.lofile):
            self.create()
        else:
            self.resize()
        return LoopbackMount.mount(self)

class TextProgress(object):
    def start(self, filename, url, *args, **kwargs):
        sys.stdout.write("Retrieving %s " % (url,))
        self.url = url
    def update(self, *args):
        pass
    def end(self, *args):
        sys.stdout.write("...OK\n")

class LiveCDYum(yum.YumBase):
    def __init__(self):
        yum.YumBase.__init__(self)

    def doFileLogSetup(self, uid, logfile):
        # don't do the file log for the livecd as it can lead to open fds
        # being left and an inability to clean up after ourself
        pass

    def close(self):
        try:
            os.unlink(self.conf.installroot + "/yum.conf")
        except:
            pass
        yum.YumBase.close(self)

    def _writeConf(self, datadir, installroot):
        conf  = "[main]\n"
        conf += "installroot=%s\n" % installroot
        conf += "cachedir=/var/cache/yum\n"
        conf += "plugins=0\n"
        conf += "reposdir=\n"

        path = datadir + "/yum.conf"

        f = file(path, "w+")
        f.write(conf)
        f.close()

        os.chmod(path, 0644)

        return path

    def setup(self, datadir, installroot):
        self.doConfigSetup(fn = self._writeConf(datadir, installroot),
                           root = installroot)
        self.conf.cache = 0
        self.doTsSetup()
        self.doRpmDBSetup()
        self.doRepoSetup()
        self.doSackSetup()

    def selectPackage(self, pkg):
        """Select a given package.  Can be specified with name.arch or name*"""
        return self.install(pattern = pkg)
        
    def deselectPackage(self, pkg):
        """Deselect package.  Can be specified as name.arch or name*"""
        sp = pkg.rsplit(".", 2)
        txmbrs = []
        if len(sp) == 2:
            txmbrs = self.tsInfo.matchNaevr(name=sp[0], arch=sp[1])

        if len(txmbrs) == 0:
            exact, match, unmatch = yum.packages.parsePackages(self.pkgSack.returnPackages(), [pkg], casematch=1)
            for p in exact + match:
                txmbrs.append(p)

        if len(txmbrs) > 0:
            map(lambda x: self.tsInfo.remove(x.pkgtup), txmbrs)
        else:
            print >> sys.stderr, "No such package %s to remove" %(pkg,)

    def selectGroup(self, grp, include = pykickstart.parser.GROUP_DEFAULT):
        yum.YumBase.selectGroup(self, grp)
        if include == pykickstart.parser.GROUP_REQUIRED:
            map(lambda p: self.deselectPackage(p), grp.default_packages.keys())
        elif include == pykickstart.parser.GROUP_ALL:
            map(lambda p: self.selectPackage(p), grp.optional_packages.keys())

    def addRepository(self, name, url = None, mirrorlist = None):
        def _varSubstitute(option):
            # takes a variable and substitutes like yum configs do
            option = option.replace("$basearch", rpmUtils.arch.getBaseArch())
            option = option.replace("$arch", rpmUtils.arch.getCanonArch())
            return option

        repo = yum.yumRepo.YumRepository(name)
        if url:
            repo.baseurl.append(_varSubstitute(url))
        if mirrorlist:
            repo.mirrorlist = _varSubstitute(mirrorlist)
        conf = yum.config.RepoConf()
        for k, v in conf.iteritems():
            if v or not hasattr(repo, k):
                repo.setAttribute(k, v)
        repo.basecachedir = self.conf.cachedir
        repo.metadata_expire = 0
        # disable gpg check???
        repo.gpgcheck = 0
        repo.enable()
        repo.setup(0)
        repo.setCallback(TextProgress())
        self.repos.add(repo)
        return repo
            
    def runInstall(self):
        try:
            (res, resmsg) = self.buildTransaction()
        except yum.Errors.RepoError, e:
            raise InstallationError("Unable to download from repo : %s" %(e,))
        if res != 2 and False:
            raise InstallationError("Failed to build transaction : %s" % str.join("\n", resmsg))
        
        dlpkgs = map(lambda x: x.po, filter(lambda txmbr: txmbr.ts_state in ("i", "u"), self.tsInfo.getMembers()))
        self.downloadPkgs(dlpkgs)
        # FIXME: sigcheck?
        
        self.initActionTs()
        self.populateTs(keepold=0)
        self.ts.check()
        self.ts.order()
        # FIXME: callback should be refactored a little in yum 
        sys.path.append('/usr/share/yum-cli')
        import callback
        cb = callback.RPMInstallCallback()
        cb.tsInfo = self.tsInfo
        cb.filelog = False
        return self.runTransaction(cb)

def mksquashfs(output, filelist, cwd = None):
    args = ["/sbin/mksquashfs"]
    args.extend(filelist)
    args.append(output)
    if not sys.stdout.isatty():
        args.append("-no-progress")
    if cwd is None:
        cwd = os.getcwd()
    return subprocess.call(args, cwd = cwd,  env={"PWD": cwd})

class ImageNetworkConfig(object):
    """An object to take the kickstart network configuration and turn it
    into something useful on the filesystem."""
    def __init__(self, ksnet, instroot):
        self.instroot = instroot
        self.ksnet = ksnet

    def __writeNetworkIfCfg(self, network):
        path = self.instroot + "/etc/sysconfig/network-scripts/ifcfg-" + network.device

        f = file(path, "w+")
        os.chmod(path, 0644)

        f.write("DEVICE=%s\n" % network.device)
        f.write("BOOTPROTO=%s\n" % network.bootProto)

        if network.bootProto.lower() == "static":
            if network.ip:
                f.write("IPADDR=%s\n" % network.ip)
            if network.netmask:
                f.write("NETMASK=%s\n" % network.netmask)

        if network.onboot:
            f.write("ONBOOT=on\n")
        else:
            f.write("ONBOOT=off\n")

        if network.essid:
            f.write("ESSID=%s\n" % network.essid)

        if network.ethtool:
            if network.ethtool.find("autoneg") == -1:
                network.ethtool = "autoneg off " + network.ethtool
            f.write("ETHTOOL_OPTS=%s\n" % network.ethtool)

        if network.bootProto.lower() == "dhcp":
            if network.hostname:
                f.write("DHCP_HOSTNAME=%s\n" % network.hostname)
            if network.dhcpclass:
                f.write("DHCP_CLASSID=%s\n" % network.dhcpclass)

        if network.mtu:
            f.write("MTU=%s\n" % network.mtu)

        f.close()

    def __writeNetworkKey(self, network):
        if not network.wepkey:
            return

        path = self.instroot + "/etc/sysconfig/network-scripts/keys-" + network.device
        f = file(path, "w+")
        os.chmod(path, 0600)
        f.write("KEY=%s\n" % network.wepkey)
        f.close()

    def __writeNetworkConfig(self, useipv6, hostname, gateway):
        path = self.instroot + "/etc/sysconfig/network"
        f = file(path, "w+")
        os.chmod(path, 0644)

        f.write("NETWORKING=yes\n")

        if useipv6:
            f.write("NETWORKING_IPV6=yes\n")
        else:
            f.write("NETWORKING_IPV6=no\n")

        if hostname:
            f.write("HOSTNAME=%s\n" % hostname)
        else:
            f.write("HOSTNAME=localhost.localdomain\n")

        if gateway:
            f.write("GATEWAY=%s\n" % gateway)

        f.close()

    def __writeNetworkHosts(self, hostname):
        localline = ""
        if hostname and hostname != "localhost.localdomain":
            localline += hostname + " "
            l = string.split(hostname, ".")
            if len(l) > 1:
                localline += l[0] + " "
        localline += "localhost.localdomain localhost"

        path = self.instroot + "/etc/hosts"
        f = file(path, "w+")
        os.chmod(path, 0644)
        f.write("127.0.0.1\t\t%s\n" % localline)
        f.write("::1\t\tlocalhost6.localdomain6 localhost6\n")
        f.close()

    def __writeNetworkResolv(self, nodns, nameservers):
        if nodns or not nameservers:
            return

        path = self.instroot + "/etc/resolv.conf"
        f = file(path, "w+")
        os.chmod(path, 0644)

        for ns in (nameservers):
            if ns:
                f.write("nameserver %s\n" % ns)

        f.close()

    def write(self):
        makedirs(self.instroot + "/etc/sysconfig/network-scripts")

        useipv6 = False
        nodns = False
        hostname = None
        gateway = None
        nameservers = None

        for network in self.ksnet.network:
            if not network.device:
                raise InstallationError("No --device specified with network kickstart command")

            if network.onboot and network.bootProto.lower() != "dhcp" and \
               not (network.ip and network.netmask):
                raise InstallationError("No IP address and/or netmask specified with static " +
                                        "configuration for '%s'" % network.device)

            self.__writeNetworkIfCfg(network)
            self.__writeNetworkKey(network)

            if network.ipv6:
                useipv6 = True
            if network.nodns:
                nodns = True

            if network.hostname:
                hostname = network.hostname
            if network.gateway:
                gateway = network.gateway

            if network.nameserver:
                nameservers = string.split(network.nameserver, ",")

        self.__writeNetworkConfig(useipv6, hostname, gateway)
        self.__writeNetworkHosts(hostname)
        self.__writeNetworkResolv(nodns, nameservers)

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
