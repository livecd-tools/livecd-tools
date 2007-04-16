lang en_US.UTF-8
keyboard us
timezone US/Eastern
auth --useshadow --enablemd5
selinux --enforcing
firewall --disabled

xconfig --startxonboot
services --enabled=NetworkManager,dhcdbd,lisa --disabled=network,sshd

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
syslinux
system-config-display
xorg-x11-drivers

# to make the cd installable
anaconda

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
-kdemultimedia-extras
-kdeartwork-extras
-kmymoney2
-basket

# some other extra packages
gnupg
samba-client
xine-lib-extras


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
#exists system-config-display --noui --reconfig --set-depth=24

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

# replace htmlview and launchmail in kicker
sed -i 's/redhat-web.desktop/konqbrowser.desktop/' /usr/share/config/kickerrc
sed -i 's/redhat-email.desktop/kmail.desktop/' /usr/share/config/kickerrc

# adding some autostarted applications
cp /usr/share/applications/fedora-knetworkmanager.desktop /usr/share/autostart/

# workaround for #233881
sed -i 's/BlueCurve/Echo/' /usr/share/config/ksplashrc

# workaround to put liveinst on desktop (should not be needed but 
# /etc/X11/xinit/xinitrc.d/zz-liveinst from anaconda doesn't do this atm)
mkdir -p /home/fedora/.kde/env
cat > /home/fedora/.kde/env/liveinst.sh <<END
#! /bin/bash
sed -i 's/NoDisplay=true/NoDisplay=false/' /home/fedora/Desktop/liveinst.desktop
END
chmod +x /home/fedora/.kde/env/liveinst.sh

# turn off firstboot for livecd boots
echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

# Stopgap fix for RH #217966; should be fixed in HAL instead
touch /media/.hal-mtab

# some cleanups

# remove non-working gnome-theme-installer from menu
rm -f /usr/share/applications/gnome-theme-installer.desktop

# don't start yum-updatesd for livecd boots
chkconfig --levels 345 yum-updatesd off

EOF

chmod 755 /etc/rc.d/init.d/fedora-live-kde
/sbin/restorecon /etc/rc.d/init.d/fedora-live-kde
/sbin/chkconfig --add fedora-live-kde
