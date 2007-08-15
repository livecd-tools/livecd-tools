lang en_US.UTF-8
keyboard us
timezone US/Eastern
auth --useshadow --enablemd5
selinux --enforcing
firewall --disabled
xconfig --startxonboot
services --enabled=NetworkManager,dhcdbd --disabled=network,sshd

repo --name=development --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=rawhide&arch=$basearch

%packages
@base-x
@games
@base
@core
@admin-tools
@dial-up
@hardware-support
@printing
kernel
memtest86+

@afrikaans-support
@albanian-support
@arabic-support
@armenian-support
@assamese-support
@basque-support
@belarusian-support
@bengali-support
@bhutanese-support
@bosnian-support
@brazilian-support
@breton-support
@british-support
@bulgarian-support
@catalan-support
@chinese-support
@croatian-support
@czech-support
@danish-support
@dutch-support
@estonian-support
@ethiopic-support
@faeroese-support
@filipino-support
@finnish-support
@french-support
@gaelic-support
@galician-support
@georgian-support
@german-support
@greek-support
@gujarati-support
@hebrew-support
@hindi-support
@hungarian-support
@icelandic-support
@indonesian-support
@inuktitut-support
@irish-support
@italian-support
@japanese-support
@kannada-support
@khmer-support
@korean-support
@lao-support
@latvian-support
@lithuanian-support
@malay-support
@malayalam-support
@maori-support
@marathi-support
@northern-sotho-support
@norwegian-support
@oriya-support
@persian-support
@polish-support
@portuguese-support
@punjabi-support
@romanian-support
@russian-support
@samoan-support
@serbian-support
@sinhala-support
@slovak-support
@slovenian-support
@somali-support
@southern-ndebele-support
@southern-sotho-support
@spanish-support
@swati-support
@swedish-support
@tagalog-support
@tamil-support
@telugu-support
@thai-support
@tibetan-support
@tonga-support
@tsonga-support
@tswana-support
@turkish-support
@ukrainian-support
@urdu-support
@venda-support
@vietnamese-support
@welsh-support
@xhosa-support
@zulu-support

# dictionaries are big
-aspell-*
-m17n-db-*
-man-pages-*
# lose the compat stuff
-compat*
-scim-tables-*

# save some space
-specspo
-esc
-samba-client
-a2ps
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

# scanning takes quite a bit of space :/
-xsane
-xsane-gimp
-sane-backends

# lots of people want to have this
gparted

# livecd bits to set up the livecd and be able to install
anaconda
anaconda-runtime

# make sure debuginfo doesn't end up on the live image
-*debuginfo

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
if [ -b /dev/live ]; then
   mkdir -p /mnt/live
   mount -o ro /dev/live /mnt/live
fi

# configure X
exists system-config-display --noui --reconfig --set-depth=24

# unmute sound card
exists alsaunmute 0 2> /dev/null

# add fedora user with no passwd
useradd -c "Fedora Live" fedora
passwd -d fedora > /dev/null

# turn off firstboot for livecd boots
echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

# don't start yum-updatesd for livecd boots
chkconfig --level 345 yum-updatesd off

# don't start cron/at as they tend to spawn things which are
# disk intensive that are painful on a live image
chkconfig --level 345 crond off
chkconfig --level 345 atd off
chkconfig --level 345 anacron off
chkconfig --level 345 readahead_early off
chkconfig --level 345 readahead_later off

# Stopgap fix for RH #217966; should be fixed in HAL instead
touch /media/.hal-mtab
EOF

chmod 755 /etc/rc.d/init.d/fedora-live
/sbin/restorecon /etc/rc.d/init.d/fedora-live
/sbin/chkconfig --add fedora-live

# save a little bit of space at least...
rm -f /boot/initrd*

