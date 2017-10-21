lang en_US.UTF-8
keyboard us
timezone US/Eastern
auth --useshadow --passalgo=sha512
selinux --disabled
firewall --disabled
part / --size 1536

repo --name=cauldron-i586 --mirrorlist=https://www.mageia.org/mirrorlist/?release=cauldron&arch=i586&section=core&repo=release


%packages --nocore
basesystem
kernel-desktop-latest
locales-en
dnf
dnf-plugins-core
-perl-URPM
-urpmi

%end
