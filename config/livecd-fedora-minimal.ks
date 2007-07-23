lang en_US.UTF-8
keyboard us
timezone US/Eastern
auth --useshadow --enablemd5
selinux --enforcing
firewall --disabled

# TODO: how to replace i386 with $basearch
repo --name=development --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=rawhide&arch=i386


%packages
@core
bash
kernel
syslinux
passwd
policycoreutils
chkconfig
authconfig
rootfiles

