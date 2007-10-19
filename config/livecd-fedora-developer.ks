%include livecd-fedora-desktop.ks

part / --size 6000

%packages
# Libraries
@development-libs
@gnome-software-development
@java-development

# SCM tools
bazaar
bzr
cogito
cvs2cl
cvsutils
git
mercurial
monotone
quilt

# IDEs
@eclipse
anjuta
anjuta-docs
codeblocks

# General developer tools
@authoring-and-publishing
@development-tools
@editors
@system-tools
@virtualization
ElectricFence
alleyoop
crash
dejagnu
dogtail
elfutils-devel
emacs
emacs-el
expect
frysk-gnome
gconf-editor
gettext-devel
gnuplot
hexedit
inkscape
intltool
lynx
maven2
mutt
scons
sharutils
socat
sox
sysprof
tcp_wrappers-devel
tcsh
texi2html
xchat

# RPM/Fedora-specific tools
@buildsys-build
createrepo
koji
livecd-tools
mock
rpmdevtools
rpmlint
yum-priorities

eclipse-demos

# Should we?
#@sql-server
#@mysql
#@ruby
#@web-development
#@x-software-development
# I think this is going to be too big on x86_64
#*-devel
%end

%post
# TODO: Enable debuginfo repository

cat >> /etc/rc.d/init.d/fedora-live << EOF
# Put link to demonstration videos on the desktop
pushd /home/fedora/Desktop
ln -s /usr/share/eclipse-demos-0.0.1 "Eclipse demonstration videos"
popd
EOF
%end
