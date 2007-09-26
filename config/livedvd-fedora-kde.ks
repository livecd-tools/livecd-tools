%include livecd-fedora-kde.ks

%packages

# add full language support
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

# and some extra packages
koffice-*
krusader
nss-mdns

%end 

%post
# workaround avahi segfault (#279301)
touch /etc/resolv.conf
/sbin/restorecon /etc/resolv.conf

# Use gdm here for language selection

# create /etc/sysconfig/desktop (needed for installation)
cat > /etc/sysconfig/desktop <<EOF
DESKTOP="KDE"
#DISPLAYMANAGER="KDE"
EOF

%end 
