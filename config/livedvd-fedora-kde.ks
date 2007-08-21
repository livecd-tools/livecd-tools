%include livecd-fedora-kde.ks

%packages
# additional languages for kde
kde-i18n-*
koffice-langpack-*
man-pages-*

# and some extra packages
koffice-*


%post

# create /etc/sysconfig/desktop (needed for installation)
cat > /etc/sysconfig/desktop <<EOF
DESKTOP="KDE"
#DISPLAYMANAGER="KDE"
EOF

