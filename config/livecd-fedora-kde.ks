%include livecd-fedora-base-desktop.ks

# WARNING: Don't expect this kickstart to be working. It's an initial version
# and also some packages are right building atm. KDE4 is also actual in a state
# where it needs some polishing.
# I you've ignored this warnings please fill bug report at:
# https://bugzilla.redhat.com
# http://bugs.kde.org/

%packages
# don't use @kde-desktop for the moment (until it's complete kde4)
# KDE 4
kdelibs
kdebase
kdebase-workspace
kdebase-runtime
kdegames
kdeutils
kdeaccessibility
kdeadmin
kdenetwork
kdegraphics
kde-settings
kde-settings-kdm
kde-settings-pulseaudio

# KDE 3
amarok
koffice-kword
koffice-kspread
koffice-kpresenter
koffice-filters
twinkle
k3b
knetworkmanager
konversation
digikam
filelight
kaffeine
ktorrent

# FIXME/TODO: recheck the removals here
# try to remove some packages from livecd-fedora-base-desktop.ks
-scim*
-gdm
-authconfig-gtk
-m17n*
-PolicyKit-gnome
-gnome-doc-utils-stylesheets
-anthy
-kasumi
-pygtkglext
-python-devel
-libchewing
-firefox

%end

%post

# create /etc/sysconfig/desktop (needed for installation)
cat > /etc/sysconfig/desktop <<EOF
DESKTOP="KDE"
DISPLAYMANAGER="KDM"
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

# FIXME/TODO: Where to put liveinst.desktop since there is no "normal" desktop anymore?

%end
