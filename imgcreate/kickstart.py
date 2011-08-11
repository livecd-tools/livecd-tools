#
# kickstart.py : Apply kickstart configuration to a system
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
import shutil
import subprocess
import time
import logging
import urlgrabber
import selinux

try:
    import system_config_keyboard.keyboard as keyboard
except ImportError:
    import rhpl.keyboard as keyboard

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
        ksfile = urlgrabber.urlgrab(path)
        ks.readKickstart(ksfile)
# Fallback to e.args[0] is a workaround for bugs in urlgragger and pykickstart.
    except IOError, e:
        raise errors.KickstartError("Failed to read kickstart file "
                                    "'%s' : %s" % (path, e.strerror or
                                    e.args[0]))
    except kserrors.KickstartError, e:
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
        if not os.path.exists("%s/%s" %(self.instroot, args[0])):
            raise errors.KickstartError("Unable to run %s!" %(args))
        subprocess.call(args, preexec_fn = self.chroot)

    def apply(self):
        pass

class LanguageConfig(KickstartConfig):
    """A class to apply a kickstart language configuration to a system."""
    def apply(self, kslang):
        lang = kslang.lang or "en_US.UTF-8"

        f = open(self.path("/etc/sysconfig/i18n"), "w+")
        f.write("LANG=\"" + lang + "\"\n")
        f.close()

class KeyboardConfig(KickstartConfig):
    """A class to apply a kickstart keyboard configuration to a system."""
    def apply(self, kskeyboard):
        k = keyboard.Keyboard()
        if kskeyboard.keyboard:
            k.set(kskeyboard.keyboard)
        k.write(self.instroot)

class TimezoneConfig(KickstartConfig):
    """A class to apply a kickstart timezone configuration to a system."""
    def apply(self, kstimezone):
        tz = kstimezone.timezone or "America/New_York"
        utc = str(kstimezone.isUtc)

        f = open(self.path("/etc/sysconfig/clock"), "w+")
        f.write("ZONE=\"" + tz + "\"\n")
        f.write("UTC=" + utc + "\n")
        f.close()
        try:
            shutil.copyfile(self.path("/usr/share/zoneinfo/%s" %(tz,)),
                            self.path("/etc/localtime"))
        except OSError, e:
            log.error("Error copying timezone: %s" %(e.strerror,))


class AuthConfig(KickstartConfig):
    """A class to apply a kickstart authconfig configuration to a system."""
    def apply(self, ksauthconfig):
        if not os.path.exists(self.path("/usr/sbin/authconfig")):
            return

        auth = ksauthconfig.authconfig or "--useshadow --enablemd5"
        args = ["/usr/sbin/authconfig", "--update", "--nostart"]
        self.call(args + auth.split())

class FirewallConfig(KickstartConfig):
    """A class to apply a kickstart firewall configuration to a system."""
    def apply(self, ksfirewall):
        if not os.path.exists(self.path("/usr/sbin/lokkit")):
            return
        args = ["/usr/sbin/lokkit", "-f", "--quiet", "--nostart"]
        if ksfirewall.enabled:
            args.append("--enabled")

            for port in ksfirewall.ports:
                args.append("--port=%s" %(port,))
            for svc in ksfirewall.services:
                args.append("--service=%s" %(svc,))
            for dev in ksfirewall.trusts:
                args.append("--trust=%s" %(dev,))
        else:
            args.append("--disabled")

        self.call(args)
        
class RootPasswordConfig(KickstartConfig):
    """A class to apply a kickstart root password configuration to a system."""
    def unset(self):
        self.call(["/usr/bin/passwd", "-d", "root"])
        
    def set_encrypted(self, password):
        self.call(["/usr/sbin/usermod", "-p", password, "root"])

    def set_unencrypted(self, password):
        for p in ("/bin/echo", "/usr/bin/passwd"):
            if not os.path.exists("%s/%s" %(self.instroot, p)):
                raise errors.KickstartError("Unable to set unencrypted password due to lack of %s" % p)

        p1 = subprocess.Popen(["/bin/echo", password],
                              stdout = subprocess.PIPE,
                              preexec_fn = self.chroot)
        p2 = subprocess.Popen(["/usr/bin/passwd", "--stdin", "root"],
                              stdin = p1.stdout,
                              stdout = subprocess.PIPE,
                              preexec_fn = self.chroot)
        p2.communicate()

    def apply(self, ksrootpw):
        if ksrootpw.isCrypted:
            self.set_encrypted(ksrootpw.password)
        elif ksrootpw.password != "":
            self.set_unencrypted(ksrootpw.password)
        else:
            self.unset()

class ServicesConfig(KickstartConfig):
    """A class to apply a kickstart services configuration to a system."""
    def apply(self, ksservices):
        if not os.path.exists(self.path("/sbin/chkconfig")):
            return
        for s in ksservices.enabled:
            self.call(["/sbin/chkconfig", s, "on"])
        for s in ksservices.disabled:
            self.call(["/sbin/chkconfig", s, "off"])

