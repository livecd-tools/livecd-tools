
VERSION = 009

INSTALL = /usr/bin/install -c
INSTALL_PROGRAM = ${INSTALL}
INSTALL_DATA = ${INSTALL} -m 644
INSTALL_SCRIPT = ${INSTALL_PROGRAM}

all: 

install:
	$(INSTALL_PROGRAM) -D creator/livecd-creator $(DESTDIR)/usr/bin/livecd-creator
	$(INSTALL_PROGRAM) -D creator/isotostick.sh $(DESTDIR)/usr/bin/livecd-iso-to-disk
	$(INSTALL_PROGRAM) -D creator/mayflower $(DESTDIR)/usr/lib/livecd-creator/mayflower
	$(INSTALL_DATA) -D AUTHORS $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)/AUTHORS
	$(INSTALL_DATA) -D COPYING $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)/COPYING
	$(INSTALL_DATA) -D README $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)/README
	$(INSTALL_DATA) -D HACKING $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)/HACKING
	$(INSTALL_DATA) -D TODO $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)/TODO
	$(INSTALL_DATA) -D config/livecd-fedora-minimal.ks $(DESTDIR)/usr/share/livecd-tools/livecd-fedora-minimal.ks
	$(INSTALL_DATA) -D config/livecd-fedora-desktop.ks $(DESTDIR)/usr/share/livecd-tools/livecd-fedora-desktop.ks
	$(INSTALL_DATA) -D config/livecd-fedora-kde.ks $(DESTDIR)/usr/share/livecd-tools/livecd-fedora-kde.ks
	$(INSTALL_DATA) -D config/livedvd-fedora-kde.ks $(DESTDIR)/usr/share/livecd-tools/livedvd-fedora-kde.ks

uninstall:
	rm -f $(DESTDIR)/usr/bin/livecd-creator
	rm -rf $(DESTDIR)/usr/lib/livecd-creator
	rm -rf $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)
	rm -rf $(DESTDIR)/usr/share/livecd-tools

dist : all
	git-archive --format=tar --prefix=livecd-tools-$(VERSION)/ HEAD | bzip2 -9v > livecd-tools-$(VERSION).tar.bz2

clean:
	rm -f *~ creator/*~ installer/*~ config/*~
