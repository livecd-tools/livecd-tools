#
# kickstart.py : Apply kickstart configuration to a system
#
# Copyright 2007, Red Hat  Inc.
# Copyright 2016, Kevin Kofler
# Copyright 2016, Neal Gompa
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
import errno
import os.path
import shutil
import subprocess
import time
import logging

import urlgrabber

import pykickstart.commands as kscommands
import pykickstart.constants as ksconstants
import pykickstart.errors as kserrors
import pykickstart.parser as ksparser
import pykickstart.version as ksversion

import imgcreate.errors as errors
import imgcreate.fs as fs

def read_kickstart(path):
    """Parse a kickstart file and return a KickstartParser instance.

    This is a simple utility function which takes a path to a kickstart file,
    parses it and returns a pykickstart KickstartParser instance which can
    be then passed to an ImageCreator constructor.

    If an error occurs, a CreatorError exception is thrown.

    """
    version = ksversion.makeVersion()
    ks = ksparser.KickstartParser(version)
    try:
        # If kickstart file exists on the local filesystem, open it directly
        # so pykickstart knows how to handle relative %include. Otherwise,
        # treat as URL and download to temporary file before parsing.
        if os.path.exists(path):
            ks.readKickstart(path)
        else:
            tmpks = '.kstmp.{}'.format(os.getpid())
            ksfile = urlgrabber.urlgrab(path, filename=tmpks)
            ks.readKickstart(tmpks)
            os.unlink(tmpks)
# Fallback to e.args[0] is a workaround for bugs in urlgragger and pykickstart.
    except IOError as e:
        raise errors.KickstartError("Failed to read kickstart file "
                                    "'%s' : %s" % (path, e.strerror or
                                    e.args[0]))
    except kserrors.KickstartError as e:
        raise errors.KickstartError("Failed to parse kickstart file "
                                    "'%s' : %s" % (path, e))
    return ks

def build_name(kscfg, prefix = None, suffix = None, maxlen = None):
    """Construct and return an image name string.

    This is a utility function to help create sensible name and fslabel
    strings. The name is constructed using the sans-prefix-and-extension
    kickstart filename and the supplied prefix and suffix.

    If the name exceeds the maxlen length supplied, the prefix is first dropped
    and then the kickstart filename portion is reduced until it fits. In other
    words, the suffix takes precedence over the kickstart portion and the
    kickstart portion takes precedence over the prefix.

    kscfg -- a path to a kickstart file
    prefix -- a prefix to prepend to the name; defaults to None, which causes
              no prefix to be used
    suffix -- a suffix to append to the name; defaults to None, which causes
              a YYYYMMDDHHMM suffix to be used
    maxlen -- the maximum length for the returned string; defaults to None,
              which means there is no restriction on the name length

    Note, if maxlen is less then the len(suffix), you get to keep both pieces.

    """
    name = os.path.basename(kscfg)
    idx = name.rfind('.')
    if idx >= 0:
        name = name[:idx]

    if prefix is None:
        prefix = ""
    if suffix is None:
        suffix = time.strftime("%Y%m%d%H%M")

    if name.startswith(prefix):
        name = name[len(prefix):]

    ret = prefix + name + "-" + suffix
    if not maxlen is None and len(ret) > maxlen:
        ret = name[:maxlen - len(suffix) - 1] + "-" + suffix

    return ret

class KickstartConfig(object):
    """A base class for applying kickstart configurations to a system."""
    def __init__(self, instroot):
        self.instroot = instroot

    def path(self, subpath):
        return self.instroot + subpath

    def chroot(self):
        os.chroot(self.instroot)
        os.chdir("/")

    def call(self, args):
        try:
            return subprocess.call(args, preexec_fn=self.chroot)
        except OSError as e:
            if e.errno == errno.ENOENT:
                raise errors.KickstartError("Unable to run %s!" %(args))

    def apply(self):
        pass

class LanguageConfig(KickstartConfig):
    """A class to apply a kickstart language configuration to a system."""
    def apply(self, kslang):
        lang = kslang.lang or "en_US.UTF-8"

        f = open(self.path("/etc/locale.conf"), "w+")
        f.write("LANG=\"" + lang + "\"\n")
        f.close()

