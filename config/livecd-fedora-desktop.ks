%include livecd-fedora-base-desktop.ks

%packages
@games
@graphical-internet
@graphics
@sound-and-video
@gnome-desktop
nss-mdns
NetworkManager-vpnc
NetworkManager-openvpn
# we don't include @office so that we don't get OOo.  but some nice bits
abiword
gnumeric
gnome-blog
#planner
#inkscape

@albanian-support
@arabic-support
@basque-support
@bengali-support
@brazilian-support
@british-support
@bulgarian-support
@catalan-support
@chinese-support
@czech-support
@danish-support
@dutch-support
@estonian-support
@finnish-support
@french-support
@galician-support
@georgian-support
@german-support
@greek-support
@gujarati-support
@hebrew-support
@hindi-support
@hungarian-support
@indonesian-support
@italian-support
@japanese-support
@khmer-support
@korean-support
@latvian-support
@lithuanian-support
@malayalam-support
@marathi-support
@norwegian-support
@oriya-support
@persian-support
@polish-support
@portuguese-support
@punjabi-support
@romanian-support
@russian-support
@serbian-support
@slovak-support
@slovenian-support
@spanish-support
@swedish-support
@tamil-support
@telugu-support
@thai-support
@turkish-support
@ukrainian-support
@vietnamese-support
@welsh-support

# The following locales have less than 50% translation coverage for the core
# GNOME stack, as found at http://l10n.gnome.org/languages/

#@afrikaans-support
#@armenian-support
#@assamese-support
#@belarusian-support
#@bhutanese-support
#@bosnian-support
#@breton-support
#@croatian-support
#@ethiopic-support
#@faeroese-support
#@filipino-support
#@gaelic-support
#@icelandic-support
#@inuktitut-support
#@irish-support
#@kannada-support
#@lao-support
#@malay-support
#@maori-support
#@northern-sotho-support
#@samoan-support
#@sinhala-support
#@somali-support
#@southern-ndebele-support
#@southern-sotho-support
#@swati-support
#@tagalog-support
#@tibetan-support
#@tonga-support
#@tsonga-support
#@tswana-support
#@urdu-support
#@venda-support
#@xhosa-support
#@zulu-support

# These fonts are only used in the commented-out locales above
-lklug-fonts
-lohit-fonts-kannada
-abyssinica-fonts
-jomolhari-fonts


# dictionaries are big
-aspell-*
-hunspell-*
-man-pages-*
-scim-tables-*
-wqy-bitmap-fonts
-dejavu-fonts-experimental

# more fun with space saving 
-scim-lang-chinese
scim-chewing
scim-pinyin

# save some space
-gnome-user-docs
-gimp-help
-evolution-help
-autofs
-nss_db
-vino
-dasher
-evince-dvi
-evince-djvu
# temporary - drags in many deps
-ekiga
%end

%post
cat >> /etc/rc.d/init.d/fedora-live << EOF
# disable screensaver locking
gconftool-2 --direct --config-source=xml:readwrite:/etc/gconf/gconf.xml.defaults -s -t bool /apps/gnome-screensaver/lock_enabled false >/dev/null
# set up timed auto-login for after 60 seconds
sed -i -e 's/\[daemon\]/[daemon]\nTimedLoginEnable=true\nTimedLogin=fedora\nTimedLoginDelay=60/' /etc/gdm/custom.conf
if [ -e /usr/share/icons/hicolor/96x96/apps/fedora-logo-icon.png ] ; then
    cp /usr/share/icons/hicolor/96x96/apps/fedora-logo-icon.png /home/fedora/.face
    chown fedora:fedora /home/fedora/.face
    # TODO: would be nice to get e-d-s to pick this one up too... but how?
fi

EOF

%end
