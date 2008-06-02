lang en_US.UTF-8
keyboard us
timezone US/Eastern
auth --useshadow --enablemd5
selinux --enforcing
firewall --disabled
xconfig --startxonboot
part / --size 4096
services --enabled=NetworkManager --disabled=network,sshd

repo --name=development --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=rawhide&arch=$basearch

%packages
@base-x
@base
@core
@fonts
@admin-tools
@dial-up
@hardware-support
@printing
kernel
memtest86+

# save some space
-specspo
-esc
-samba-client
-a2ps
-mpage
-redhat-lsb
-sox
-hplip
-hpijs
# smartcards won't really work on the livecd.  
-coolkey
-ccid
# duplicate functionality
-pinfo
-vorbis-tools
-wget
# dasher is just too big
-dasher
# lose the compat stuff
-compat*

# qlogic firmwares
-ql2100-firmware
-ql2200-firmware
-ql23xx-firmware
-ql2400-firmware

# scanning takes quite a bit of space :/
-xsane
-xsane-gimp
-sane-backends

# livecd bits to set up the livecd and be able to install
anaconda
isomd5sum

# make sure debuginfo doesn't end up on the live image
-*debuginfo
%end

%post
# FIXME: it'd be better to get this installed from a package
cat > /etc/rc.d/init.d/fedora-live << EOF
#!/bin/bash
#
# live: Init script for live image
#
# chkconfig: 345 00 99
# description: Init script for live image.

. /etc/init.d/functions

if ! strstr "\`cat /proc/cmdline\`" liveimg || [ "\$1" != "start" ] || [ -e /.liveimg-configured ] ; then
    exit 0
fi

exists() {
    which \$1 >/dev/null 2>&1 || return
    \$*
}

touch /.liveimg-configured

