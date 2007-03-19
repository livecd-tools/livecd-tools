lang en_US.UTF-8
keyboard us
timezone US/Eastern
auth --useshadow --enablemd5
selinux --enforcing
firewall --disabled

# TODO: how to replace i386 with $basearch

# TODO: apparently calling it fedora-dev instead of a-dev makes things
# not work. Perhaps it has something to do with the default repos in
# /etc/yum.repos.d not getting properly disabled?

repo --name=a-dev --baseurl=http://download.fedora.redhat.com/pub/fedora/linux/core/development/i386/os
repo --name=a-extras-dev --baseurl=http://download.fedora.redhat.com/pub/fedora/linux/extras/development/i386

%packages
bash
kernel
syslinux
passwd
policycoreutils
chkconfig
authconfig
rootfiles

