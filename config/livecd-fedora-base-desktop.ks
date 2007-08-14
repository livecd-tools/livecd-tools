lang en_US.UTF-8
keyboard us
timezone US/Eastern
auth --useshadow --enablemd5
selinux --enforcing
firewall --disabled
xconfig --startxonboot
services --enabled=NetworkManager,dhcdbd --disabled=network,sshd

repo --name=development --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=rawhide&arch=$basearch

%packages
@base-x
@games
@base
@core
@admin-tools
@dial-up
@hardware-support
@printing
syslinux
kernel
memtest86+

scim*
-scim-devel
-scim-doc
-scim-qtimm
-scim-bridge-qt
-scim-bridge-qt4
-scim-skk
-scim-tomoe
-scim-tables*
-scim-tables
-scim-fcitx*
-scim-skk
-scim-lang*

m17n-lib
m17n-db
#m17n-db-*

fonts-*

# dictionaries are big
-aspell-*
-m17n-db-*
-man-pages-*
# lose the compat stuff
-compat*

# save some space
-specspo
-esc
-samba-client
-a2ps
-redhat-lsb
-sox
# smartcards won't really work on the livecd.  
-coolkey
-ccid
# duplicate functionality
-pinfo
-vorbis-tools
-wget

# scanning takes quite a bit of space :/
-xsane
-xsane-gimp
-sane-backends

# lots of people want to have this
gparted

# livecd bits to set up the livecd and be able to install
anaconda
anaconda-runtime

# make sure debuginfo doesn't end up on the live image
-*debuginfo

%post
# FIXME: it'd be better to get this installed from a package
cat > /etc/rc.d/init.d/fedora-live << EOF
#!/bin/bash
#
# live: Init script for live image
#
# chkconfig: 345 00 99
# description: Init script for live image.

. /etc/init.d/functions

if ! strstr "\`cat /proc/cmdline\`" liveimg || [ "\$1" != "start" ] || [ -e /.liveimg-configured ] ; then
    exit 0
fi

exists() {
    which \$1 >/dev/null 2>&1 || return
    \$*
}

touch /.liveimg-configured

# mount live image
if [ -b /dev/live ]; then
   mkdir -p /mnt/live
   mount -o ro /dev/live /mnt/live
fi

# configure X
exists system-config-display --noui --reconfig --set-depth=24

# unmute sound card
exists alsaunmute 0 2> /dev/null

# add fedora user with no passwd
useradd -c "Fedora Live" fedora
passwd -d fedora > /dev/null

# turn off firstboot for livecd boots
echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

# don't start yum-updatesd for livecd boots
chkconfig --level 345 yum-updatesd off

# don't start cron/at as they tend to spawn things which are
# disk intensive that are painful on a live image
chkconfig --level 345 crond off
chkconfig --level 345 atd off
chkconfig --level 345 anacron off
chkconfig --level 345 readahead_early off
chkconfig --level 345 readahead_later off

# Stopgap fix for RH #217966; should be fixed in HAL instead
touch /media/.hal-mtab
EOF

chmod 755 /etc/rc.d/init.d/fedora-live
/sbin/restorecon /etc/rc.d/init.d/fedora-live
/sbin/chkconfig --add fedora-live

# save a little bit of space at least...
rm -f /boot/initrd*

