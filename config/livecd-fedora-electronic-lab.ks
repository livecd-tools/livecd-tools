%include livecd-fedora-base-desktop.ks

%packages
# fonts
dejavu-lgc-fonts

# KDE basic packages
kdebase
kde-filesystem
kdelibs
kdenetwork
kdepim
kde-settings
kde-settings-kdm
kdeutils
knetworkmanager
kpowersave
redhat-artwork-kde

# some other extra packages
ntfsprogs
ntfs-3g
synaptics
setroubleshoot
smolt
smolt-firstboot
syslinux
rhgb

# we don't want these
-dos2unix
-gphoto2

#vlsi
alliance-doc
irsim
gds2pov
magic-doc
toped
xcircuit
qucs
netgen

#Hardware Description Languages
gtkwave
iverilog
drawtiming
ghdl

#spice
ngspice
gnucap
#gspiceui
#gwave

#PCB and schematics
geda-gschem
geda-examples
geda-gsymcheck
geda-gattrib
geda-utils
geda-docs
geda-gnetlist
gerbv
gresistor
kicad
pcb

#Micro Programming
piklab
ktechlab
pikloops
sdcc

#embedded
avr-gcc
avr-binutils
avr-libc
avr-gdb
avrdude

#computing
octave

%post

###### Fedora Electronic Lab ####################################################

# Fedora Electronic Lab:  KDE keyboard layouts
cat > /usr/share/kde-settings/kde-profile/default/share/config/kxkbrc <<EOF
[Layout]
DisplayNames=
EnableXkbOptions=false
IncludeGroups=
LayoutList=us,fr,de,jp
Model=pc104
Options=
ResetOldOptions=false
ShowFlag=true
ShowSingle=true
StickySwitching=false
StickySwitchingDepth=2
SwitchMode=Global
Use=true
EOF


# Fedora Electronic Lab: Kwin buttons
cat > /usr/share/kde-settings/kde-profile/default/share/config/kwinrc <<EOF
[Style]
ButtonsOnLeft=MB
ButtonsOnRight=FIAX
CustomButtonPositions=true
EOF

###### KDE #####################################################################

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
sed -i 's/#PreselectUser=Default/PreselectUser=Default/' /etc/kde/kdm/kdmrc
sed -i 's/#DefaultUser=johndoe/DefaultUser=fedora/' /etc/kde/kdm/kdmrc

# disable screensaver
sed -i 's/Enabled=true/Enabled=false/' /usr/share/kde-settings/kde-profile/default/share/config/kdesktoprc

# adding some autostarted applications
cp /usr/share/applications/fedora-knetworkmanager.desktop /usr/share/autostart/

# workaround to put liveinst on desktop and in menu
sed -i 's/NoDisplay=true/NoDisplay=false/' /usr/share/applications/liveinst.desktop

EOF

chmod 755 /etc/rc.d/init.d/fedora-live-kde
/sbin/restorecon /etc/rc.d/init.d/fedora-live-kde
/sbin/chkconfig --add fedora-live-kde