class XConfig(KickstartConfig):
    """A class to apply a kickstart X configuration to a system."""
    def apply(self, ksxconfig):
        if ksxconfig.startX:
            f = open(self.path("/etc/inittab"), "rw+")
            buf = f.read()
            buf = buf.replace("id:3:initdefault", "id:5:initdefault")
            f.seek(0)
            f.write(buf)
            f.close()
        if ksxconfig.defaultdesktop:
            f = open(self.path("/etc/sysconfig/desktop"), "w")
            f.write("DESKTOP="+ksxconfig.defaultdesktop+"\n")
            f.close()

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

        f = file(p, "w+")
        os.chmod(p, 0644)

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
        f = file(p, "w+")
        os.chmod(p, 0600)
        f.write("KEY=%s\n" % network.wepkey)
        f.close()

    def write_sysconfig(self, useipv6, hostname, gateway):
        path = self.path("/etc/sysconfig/network")
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

    def write_hosts(self, hostname):
        localline = ""
        if hostname and hostname != "localhost.localdomain":
            localline += hostname + " "
            l = hostname.split(".")
            if len(l) > 1:
                localline += l[0] + " "
        localline += "localhost.localdomain localhost"

        path = self.path("/etc/hosts")
        f = file(path, "w+")
        os.chmod(path, 0644)
        f.write("127.0.0.1\t\t%s\n" % localline)
        f.write("::1\t\tlocalhost6.localdomain6 localhost6\n")
        f.close()

    def write_resolv(self, nodns, nameservers):
        if nodns or not nameservers:
            return

        path = self.path("/etc/resolv.conf")
        f = file(path, "w+")
        os.chmod(path, 0644)

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
        self.write_resolv(nodns, nameservers)

class SelinuxConfig(KickstartConfig):
    """A class to apply a kickstart selinux configuration to a system."""
    def relabel(self, ksselinux):
        # touch some files which get unhappy if they're not labeled correctly
        for fn in ("/etc/resolv.conf",):
            path = self.path(fn)
            f = file(path, "w+")
            os.chmod(path, 0644)
            f.close()

        if ksselinux.selinux == ksconstants.SELINUX_DISABLED:
            return

        if not os.path.exists(self.path("/sbin/setfiles")):
            return

        self.call(["/sbin/setfiles", "-p", "-e", "/proc", "-e", "/sys", "-e", "/dev", selinux.selinux_file_context_path(), "/"])

    def apply(self, ksselinux):
        if os.path.exists(self.path("/usr/sbin/lokkit")):
            args = ["/usr/sbin/lokkit", "-f", "--quiet", "--nostart"]

            if ksselinux.selinux == ksconstants.SELINUX_ENFORCING:
                args.append("--selinux=enforcing")
            if ksselinux.selinux == ksconstants.SELINUX_PERMISSIVE:
                args.append("--selinux=permissive")
            if ksselinux.selinux == ksconstants.SELINUX_DISABLED:
                args.append("--selinux=disabled")

            self.call(args)

        self.relabel(ksselinux)

def get_image_size(ks, default = None):
    __size = 0
    for p in ks.handler.partition.partitions:
        if p.mountpoint == "/" and p.size:
            __size = p.size
    if __size > 0:
        return int(__size) * 1024L * 1024L
    else:
        return default

def get_image_fstype(ks, default = None):
    for p in ks.handler.partition.partitions:
        if p.mountpoint == "/" and p.fstype:
            return p.fstype
    return default

def get_modules(ks):
    devices = []
    if not hasattr(ks.handler.device, "deviceList"):
        devices.append(ks.handler.device)
    else:
        devices.extend(ks.handler.device.deviceList)

    modules = []
    for device in devices:
        if not device.moduleName:
            continue
        modules.extend(device.moduleName.split(":"))

    return modules

def get_timeout(ks, default = None):
    if not hasattr(ks.handler.bootloader, "timeout"):
        return default
    if ks.handler.bootloader.timeout is None:
        return default
    return int(ks.handler.bootloader.timeout)

def get_kernel_args(ks, default = "ro liveimg quiet"):
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

        if repo.name in repo_urls:
            baseurl = repo_urls[repo.name]
            mirrorlist = None

        if repos.has_key(repo.name):
            logging.warn("Overriding already specified repo %s" %(repo.name,))
        repos[repo.name] = (repo.name, baseurl, mirrorlist, proxy, inc, exc)

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

def get_excluded(ks, required = []):
    return ks.handler.packages.excludedList + required

def get_partitions(ks, required = []):
    return ks.handler.partition.partitions

def ignore_missing(ks):
    return ks.handler.packages.handleMissing == ksconstants.KS_MISSING_IGNORE

def exclude_docs(ks):
    return ks.handler.packages.excludeDocs

def inst_langs(ks):
    if hasattr(ks.handler.packages, "instLange"):
        return ks.handler.packages.instLange
    elif hasattr(ks.handler.packages, "instLangs"):
        return ks.handler.packages.instLangs
    return ""

def get_post_scripts(ks):
    scripts = []
    for s in ks.handler.scripts:
        if s.type != ksparser.KS_SCRIPT_POST:
            continue
        scripts.append(s)
    return scripts

def selinux_enabled(ks):
    return ks.handler.selinux.selinux == ksconstants.SELINUX_ENFORCING
