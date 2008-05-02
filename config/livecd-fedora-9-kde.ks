%include livecd-fedora-base-desktop.ks

%packages
@kde-desktop

# include nm-applet directly 
NetworkManager-gnome

# unwanted packages from @kde-desktop
# don't include these for now to fit on a cd
# digikam (~11 megs), ktorrent (~3 megs), amarok (~14 megs),
# kdegames (~23 megs)
-amarok
-digikam
-kdeedu
-scribus
#-ktorrent
#-kdegames
#-kftpgrabber*

# KDE 3
koffice-kword
koffice-kspread
koffice-kpresenter
koffice-filters
k3b
filelight
# twinkle (~10 megs)
#twinkle

# some extras
fuse
pavucontrol

# additional fonts
@fonts
fonts-ISO8859-2 
#cjkunifonts-ukai 
madan-fonts 
fonts-KOI8-R 
fonts-KOI8-R-100dpi 
tibetan-machine-uni-fonts

# FIXME/TODO: recheck the removals here
# try to remove some packages from livecd-fedora-base-desktop.ks
-gdm
-authconfig-gtk

# save some space (from @base)
-make
-nss_db
-autofs

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

# add liveinst.desktop to favorites menu
mkdir -p /home/fedora/.kde/share/config/
cat > /home/fedora/.kde/share/config/kickoffrc << MENU_EOF
[Favorites]
FavoriteURLs=/usr/share/applications/kde4/konqbrowser.desktop,/usr/share/applications/kde4/dolphin.desktop,/usr/share/applications/kde4/systemsettings.desktop,/usr/share/applications/liveinst.desktop
MENU_EOF
chown -R fedora:fedora /home/fedora/.kde/

%end
