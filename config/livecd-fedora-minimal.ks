lang en_US.UTF-8
keyboard us
timezone US/Eastern
auth --useshadow --enablemd5
selinux --enforcing
firewall --disabled
part / --size 1024

repo --name=development --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=rawhide&arch=$basearch


%packages
@core
anaconda-runtime
bash
kernel
passwd
policycoreutils
chkconfig
authconfig
rootfiles

%end
