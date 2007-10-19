# Description : Live image for Fedora Electronic Lab
# last updated: 10 October 2007

%include livecd-fedora-base-desktop.ks

%packages
# KDE basic packages
kdebase
kde-filesystem
kdelibs
kdenetwork
kdegraphics
kdeutils
knetworkmanager
kde-settings
kmenu-gnome
kdesvn
yakuake
# include default fedora wallpaper
desktop-backgrounds-basic
wget

# some projects based on ghdl and gtkwave needs
zlib-devel

#project management
vym
koffice-kspread
koffice-kword
koffice-kplato
koffice-filters

# some other extra packages
ntfsprogs
ntfs-3g
synaptics
setroubleshoot
smolt
smolt-firstboot
syslinux
gnupg
hal-cups-utils

# we don't want these
-dos2unix
-firefox
-authconfig-gtk
-PolicyKit-gnome
-gnome-doc-utils-stylesheets

# ignore comps.xml and make sure these packages are included
kpowersave
rhgb


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
freehdl

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

# Serial Port Terminals
gtkterm
picocom
minicom

#embedded
arm-gp2x-linux*
avr-*
avrdude
dfu-programmer
avarice
uisp

#computing
octave
octave-forge

%end

%post

###### Fedora Electronic Lab ####################################################

# Fedora Electronic Lab: Kwin buttons
cat > /usr/share/kde-settings/kde-profile/default/share/config/kwinrc <<EOF
[Style]
ButtonsOnLeft=MB
ButtonsOnRight=FIAX
CustomButtonPositions=true
EOF


# kill stupid klipper
cat > /usr/share/kde-settings/kde-profile/default/share/config/klipperrc <<EOF
[General]
AutoStart=false
EOF

# use the LCD_Style clock as alliance's windows demand a lot of space on kicker
cat > /usr/share/kde-settings/kde-profile/default/share/config/clock_panelappletrc <<EOF
[Digital]
LCD_Style=false
Show_Date=false
Show_Seconds=true

[General]
Type=Digital
EOF


cat > /usr/share/kde-settings/kde-profile/default/share/config/kxkbrc <<EOF
[Layout]
DisplayNames=
EnableXkbOptions=false
IncludeGroups=
LayoutList=us,de,fr,jp
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

# Chitlesh doesn't like the KDE icon on the kicker, but fedora's
# This is a feature for Fedora and not for KDE
cp -fp /usr/share/icons/Bluecurve/16x16/apps/gnome-main-menu.png /usr/share/icons/crystalsvg/16x16/apps/kmenu.png
cp -fp /usr/share/icons/Bluecurve/24x24/apps/gnome-main-menu.png /usr/share/icons/crystalsvg/22x22/apps/kmenu.png
cp -fp /usr/share/icons/Bluecurve/32x32/apps/gnome-main-menu.png /usr/share/icons/crystalsvg/32x32/apps/kmenu.png
cp -fp /usr/share/icons/Bluecurve/48x48/apps/gnome-main-menu.png /usr/share/icons/crystalsvg/48x48/apps/kmenu.png

###### KDE #####################################################################

# create /etc/sysconfig/desktop (needed for installation)
cat > /etc/sysconfig/desktop <<EOF
DESKTOP="KDE"
DISPLAYMANAGER="KDE"
EOF

# add initscript qnd # Fedora Electronic Lab:  KDE keyboard layouts
cat >> /etc/rc.d/init.d/fedora-live << EOF

if [ -e /usr/share/icons/hicolor/96x96/apps/fedora-logo-icon.png ] ; then
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

# workaround to put liveinst on desktop and in menu
sed -i 's/NoDisplay=true/NoDisplay=false/' /usr/share/applications/liveinst.desktop
EOF

# and set up gnome-keyring to startup/shutdown in kde
mkdir -p /etc/skel/.kde/env /etc/skel/.kde/shutdown
cat > /etc/skel/.kde/env/start-custom.sh << EOF
#!/bin/sh
eval \`gnome-keyring-daemon\`
export GNOME_KEYRING_PID
export GNOME_KEYRING_SOCKET
EOF
chmod 755 /etc/skel/.kde/env/start-custom.sh

cat > /etc/skel/.kde/shutdown/stop-custom.sh << EOF
#/bin/sh
if [-n "$GNOME_KEYRING_PID"];then
kill $GNOME_KEYRING_PID
fi
EOF
chmod 755 /etc/skel/.kde/shutdown/stop-custom.sh

###### Fedora Electronic Lab ####################################################

# FEL doesn't need these and boots slowly
/sbin/chkconfig --del anacron
/sbin/chkconfig --del sendmail
/sbin/chkconfig --del nfs
/sbin/chkconfig --del nfslock
/sbin/chkconfig --del rpcidmapd
/sbin/chkconfig --del rpcbind

%end
	