class KeyboardConfig(KickstartConfig):
    """A class to apply a kickstart keyboard configuration to a system."""
    def apply(self, kskeyboard):
        vcconf_file = self.path("/etc/vconsole.conf")
        DEFAULT_VC_FONT = "eurlatgr"

        if not kskeyboard.keyboard:
            kskeyboard.keyboard = "us"

        try:
            with open(vcconf_file, "w") as f:
                f.write('KEYMAP="%s"\n' % kskeyboard.keyboard)

                # systemd now defaults to a font that cannot display non-ascii
                # characters, so we have to tell it to use a better one
                f.write('FONT="%s"\n' % DEFAULT_VC_FONT)
        except IOError as e:
            logging.error("Cannot write vconsole configuration file: %s" % e)

class TimezoneConfig(KickstartConfig):
    """A class to apply a kickstart timezone configuration to a system."""
    def apply(self, kstimezone):
        tz = kstimezone.timezone or "America/New_York"
        utc = str(kstimezone.isUtc)

        # /etc/localtime is a symlink with glibc > 2.15-41
        # but if it exists as a file keep it as a file and fall back
        # to a symlink.
        localtime = self.path("/etc/localtime")
        if os.path.isfile(localtime) and \
           not os.path.islink(localtime):
            try:
                shutil.copy2(self.path("/usr/share/zoneinfo/%s" %(tz,)),
                                localtime)
            except (OSError, shutil.Error) as e:
                logging.error("Error copying timezone: %s" %(e.strerror,))
        else:
            if os.path.exists(localtime):
                os.unlink(localtime)
            os.symlink("/usr/share/zoneinfo/%s" %(tz,), localtime)

class AuthSelect(KickstartConfig):
    """A class to apply a kickstart authselect configuration to a system."""
    def apply(self, ksauthselect):

        auth = ksauthselect.authselect or "select sssd with-silent-lastlog --force"
        try:
            subprocess.call(['authselect'] + auth.split(), preexec_fn=self.chroot)
        except OSError as e:
            if e.errno == errno.ENOENT:
                logging.info('The authselect command is not available.')
                return

class FirewallConfig(KickstartConfig):
    """A class to apply a kickstart firewall configuration to a system."""
    def apply(self, ksfirewall):

        args = ["firewall-offline-cmd"]
        # enabled is None if neither --enable or --disable is passed
        # default to enabled if nothing has been set.
        if ksfirewall.enabled == False:
            args += ["--disabled"]
        else:
            args += ["--enabled"]

        for dev in ksfirewall.trusts:
            args += [ "--trust=%s" % (dev,) ]

        for port in ksfirewall.ports:
            args += [ "--port=%s" % (port,) ]

        for service in ksfirewall.services:
            args += [ "--service=%s" % (service,) ]

        try:
            subprocess.call(args, preexec_fn=self.chroot)
        except OSError as e:
            # Check to see if firewalld is available in the install image.
            if e.errno == errno.ENOENT:
                logging.warning('firewalld is not installed, '
                                'ignoring firewall configuration settings!')
                return

class RootPasswordConfig(KickstartConfig):
    """A class to apply a kickstart root password configuration to a system."""
    def lock(self):
        self.call(["passwd", "-l", "root"])

    def set_encrypted(self, password):
        self.call(["usermod", "-p", password, "root"])

    def set_unencrypted(self, password):

        try:
            p1 = subprocess.Popen(["echo", password],
                                  stdout=subprocess.PIPE,
                                  preexec_fn=self.chroot)
        except OSError as e:
            if e.errno == errno.ENOENT:
                raise errors.KickstartError("Unable to set unencrypted "
                                            "password due to lack of 'echo'.")

        try:
            p2 = subprocess.Popen(["passwd", "--stdin", "root"],
                                  stdin=p1.stdout,
                                  stdout=subprocess.PIPE,
                                  preexec_fn=self.chroot)
        except OSError as e:
            if e.errno == errno.ENOENT:
                raise errors.KickstartError("Unable to set unencrypted "
                                           "password due to lack of 'passwd'.")

        p2.communicate()

    def apply(self, ksrootpw):
        if ksrootpw.isCrypted:
            self.set_encrypted(ksrootpw.password)
        elif ksrootpw.password != "":
            self.set_unencrypted(ksrootpw.password)

        if ksrootpw.lock:
            self.lock()

