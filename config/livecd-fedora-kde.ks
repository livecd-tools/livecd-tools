lang en_US.UTF-8
keyboard us
timezone US/Eastern
auth --useshadow --enablemd5
selinux --enforcing
firewall --disabled

xconfig --startxonboot
services --enabled=NetworkManager,dhcdbd,lisa --disabled=network,sshd

repo --name=kde-d7 --baseurl=http://download.fedora.redhat.com/pub/fedora/linux/core/development/i386/os
repo --name=kde-e7 --baseurl=http://download.fedora.redhat.com/pub/fedora/linux/extras/development/i386

%packages
# Basic packages
@core
@base
@admin-tools
@dial-up
@hardware-support
kernel
syslinux

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
-kdeaddons
kdegames
#kdeedu
#kdetoys

# additional KDE packages
amarok
beryl-kde
digikam
k3b
kaffeine
knetworkmanager
konversation
kpowersave
ktorrent
twinkle

# we don't want to pull in krita, but want the rest of the koffice stuff
koffice-kword
koffice-kspread
koffice-kpresenter
koffice-kivio
koffice-karbon
koffice-kugar
koffice-kexi
koffice-kexi-driver-mysql
koffice-kexi-driver-pgsql
koffice-kchart
koffice-kformula
koffice-filters
koffice-kplato

#some changes that we don't want...
-apollon
-kerry
-basket
-gift-gnutella
-gift-openft
-gpgme
-rss-glx-kde
-specspo
-koffice-krita
-koffice-suite


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

( until test -d /home/fedora/Desktop ; do sleep 1; done
cp /usr/share/applications/liveinst.desktop /home/fedora/Desktop/
sed -i 's/NoDisplay=true/NoDisplay=false/' /home/fedora/Desktop/liveinst.desktop
) &
END
chmod +x /home/fedora/.kde/env/liveinst.sh


# turn off firstboot for livecd boots
echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

# Stopgap fix for RH #217966; should be fixed in HAL instead
touch /media/.hal-mtab

# /etc/X11/xinit/xinitrc.d/zz-liveinst.sh is confusing kde on login
# so remove it for now
rm -f /etc/X11/xinit/xinitrc.d/zz-liveinst.sh

# some cleanups

# remove non-working gnome-theme-installer from menu
rm -f /usr/share/applications/gnome-theme-installer.desktop

# don't start yum-updatesd for livecd boots
chkconfig --levels 345 yum-updatesd off

EOF

chmod 755 /etc/rc.d/init.d/fedora-live-kde
/sbin/restorecon /etc/rc.d/init.d/fedora-live-kde
/sbin/chkconfig --add fedora-live-kde
