lang en_US.UTF-8
keyboard us
timezone US/Eastern
auth --useshadow --enablemd5
selinux --enforcing
firewall --disabled
repo --name=d7 --baseurl=http://download.fedora.redhat.com/pub/fedora/linux/core/development/i386/os
repo --name=e7 --baseurl=http://download.fedora.redhat.com/pub/fedora/linux/extras/development/i386
xconfig --startxonboot
services --enabled=NetworkManager,dhcdbd --disabled=network,sshd

%packages
# basic desktop packages
@graphical-internet
@graphics
@sound-and-video
@gnome-desktop
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

scim*
-scim-devel
-scim-doc
-scim-qtimm
-scim-bridge-qt
-scim-skk
-scim-tomoe
-scim-tables-chinese

m17n-lib
m17n-db
#m17n-db-*

fonts-*

# dictionaries are big
-aspell-*
-m17n-db-*
-man-pages-*
# gimp help is huge
-gimp-help
# lose the compat stuff
-compat*

# space sucks
-ekiga
-gnome-user-docs
-specspo
-esc
-samba-client
-a2ps
-vino
-redhat-lsb
-sox

# smartcards won't really work on the livecd.  and we _need_ space
-coolkey
-ccid

# duplicate functionality
-pinfo
-vorbis-tools
-wget


# scanning takes quite a bit of space :/
-xsane
-xsane-gimp

# while hplip requires pyqt, it has to go
-hplip

# added games
#monkey-bubble
#ppracer

# we don't include @office so that we don't get OOo.  but some nice bits
abiword
gnumeric
evince
gnome-blog
-planner

# lots of people want...
gparted
ntfs-3g
ntfsprogs

# livecd bits to set up the livecd and be able to install
anaconda
anaconda-runtime


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
# disable screensaver locking
gconftool-2 --direct --config-source=xml:readwrite:/etc/gconf/gconf.xml.defaults -s -t bool /apps/gnome-screensaver/lock_enabled false >/dev/null
if [ -e /usr/share/icons/hicolor/96x96/apps/fedora-logo-icon.png ] ; then
    cp /usr/share/icons/hicolor/96x96/apps/fedora-logo-icon.png /home/fedora/.face
    chown fedora:fedora /home/fedora/.face
    # TODO: would be nice to get e-d-s to pick this one up too... but how?
fi

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