class ServicesConfig(KickstartConfig):
    """A class to apply a kickstart services configuration to a system."""
    def apply(self, ksservices):

        if fs.chrootentitycheck('systemctl', self.instroot):
            for s in ksservices.enabled:
                subprocess.call(['systemctl', 'enable', s], preexec_fn=self.chroot)
            for s in ksservices.disabled:
                subprocess.call(['systemctl', 'disable', s], preexec_fn=self.chroot)

class XConfig(KickstartConfig):
    """A class to apply a kickstart X configuration to a system."""
    RUNLEVELS = {3: 'multi-user.target', 5: 'graphical.target'}

    def apply(self, ksxconfig):
        if ksxconfig.defaultdesktop:
            f = open(self.path("/etc/sysconfig/desktop"), "w")
            f.write("DESKTOP="+ksxconfig.defaultdesktop+"\n")
            f.close()

        if ksxconfig.startX:
            if not os.path.isdir(self.path('/etc/systemd/system')):
                logging.warning("there is no /etc/systemd/system directory, cannot update default.target!")
                return
            default_target = self.path('/etc/systemd/system/default.target')
            if os.path.islink(default_target):
                 os.unlink(default_target)
            os.symlink('/lib/systemd/system/graphical.target', default_target)

class RPMMacroConfig(KickstartConfig):
    """A class to apply the specified rpm macros to the filesystem"""
    def apply(self, ks):
        if not ks:
            return
        f = open(self.path("/etc/rpm/macros.imgcreate"), "w+")
        if exclude_docs(ks):
            f.write("%_excludedocs 1\n")
        if not selinux_enabled(ks):
            f.write("%__file_context_path %{nil}\n")
        if inst_langs(ks) != None:
            f.write("%_install_langs ")
            f.write(inst_langs(ks))
            f.write("\n")
        f.close()

class NetworkConfig(KickstartConfig):
    """A class to apply a kickstart network configuration to a system."""
    def write_ifcfg(self, network):
        p = self.path("/etc/sysconfig/network-scripts/ifcfg-" + network.device)

        f = open(p, "w+")
        os.chmod(p, 0o644)

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

    def write_wepkey(self, network):
        if not network.wepkey:
            return

        p = self.path("/etc/sysconfig/network-scripts/keys-" + network.device)
        f = open(p, "w+")
        os.chmod(p, 0o600)
        f.write("KEY=%s\n" % network.wepkey)
        f.close()

    def write_sysconfig(self, useipv6, hostname, gateway):
        path = self.path("/etc/sysconfig/network")
        f = open(path, "w+")
        os.chmod(path, 0o644)

        f.write("NETWORKING=yes\n")

        if useipv6:
            f.write("NETWORKING_IPV6=yes\n")
        else:
            f.write("NETWORKING_IPV6=no\n")

        if gateway:
            f.write("GATEWAY=%s\n" % gateway)

        f.close()

    def write_hosts(self, hostname):
        localline = ""
        if hostname and hostname != "localhost.localdomain":
            localline += hostname + " "
            l = hostname.split(".")
            if len(l) > 1:
                localline += l[0] + " "
        localline += "localhost.localdomain localhost"

        path = self.path("/etc/hosts")
        f = open(path, "w+")
        os.chmod(path, 0o644)
        f.write("127.0.0.1\t\t%s\n" % localline)
        f.write("::1\t\tlocalhost6.localdomain6 localhost6\n")
        f.close()

    def write_hostname(self, hostname):
        if not hostname:
            return

        path = self.path("/etc/hostname")
        f = open(path, "w+")
        os.chmod(path, 0o644)
        f.write("%s\n" % (hostname,))
        f.close()

    def write_resolv(self, nodns, nameservers):
        if nodns or not nameservers:
            return

        path = self.path("/etc/resolv.conf")
        # Explicitly overwrite what's there now, see https://bugzilla.redhat.com/show_bug.cgi?id=1116651
        try:
            os.unlink(path)
        except OSError as e:
            if e.errno != errno.ENOENT:
                raise
        f = open(path, "w+")
        os.chmod(path, 0o644)

        for ns in (nameservers):
            if ns:
                f.write("nameserver %s\n" % ns)

        f.close()

    def apply(self, ksnet):
        fs.makedirs(self.path("/etc/sysconfig/network-scripts"))

        useipv6 = False
        nodns = False
        hostname = None
        gateway = None
        nameservers = None

        for network in ksnet.network:
            if not network.device:
                raise errors.KickstartError("No --device specified with "
                                            "network kickstart command")

            if (network.onboot and network.bootProto.lower() != "dhcp" and 
                not (network.ip and network.netmask)):
                raise errors.KickstartError("No IP address and/or netmask "
                                            "specified with static "
                                            "configuration for '%s'" %
                                            network.device)

            self.write_ifcfg(network)
            self.write_wepkey(network)

            if network.ipv6:
                useipv6 = True
            if network.nodns:
                nodns = True

            if network.hostname:
                hostname = network.hostname
            if network.gateway:
                gateway = network.gateway

            if network.nameserver:
                nameservers = network.nameserver.split(",")

        self.write_sysconfig(useipv6, hostname, gateway)
        self.write_hosts(hostname)
        self.write_hostname(hostname)
        self.write_resolv(nodns, nameservers)

