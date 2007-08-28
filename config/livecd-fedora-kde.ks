%include livecd-fedora-base-desktop.ks

%packages
@kde-desktop
kdegames
beryl-kde
k3b
koffice-kword
koffice-kspread
koffice-kpresenter
koffice-filters
twinkle
filelight
kdeutils-extras

# some other extra packages
gnupg
xine-lib-extras
synaptics
fonts-*
hal-cups-utils

# if it is enough space include koffice-krita (~40 megs)
koffice-krita

# ignore comps.xml and make sure these packages are included
knetworkmanager
kpowersave
redhat-artwork-kde
rhgb
man-pages

#some changes that we don't want...
-specspo
-scribus
-kdeaddons
-kdemultimedia-extras
-kdeartwork-extras
-kmymoney2
-basket
-speedcrunch


# remove some packages from livecd-fedora-base-desktop.ks
-scim*
-system-config-printer*
-gdm
-authconfig-gtk
-m17n*
-xorg-x11-fonts-*
-xorg-x11-twm
-PolicyKit-gnome
#-libbeagle
#-yelp
#-firefox
-desktop-backgrounds-basic
-gnome-doc-utils-stylesheets
#-yelp
#-zenity
-anthy
-kasumi
-pygtkglext
-python-devel
-libchewing
-system-config-printer-libs
#-hal-cups-utils
#kipi-plugins
#gutenprint-foomatic


%post

# create /etc/sysconfig/desktop (needed for installation)
cat > /etc/sysconfig/desktop <<EOF
DESKTOP="KDE"
DISPLAYMANAGER="KDE"
EOF

# add initscript
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

# adding some autostarted applications
cp /usr/share/applications/fedora-knetworkmanager.desktop /usr/share/autostart/

# workaround to put liveinst on desktop and in menu
sed -i 's/NoDisplay=true/NoDisplay=false/' /usr/share/applications/liveinst.desktop
EOF

