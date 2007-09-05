%include livecd-fedora-desktop.ks

%packages
@eclipse
@java-development
@development-libs
@development-tools
@editors
@gnome-software-development

# Does this work?
#man-pages-*

# Need to figure out if this is going to be too big
#*-devel

# Enable debuginfo repository
# ?
