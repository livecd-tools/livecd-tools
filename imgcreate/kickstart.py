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
import string

from imgcreate.fs import *

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
