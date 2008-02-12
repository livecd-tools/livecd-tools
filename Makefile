
VERSION = 014

INSTALL = /usr/bin/install -c
INSTALL_PROGRAM = ${INSTALL}
INSTALL_DATA = ${INSTALL} -m 644
INSTALL_SCRIPT = ${INSTALL_PROGRAM}

INSTALL_PYTHON = ${INSTALL} -m 644
define COMPILE_PYTHON
	python -c "import compileall as c; c.compile_dir('$(1)', force=1)"
	python -O -c "import compileall as c; c.compile_dir('$(1)', force=1)"
endef
PYTHONDIR := $(shell python -c "import distutils.sysconfig as d; print d.get_python_lib()")

all: 

install:
	$(INSTALL_PROGRAM) -D tools/livecd-creator $(DESTDIR)/usr/bin/livecd-creator
	$(INSTALL_PROGRAM) -D tools/image-creator $(DESTDIR)/usr/bin/image-creator
	$(INSTALL_PROGRAM) -D tools/livecd-iso-to-disk.sh $(DESTDIR)/usr/bin/livecd-iso-to-disk
	$(INSTALL_PROGRAM) -D tools/mayflower $(DESTDIR)/usr/lib/livecd-creator/mayflower
	$(INSTALL_DATA) -D AUTHORS $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)/AUTHORS
	$(INSTALL_DATA) -D COPYING $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)/COPYING
	$(INSTALL_DATA) -D README $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)/README
	$(INSTALL_DATA) -D HACKING $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)/HACKING
	mkdir -p $(DESTDIR)/usr/share/livecd-tools/
	$(INSTALL_DATA) -D config/*.ks $(DESTDIR)/usr/share/livecd-tools/
	mkdir -p $(DESTDIR)/$(PYTHONDIR)/imgcreate
	$(INSTALL_PYTHON) -D imgcreate/*.py $(DESTDIR)/$(PYTHONDIR)/imgcreate/
	$(call COMPILE_PYTHON,$(DESTDIR)/$(PYTHONDIR)/imgcreate)

uninstall:
	rm -f $(DESTDIR)/usr/bin/livecd-creator
	rm -rf $(DESTDIR)/usr/lib/livecd-creator
	rm -rf $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)
	rm -rf $(DESTDIR)/usr/share/livecd-tools

dist : all
	git-archive --format=tar --prefix=livecd-tools-$(VERSION)/ HEAD | bzip2 -9v > livecd-tools-$(VERSION).tar.bz2

clean:
	rm -f *~ creator/*~ installer/*~ config/*~
