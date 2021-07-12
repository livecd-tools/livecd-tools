lang en_US.UTF-8
keyboard us
timezone US/Eastern
authselect select sssd with-silent-lastlog --force
selinux --enforcing
firewall --disabled
part / --size 2048

repo --name=development --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=rawhide&arch=$basearch


%packages
@standard

%end
