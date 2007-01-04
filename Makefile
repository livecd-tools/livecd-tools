
VERSION = 001

INSTALL = /usr/bin/install -c
INSTALL_PROGRAM = ${INSTALL}
INSTALL_DATA = ${INSTALL} -m 644
INSTALL_SCRIPT = ${INSTALL_PROGRAM}

all: creator/run-init

creator/run-init : creator/run-init.c creator/run-init.h creator/runinitlib.c Makefile
	cd creator && gcc -o run-init -static run-init.c runinitlib.c && strip run-init

install:
	$(INSTALL_PROGRAM) -D creator/livecd-creator $(DESTDIR)/usr/bin/livecd-creator
	$(INSTALL_PROGRAM) -D creator/mayflower $(DESTDIR)/usr/lib/livecd-creator/mayflower
	$(INSTALL_PROGRAM) -D creator/run-init $(DESTDIR)/usr/lib/livecd-creator/run-init
	$(INSTALL_DATA) -D AUTHORS $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)/AUTHORS
	$(INSTALL_DATA) -D COPYING $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)/COPYING
	$(INSTALL_DATA) -D README $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)/README
	$(INSTALL_DATA) -D HACKING $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)/HACKING
	$(INSTALL_PROGRAM) -D installer/livecd-installer $(DESTDIR)/usr/libexec/livecd-installer
	$(INSTALL_PROGRAM) -D installer/livecd-installer-tui $(DESTDIR)/usr/bin/livecd-installer-tui
	$(INSTALL_PROGRAM) -D installer/livecd-install-daemon $(DESTDIR)/etc/rc.d/init.d/livecd-install-daemon
	$(INSTALL_DATA) -D installer/livecd-installer.conf $(DESTDIR)/etc/dbus-1/system.d/livecd-installer.conf

uninstall:
	rm -f $(DESTDIR)/usr/bin/livecd-creator
	rm -rf $(DESTDIR)/usr/lib/livecd-creator
	rm -rf $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)
	rm -f $(DESTDIR)/usr/libexec/livecd-installer
	rm -f $(DESTDIR)/usr/bin/livecd-installer-tui
	rm -f $(DESTDIR)/etc/rc.d/init.d/livecd-install-daemon
	rm -f $(DESTDIR)/etc/dbus-1/system.d/livecd-installer.conf

DIST_FILES=AUTHORS COPYING README Makefile
DIST_FILES+=creator/livecd-creator creator/mayflower
DIST_FILES+=creator/run-init.c creator/run-init.h creator/runinitlib.c
DIST_FILES+=installer/livecd-installer installer/livecd-installer-tui
DIST_FILES+=installer/livecd-install-daemon livecd-installer.conf

dist : all
	git-tar-tree HEAD livecd-tools-$(VERSION) | bzip2 -9v > livecd-tools-$(VERSION).tar.bz2

clean:
	rm -f *~ creator/*~ creator/run-init installer/*~
