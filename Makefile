
VERSION = 012

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
	mkdir -p $(DESTDIR)/usr/share/livecd-tools/
	$(INSTALL_DATA) -D config/*.ks $(DESTDIR)/usr/share/livecd-tools/

uninstall:
	rm -f $(DESTDIR)/usr/bin/livecd-creator
	rm -rf $(DESTDIR)/usr/lib/livecd-creator
	rm -rf $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)
	rm -rf $(DESTDIR)/usr/share/livecd-tools

dist : all
	git-archive --format=tar --prefix=livecd-tools-$(VERSION)/ HEAD | bzip2 -9v > livecd-tools-$(VERSION).tar.bz2

clean:
	rm -f *~ creator/*~ installer/*~ config/*~
