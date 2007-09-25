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
alleyoop
dejagnu
dogtail
emacs
expect
frysk-gnome
gnuplot
inkscape
maven2
scons
sysprof

# RPM/Fedora-specific tools
@buildsys-build
koji
mock
rpmdevtools
rpmlint

# Should we?
#@sql-server
#@mysql
#@ruby
#@web-development
#@x-software-development
# I think this is going to be too big on x86_64
#*-devel
%end

#%post
# Enable debuginfo repository
# ?
#%end
