lang en_US.UTF-8
keyboard us
timezone US/Eastern
auth --useshadow --enablemd5
selinux --enforcing
firewall --disabled

xconfig --startxonboot
services --enabled=NetworkManager,dhcdbd --disabled=network,sshd

repo --name=d7 --baseurl=http://download.fedora.redhat.com/pub/fedora/linux/core/development/i386/os
repo --name=e7 --baseurl=http://download.fedora.redhat.com/pub/fedora/linux/extras/development/i386

%packages
# Basic packages
@core
@base
@dial-up
@admin-tools
@hardware-support
kernel

dejavu-lgc-fonts
setroubleshoot
smolt
smolt-firstboot
syslinux
system-config-display
system-config-services
xorg-x11-drivers

# to make the cd installable
anaconda
anaconda-runtime

# KDE basic packages
@kde-desktop
kdegames

# additional KDE packages
beryl-kde
k3b
koffice-kword
koffice-kspread
koffice-kpresenter
koffice-filters
twinkle

#some changes that we don't want...
-specspo
-scribus
-kdeaddons
-kdemultimedia-extras
-kdeartwork-extras
-kmymoney2
-basket

# some stuff we don't want to save space
-samba-client
-redhat-lsb
-ccid
-coolkey

# some other extra packages
gnupg
xine-lib-extras
ntfsprogs
ntfs-3g
gparted
synaptics

# fonts
fonts-*

# ignore comps.xml and make sure these packages are included
knetworkmanager
kpowersave
redhat-artwork-kde

%post

# create /etc/sysconfig/desktop (needed for installation)
cat > /etc/sysconfig/desktop <<EOF
DESKTOP="KDE"
DISPLAYMANAGER="KDE"
EOF

# add initscript
# FIXME: it'd be better to get this installed from a package
cat > /etc/rc.d/init.d/fedora-live-kde << EOF
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

if [ -e /usr/share/icons/hicolor/96x96/apps/fedora-logo-icon.png ] ; then
    cp /usr/share/icons/hicolor/96x96/apps/fedora-logo-icon.png /home/fedora/.face
    chown fedora:fedora /home/fedora/.face
    # TODO: would be nice to get e-d-s to pick this one up too... but how?

    # use image also for kdm
    mkdir -p /usr/share/apps/kdm/faces
    cp /usr/share/icons/hicolor/96x96/apps/fedora-logo-icon.png /usr/share/apps/kdm/faces/fedora.face.icon

fi

# make fedora user use KDE
echo "startkde" > /home/fedora/.xsession
chmod a+x /home/fedora/.xsession
chown fedora:fedora /home/fedora/.xsession

# set up autologin for user fedora
sed -i 's/#AutoLoginEnable=true/AutoLoginEnable=true/' /etc/kde/kdm/kdmrc
sed -i 's/#AutoLoginUser=fred/AutoLoginUser=fedora/' /etc/kde/kdm/kdmrc

# set up user fedora as default user and preselected user
sed -i 's/PreselectUser=None/PreselectUser=Default/' /etc/kde/kdm/kdmrc
sed -i 's/#DefaultUser=ethel/DefaultUser=fedora/' /etc/kde/kdm/kdmrc

# adding some autostarted applications
cp /usr/share/applications/fedora-knetworkmanager.desktop /usr/share/autostart/

# workaround to put liveinst on desktop and in menu
sed -i 's/NoDisplay=true/NoDisplay=false/' /usr/share/applications/liveinst.desktop

# turn off firstboot for livecd boots
echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

# Stopgap fix for RH #217966; should be fixed in HAL instead
touch /media/.hal-mtab

# don't start yum-updatesd for livecd boots
chkconfig --levels 345 yum-updatesd off

# don't start cron/at as they tend to spawn things which are
# disk intensive that are painful on a live image
chkconfig --level 345 crond off
chkconfig --level 345 atd off
chkconfig --level 345 anacron off
chkconfig --level 345 readahead_early off
chkconfig --level 345 readahead_later off

EOF

chmod 755 /etc/rc.d/init.d/fedora-live-kde
/sbin/restorecon /etc/rc.d/init.d/fedora-live-kde
/sbin/chkconfig --add fedora-live-kde

# save a little bit of space at least...
rm -f /boot/initrd*
