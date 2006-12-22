
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

uninstall:
	rm -f $(DESTDIR)/usr/bin/livecd-creator
	rm -f $(DESTDIR)/usr/lib/livecd-creator/mayflower
	rm -f $(DESTDIR)/usr/lib/livecd-creator/run-init

clean:
	rm -f *~ creator/*~ creator/run-init
