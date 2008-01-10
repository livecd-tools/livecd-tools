%include livecd-fedora-base-desktop.ks

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
kdemultimedia
kdenetwork
kdegraphics
kde-settings
kde-settings-kdm
kde-settings-pulseaudio

# KDE 3
koffice-kword
koffice-kspread
koffice-kpresenter
koffice-filters
k3b
knetworkmanager
konversation
filelight
kaffeine
kdepim

## don't include these for now to fit a cd
## digikam (~11 megs), ktorrent (~x megs)
##amarok
digikam
twinkle
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
-xulrunner

# save some space
-autofs

%end

%post

# get rid of unwanted firefox (until this one is solved: #420101)
rpm -e firefox

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

# add liveinst.desktop to favorites menu
mkdir -p /home/fedora/.kde/share/config/
cat > /home/fedora/.kde/share/config/kickoffrc << MENU_EOF
[Favorites]
FavoriteURLs=/usr/share/applications/kde4/konqbrowser.desktop,/usr/share/applications/kde4/dolphin.desktop,/usr/share/applications/liveinst.desktop
MENU_EOF
chown -R fedora:fedora /home/fedora/.kde/

# workaround to start nm-applet automatically
cp /etc/xdg/autostart/nm-applet.desktop /usr/share/autostart/

%end
