lang en_US.UTF-8
keyboard us
timezone US/Eastern
authselect select sssd with-silent-lastlog --force
selinux --disabled
firewall --disabled
part / --size 1536

repo --name=cauldron-x86_64 --mirrorlist=https://www.mageia.org/mirrorlist/?release=cauldron&arch=x86_64&section=core&repo=release


%packages --nocore
basesystem
kernel-desktop-latest
locales-en
dnf
dnf-plugins-core
-perl-URPM
-urpmi

%end
