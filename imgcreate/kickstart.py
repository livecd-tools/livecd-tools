#!/usr/bin/python -tt
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
import string
import subprocess

import pykickstart.commands as kscommands
import pykickstart.constants as ksconstants
import pykickstart.errors as kserrors
import pykickstart.parser as ksparser
import pykickstart.version as ksversion

import imgcreate.errors as errors
import imgcreate.fs as fs

def read_kickstart(path):
    version = ksversion.makeVersion()
    ks = ksparser.KickstartParser(version)
    try:
        ks.readKickstart(path)
    except IOError, (err, msg):
        raise errors.KickstartError("Failed to read kickstart file "
                                    "'%s' : %s" % (kscfg, msg))
    except kserrors.KickstartError, e:
        raise errors.KickstartError("Failed to parse kickstart file "
                                    "'%s' : %s" % (kscfg, e))
    return ks

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
        #
        # FIXME:
        #   should this impact the X keyboard config too?
        #   or do we want to make X be able to do this mapping?
        #
        import rhpl.keyboard
        k = rhpl.keyboard.Keyboard()
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
        #
        # FIXME: should handle the rest of the options
        #
        if not ksfirewall.enabled:
            return
        if not os.path.exists(self.path("/usr/sbin/lokkit")):
            return
        self.call(["/usr/sbin/lokkit",
                   "-f", "--quiet", "--nostart", "--enabled"])
        
class RootPasswordConfig(KickstartConfig):
    """A class to apply a kickstart root password configuration to a system."""
    def unset(self):
        self.call(["/usr/bin/passwd", "-d", "root"])
        
    def set_encrypted(self, password):
        self.call(["/usr/sbin/usermod", "-p", password, "root"])

    def set_unencrypted(self, password):
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
        if not ksxconfig.startX:
            return
        f = open(self.path("/etc/inittab"), "rw+")
        buf = f.read()
        buf = buf.replace("id:3:initdefault", "id:5:initdefault")
        f.seek(0)
        f.write(buf)
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
            l = string.split(hostname, ".")
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
                raise errros.KickstartError("No --device specified with "
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
                nameservers = string.split(network.nameserver, ",")

        self.write_sysconfig(useipv6, hostname, gateway)
        self.write_hosts(hostname)
        self.write_resolv(nodns, nameservers)

class SelinuxConfig(KickstartConfig):
    """A class to apply a kickstart selinux configuration to a system."""
    def relabel(self, ksselinux):
        # touch some files which get unhappy if they're not labeled correctly
        for fn in ("/etc/modprobe.conf", "/etc/resolv.conf"):
            path = self.path(fn)
            f = file(path, "w+")
            os.chmod(path, 0644)

        if not ksselinux.selinux:
            return
        if not os.path.exists(self.path("/sbin/restorecon")):
            return

        self.call(["/sbin/restorecon", "-l", "-v", "-r", "/"])

    def apply(self, ksselinux):
        if os.path.exists(self.path("/usr/sbin/lokkit")):
            args = ["/usr/sbin/lokkit", "-f", "--quiet", "--nostart"]

            if ksselinux.selinux:
                args.append("--selinux=enforcing")
            else:
                args.append("--selinux=disabled")

            self.call(args)

        self.relabel(ksselinux)

def get_image_size(ks, default = None):
    for p in ks.partition.partitions:
        if p.mountpoint == "/" and p.size:
            return int(p.size) * 1024L * 1024L
    return default

def get_modules(ks):
    devices = []
    if isinstance(ks.device, kscommands.device.FC3_Device):
        devices.append(ks.device)
    else:
        devices.extend(ks.device.deviceList)

    modules = []
    for device in devices:
        if not device.moduleName:
            continue
        modules.extend(device.moduleName.split(":"))

    return modules

def get_timeout(ks, default = None):
    if not hasattr(ks.bootloader, "timeout"):
        return default
    if ks.bootloader.timeout is None:
        return default
    return int(ks.bootloader.timeout)

def get_default_kernel(ks, default = None):
    if not hasattr(ks.bootloader, "default"):
        return default
    if not ks.bootloader.default:
        return default
    return ks.bootloader.default

def get_repos(ks, repo_urls = {}):
    repos = []
    for repo in ks.repo.repoList:
        inc = []
        if hasattr(repo, "inc"):
            inc.extend(repo.includepkgs)

        exc = []
        if hasattr(repo, "exc"):
            exc.extend(repo.excludepkgs)

        baseurl = repo.baseurl
        mirrorlist = repo.mirrorlist
        
        if repo.name in repo_urls:
            baseurl = repo_urls[repo.name]
            mirrorlist = None

        repos.append((repo.name, baseurl, mirrorlist, inc, exc))

    return repos

def convert_method_to_repo(ks):
    try:
        ks.repo.methodToRepo()
    except (AttributeError, kserrors.KickstartError):
        pass

def get_packages(ks, required = []):
    return ks.packages.packageList + required

def get_groups(ks, required = []):
    return ks.packages.groupList + required

def get_excluded(ks, required = []):
    return ks.packages.excludedList + required

def ignore_missing(ks):
    return ks.packages.handleMissing == ksconstants.KS_MISSING_IGNORE

def exclude_docs(ks):
    return ks.packages.excludeDocs

def get_post_scripts(ks):
    scripts = []
    for s in ks.scripts:
        if s.type != ksparser.KS_SCRIPT_POST:
            continue
        scripts.append(s)
    return scripts

def selinux_enabled(ks):
    return ks.selinux.selinux