class SelinuxConfig(KickstartConfig):
    """A class to apply a kickstart selinux configuration to a system."""

    def relabel(self, ksselinux, policy_name):
        # touch some files which get unhappy if they're not labeled correctly
        for fn in ("/etc/resolv.conf",):
            path = self.path(fn)
            if not os.path.islink(path):
                f = open(path, "a")
                os.chmod(path, 0o644)
                f.close()

        if ksselinux.selinux == ksconstants.SELINUX_DISABLED:
            return

        # detect selinux policy file locations
        policy_file = self.find_policy_file(policy_name)
        file_context = '/etc/selinux/%s/contexts/files/file_contexts' % (policy_name)

        try:
            rc = subprocess.call(['setfiles', '-F', '-p', '-e', '/proc',
                                  '-e', '/sys', '-e', '/dev',
                                  '-c', policy_file,
                                  file_context, '/'],
                                 preexec_fn=self.chroot)
        except OSError as e:
            if e.errno == errno.ENOENT:
                logging.info('The setfiles command is not available.')
                return
        if rc:
            if ksselinux.selinux == ksconstants.SELINUX_ENFORCING:
                raise errors.KickstartError("SELinux relabel failed.")
            else:
                logging.error("SELinux relabel failed.")

    def apply(self, ksselinux):
        selinux_config = "/etc/selinux/config"
        if not os.path.exists(self.instroot+selinux_config):
            return

        if ksselinux.selinux == ksconstants.SELINUX_ENFORCING:
            cmd = "SELINUX=enforcing\n"
        elif ksselinux.selinux == ksconstants.SELINUX_PERMISSIVE:
            cmd = "SELINUX=permissive\n"
        elif ksselinux.selinux == ksconstants.SELINUX_DISABLED:
            cmd = "SELINUX=disabled\n"
        else:
            return

        # Detect policy name
        lines = open(self.instroot+selinux_config).readlines()
        policy_name = next(_findprefix('SELINUXTYPE=', lines), 'targeted')

        # Replace the SELINUX line in the config
        with open(self.instroot+selinux_config, "w") as f:
            for line in lines:
                if line.startswith("SELINUX="):
                    f.write(cmd)
                else:
                    f.write(line)

        self.relabel(ksselinux, policy_name)

    def find_policy_file(self, policy_name):
        """ Search for the SELinux binary policy file for policy_name """
        guest_path = '/etc/selinux/%s/policy/' % (policy_name)
        with os.scandir('%s%s' % (self.instroot, guest_path)) as sd:
            for entry in sd:
                if entry.is_file() and entry.name.startswith('policy.'):
                    return guest_path + entry.name
        raise errors.CreatorError(
            "Unable to find SELinux binary policy file in \"%s\"" %
            (guest_path))

def get_image_size(ks, default = None):
    __size = 0
    for p in ks.handler.partition.partitions:
        if p.mountpoint == "/" and p.size:
            __size = p.size
    if __size > 0:
        return int(__size) * 1024 * 1024
    else:
        return default