# mount live image
if [ -b \`readlink -f /dev/live\` ]; then
   mkdir -p /mnt/live
   mount -o ro /dev/live /mnt/live
fi

# enable swaps unless requested otherwise
swaps=\`blkid -t TYPE=swap -o device\`
if ! strstr "\`cat /proc/cmdline\`" noswap -a [ -n "\$swaps" ] ; then
  for s in \$swaps ; do
    action "Enabling swap partition \$s" swapon \$s
  done
fi

mountPersistentHome() {
  homeloop=\`losetup -f\`
  mount -o remount,rw /mnt/live
  losetup \$homeloop /mnt/live/LiveOS/home.img
  if [ "\$(/lib/udev/vol_id -t \$homeloop)" = "crypto_LUKS" ]; then
    echo
    echo "Setting up encrypted /home device"
    cryptsetup luksOpen \$homeloop EncHome <&1
    homeloop=/dev/mapper/EncHome
  fi
  mount \$homeloop /home
  [ -x /sbin/restorecon ] && /sbin/restorecon /home
  if [ -d /home/fedora ]; then USERADDARGS="-M" ; fi
}

# if we have a persistent /home, then we want to go ahead and mount it
if ! strstr "\`cat /proc/cmdline\`" nopersisthome -a [ -e /mnt/live/LiveOS/home.img ] ; then
  action "Mounting persistent /home" mountPersistentHome
fi

# add fedora user with no passwd
action "Adding fedora user" useradd \$USERADDARGS -c "Fedora Live" fedora
passwd -d fedora > /dev/null

# turn off firstboot for livecd boots
chkconfig --level 345 firstboot off 2>/dev/null

# don't start yum-updatesd for livecd boots
chkconfig --level 345 yum-updatesd off 2>/dev/null

# don't do packagekit checking by default
gconftool-2 --direct --config-source=xml:readwrite:/etc/gconf/gconf.xml.defaults -s -t string /apps/gnome-packagekit/frequency_get_updates never >/dev/null
gconftool-2 --direct --config-source=xml:readwrite:/etc/gconf/gconf.xml.defaults -s -t string /apps/gnome-packagekit/frequency_refresh_cache never >/dev/null
gconftool-2 --direct --config-source=xml:readwrite:/etc/gconf/gconf.xml.defaults -s -t bool /apps/gnome-packagekit/notify_available false >/dev/null

# apparently, the gconf keys aren't enough
mkdir -p /home/fedora/.config/autostart
echo "X-GNOME-Autostart-enabled=false" >> /home/fedora/.config/autostart/gpk-update-icon.desktop
chown -R fedora:fedora /home/fedora/.config



# don't start cron/at as they tend to spawn things which are
# disk intensive that are painful on a live image
chkconfig --level 345 crond off 2>/dev/null
chkconfig --level 345 atd off 2>/dev/null
chkconfig --level 345 anacron off 2>/dev/null
chkconfig --level 345 readahead_early off 2>/dev/null
chkconfig --level 345 readahead_later off 2>/dev/null

# make it so that we don't do writing to the overlay for things which
# are just tmpdirs/caches
mount -t tmpfs varcacheyum /var/cache/yum
mount -t tmpfs tmp /tmp
mount -t tmpfs vartmp /var/tmp
[ -x /sbin/restorecon ] && /sbin/restorecon /var/cache/yum /tmp /var/tmp >/dev/null 2>&1

# Stopgap fix for RH #217966; should be fixed in HAL instead
touch /media/.hal-mtab

# workaround clock syncing on shutdown that we don't want (#297421)
sed -i -e 's/hwclock/no-such-hwclock/g' /etc/rc.d/init.d/halt
EOF

# bah, hal starts way too late
cat > /etc/rc.d/init.d/fedora-late-live << EOF
#!/bin/bash
#
# live: Late init script for live image
#
# chkconfig: 345 99 01
# description: Late init script for live image.

. /etc/init.d/functions

if ! strstr "\`cat /proc/cmdline\`" liveimg || [ "\$1" != "start" ] || [ -e /.liveimg-late-configured ] ; then
    exit 0
fi

exists() {
    which \$1 >/dev/null 2>&1 || return
    \$*
}

touch /.liveimg-late-configured

# read some variables out of /proc/cmdline
for o in \`cat /proc/cmdline\` ; do
    case \$o in
    ks=*)
        ks="\${o#ks=}"
        ;;
    xdriver=*)
        xdriver="--set-driver=\${o#xdriver=}"
        ;;
    esac
done


# if liveinst or textinst is given, start anaconda
if strstr "\`cat /proc/cmdline\`" liveinst ; then
   /usr/sbin/liveinst \$ks
fi
if strstr "\`cat /proc/cmdline\`" textinst ; then
   /usr/sbin/liveinst --text \$ks
fi

# configure X, allowing user to override xdriver
if [ -n "\$xdriver" ]; then
   exists system-config-display --noui --reconfig --set-depth=24 \$xdriver
fi

EOF

# workaround avahi segfault (#279301)
touch /etc/resolv.conf
/sbin/restorecon /etc/resolv.conf

chmod 755 /etc/rc.d/init.d/fedora-live
/sbin/restorecon /etc/rc.d/init.d/fedora-live
/sbin/chkconfig --add fedora-live

chmod 755 /etc/rc.d/init.d/fedora-late-live
/sbin/restorecon /etc/rc.d/init.d/fedora-late-live
/sbin/chkconfig --add fedora-late-live

# work around for poor key import UI in PackageKit
rm -f /var/lib/rpm/__db*
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora

# save a little bit of space at least...
rm -f /boot/initrd*
# make sure there aren't core files lying around
rm -f /core*

%end


%post --nochroot
cp $INSTALL_ROOT/usr/share/doc/*-release-*/GPL $LIVE_ROOT/GPL
cp $INSTALL_ROOT/usr/share/doc/HTML/readme-live-image/en_US/readme-live-image-en_US.txt $LIVE_ROOT/README

# only works on x86, x86_64
if [ "$(uname -i)" = "i386" -o "$(uname -i)" = "x86_64" ]; then
  if [ ! -d $LIVE_ROOT/LiveOS ]; then mkdir -p $LIVE_ROOT/LiveOS ; fi
  cp /usr/bin/livecd-iso-to-disk $LIVE_ROOT/LiveOS
fi
%end
