lang en_US.UTF-8
keyboard us
timezone US/Eastern
auth --useshadow --enablemd5
selinux --enforcing
firewall --disabled
repo --name=d7 --baseurl=http://download.fedora.redhat.com/pub/fedora/linux/core/development/i386/os
repo --name=e7 --baseurl=http://download.fedora.devel.redhat.com/pub/fedora/linux/extras/development/i386 
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
kernel

scim*
-scim-devel
-scim-doc
-scim-qt
# work around yum API bug with specifying wildcards for now 
scim-tables
scim-tables-*
scim-sinhala
scim-libs
scim-bridge
scim-bridge-gtk
scim-anthy
scim-hangul
scim-pinyin
scim-chewing
scim-m17n

m17n-lib
m17n-db
#m17n-db-*

fonts-*
# work around yum API bug with specifying wildcards for now 
fonts-arabic
fonts-bengali
fonts-chinese
fonts-gujarati
fonts-hebrew
fonts-hindi
fonts-japanese
fonts-kannada
fonts-korean
fonts-malayalam
fonts-oriya
fonts-punjabi
fonts-sinhala
fonts-tamil
fonts-telugu

# dictionaries are big
-aspell-*
-m17n-db-*
-man-pages-*
# gimp help is huge
-gimp-help
# lose the compat stuff
-compat*

# space sucks
-festival
-gok
-gnome-speech
-ekiga
-gnome-user-docs
-specspo
-esc
-samba-client
-a2ps
-vino
-redhat-lsb

# smartcards won't really work on the livecd.  and we _need_ space
-coolkey
-ccid

# scanning takes quite a bit of space :/
-xsane
-xsane-gimp

# while hplip requires pyqt, it has to go
-hplip

# added games
#monkey-bubble
#ppracer

# we don't include @office so that we don't get OOo.  but some nice bits
#inkscape
abiword
gnumeric
#planner
evince
gnome-blog

# livecd bits to set up the livecd and be able to install
anaconda


%post
# FIXME: it'd be better to get this installed from a package
cat > /etc/rc.d/init.d/fedora-livecd << EOF
#!/bin/bash
#
# livecd: Init script for live cd
#
# chkconfig: 345 00 99
# description: Init script for live cd.

. /etc/init.d/functions

if ! strstr "\`cat /proc/cmdline\`" livecd || [ "\$1" != "start" ] || [ -e /.livecd-configured ] ; then
    exit 0
fi

exists() {
    which \$1 >/dev/null 2>&1 || return
    \$*
}

touch /.livecd-configured

# mount livecd
mkdir -p /mnt/livecd
mount -o ro -t iso9660 /dev/livecd /mnt/livecd

# configure X
exists system-config-display --noui --reconfig --set-depth=24

# unmute sound card
exists alsaunmute 0 2> /dev/null

# add fedora user with no passwd
useradd -c "Fedora live CD" fedora
passwd -d fedora > /dev/null
if [ -e /usr/share/icons/hicolor/96x96/apps/fedora-logo-icon.png ] ; then
    cp /usr/share/icons/hicolor/96x96/apps/fedora-logo-icon.png /home/fedora/.face
    chown fedora:fedora /home/fedora/.face
    # TODO: would be nice to get e-d-s to pick this one up too... but how?
fi

# turn off firstboot for livecd boots
echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

# don't start yum-updatesd for livecd boots
chkconfig --levels 345 yum-updatesd off

# Stopgap fix for RH #217966; should be fixed in HAL instead
touch /media/.hal-mtab
EOF
chmod 755 /etc/rc.d/init.d/fedora-livecd
/sbin/restorecon /etc/rc.d/init.d/fedora-livecd
/sbin/chkconfig --add fedora-livecd

# big  hack, but how else can we fit?
rm -rf /usr/share/doc/*