def get_image_fstype(ks, default = None):
    for p in ks.handler.partition.partitions:
        if p.mountpoint == "/" and p.fstype:
            return p.fstype
    return default

def get_timeout(ks, default = None):
    if not hasattr(ks.handler.bootloader, "timeout"):
        return default
    if ks.handler.bootloader.timeout is None:
        return default
    return int(ks.handler.bootloader.timeout)

def get_kernel_args(ks, default = "ro rd.live.image quiet"):
    if not hasattr(ks.handler.bootloader, "appendLine"):
        return default
    if ks.handler.bootloader.appendLine is None:
        return default
    return "%s %s" %(default, ks.handler.bootloader.appendLine)

def get_default_kernel(ks, default = None):
    if not hasattr(ks.handler.bootloader, "default"):
        return default
    if not ks.handler.bootloader.default:
        return default
    return ks.handler.bootloader.default

def get_repos(ks, repo_urls = {}):
    repos = {}
    for repo in ks.handler.repo.repoList:
        inc = []
        if hasattr(repo, "includepkgs"):
            inc.extend(repo.includepkgs)

        exc = []
        if hasattr(repo, "excludepkgs"):
            exc.extend(repo.excludepkgs)

        baseurl = repo.baseurl
        mirrorlist = repo.mirrorlist
        proxy = repo.proxy
        sslverify = not repo.noverifyssl

        if repo.name in repo_urls:
            baseurl = repo_urls[repo.name]
            mirrorlist = None

        if repo.name in repos:
            logging.warning("Overriding already specified repo %s" %(repo.name,))
        repos[repo.name] = (repo.name, baseurl, mirrorlist, proxy, inc, exc, repo.cost, sslverify)

    return repos.values()

def convert_method_to_repo(ks):
    try:
        ks.handler.repo.methodToRepo()
    except (AttributeError, kserrors.KickstartError):
        pass

def get_packages(ks, required = []):
    return ks.handler.packages.packageList + required

def get_groups(ks, required = []):
    return ks.handler.packages.groupList + required

def get_environment(ks):
    if hasattr(ks.handler.packages, "environment"):
        if ks.handler.packages.environment:
            return ks.handler.packages.environment
    return None

def get_excluded(ks, required = []):
    return ks.handler.packages.excludedList + required

def get_excluded_groups(ks, required = []):
    return ks.handler.packages.excludedGroupList + required

def get_partitions(ks, required = []):
    return ks.handler.partition.partitions

def ignore_missing(ks):
    return ks.handler.packages.handleMissing == ksconstants.KS_MISSING_IGNORE

def exclude_docs(ks):
    return ks.handler.packages.excludeDocs

def exclude_weakdeps(ks):
    if hasattr(ks.handler.packages, "excludeWeakdeps"):
        if ks.handler.packages.excludeWeakdeps:
            return ks.handler.packages.excludeWeakdeps
    return None

def nocore(ks):
    return ks.handler.packages.nocore

def inst_langs(ks):
    if hasattr(ks.handler.packages, "instLange"):
        return ks.handler.packages.instLange
    elif hasattr(ks.handler.packages, "instLangs"):
        return ks.handler.packages.instLangs
    return ""

def get_pre_scripts(ks):
    scripts = []
    for s in ks.handler.scripts:
        if s.type != ksconstants.KS_SCRIPT_PRE:
            continue
        scripts.append(s)
    return scripts

def get_post_scripts(ks):
    scripts = []
    for s in ks.handler.scripts:
        if s.type != ksconstants.KS_SCRIPT_POST:
            continue
        scripts.append(s)
    return scripts

def selinux_enabled(ks):
    return ks.handler.selinux.selinux in (ksconstants.SELINUX_ENFORCING,
                                          ksconstants.SELINUX_PERMISSIVE)

def _findprefix(prefix, linesiter):
    """ Searches for lines starting with prefix
        Emits only matching lines without the prefix. """
    def getmatch(line):
        if line.startswith(prefix):
            return line[len(prefix):].rstrip()

    return filter(None, map(getmatch, linesiter))
