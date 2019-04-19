
VERSION = 27.1

INSTALL = /usr/bin/install -c
INSTALL_PROGRAM = $(INSTALL)
INSTALL_DATA = $(INSTALL) -m 644
INSTALL_SCRIPT = $(INSTALL_PROGRAM)
PYTHON = python
PYTHON_PROGRAM = $(shell which $(PYTHON))
SED_PROGRAM = /usr/bin/sed

INSTALL_PYTHON = $(INSTALL) -m 644
define COMPILE_PYTHON
	$(PYTHON_PROGRAM) -c "import compileall as c; c.compile_dir('$(1)', force=1)"
	$(PYTHON_PROGRAM) -O -c "import compileall as c; c.compile_dir('$(1)', force=1)"
endef
PYTHONDIR := $(shell $(PYTHON_PROGRAM) -c "from __future__ import print_function; from distutils.sysconfig import get_python_lib; print(get_python_lib())")

all: 

man:
	pod2man --section=8 --release="livecd-tools $(VERSION)" --center "LiveCD Tools" docs/livecd-creator.pod > docs/livecd-creator.8
	pod2man --section=8 --release="livecd-tools $(VERSION)" --center "LiveCD Tools" docs/livecd-iso-to-disk.pod > docs/livecd-iso-to-disk.8


install: man
	$(INSTALL_PROGRAM) -D tools/livecd-creator $(DESTDIR)/usr/bin/livecd-creator
	ln -sf livecd-creator $(DESTDIR)/usr/bin/image-creator
	$(INSTALL_PROGRAM) -D tools/liveimage-mount $(DESTDIR)/usr/bin/liveimage-mount
	$(INSTALL_PROGRAM) -D tools/livecd-iso-to-disk.sh $(DESTDIR)/usr/bin/livecd-iso-to-disk
	$(INSTALL_PROGRAM) -D tools/livecd-iso-to-pxeboot.sh $(DESTDIR)/usr/bin/livecd-iso-to-pxeboot
	$(INSTALL_PROGRAM) -D tools/editliveos $(DESTDIR)/usr/bin/editliveos
	$(INSTALL_PROGRAM) -D tools/mkbiarch $(DESTDIR)/usr/bin/mkbiarch
	$(INSTALL_DATA) -D AUTHORS $(DESTDIR)/usr/share/doc/livecd-tools/AUTHORS
	$(INSTALL_DATA) -D COPYING $(DESTDIR)/usr/share/doc/livecd-tools/COPYING
	$(INSTALL_DATA) -D README $(DESTDIR)/usr/share/doc/livecd-tools/README
	$(INSTALL_DATA) -D HACKING $(DESTDIR)/usr/share/doc/livecd-tools/HACKING
	mkdir -p $(DESTDIR)/usr/share/livecd-tools/
	mkdir -p $(DESTDIR)/$(PYTHONDIR)/imgcreate
	$(INSTALL_PYTHON) -D imgcreate/*.py $(DESTDIR)/$(PYTHONDIR)/imgcreate/
	$(call COMPILE_PYTHON,$(DESTDIR)/$(PYTHONDIR)/imgcreate)
	mkdir -p $(DESTDIR)/usr/share/man/man8
	$(INSTALL_DATA) -D docs/*.8 $(DESTDIR)/usr/share/man/man8
	$(SED_PROGRAM) -i "s:#!/usr/bin/python:#!$(PYTHON_PROGRAM):g" $(DESTDIR)/usr/bin/livecd-creator
	$(SED_PROGRAM) -i "s:#!/usr/bin/python:#!$(PYTHON_PROGRAM):g" $(DESTDIR)/usr/bin/liveimage-mount
	$(SED_PROGRAM) -i "s:#!/usr/bin/python:#!$(PYTHON_PROGRAM):g" $(DESTDIR)/usr/bin/editliveos
	$(SED_PROGRAM) -i "s:#!/usr/bin/python:#!$(PYTHON_PROGRAM):g" $(DESTDIR)/usr/bin/mkbiarch

uninstall:
	rm -f $(DESTDIR)/usr/bin/livecd-creator
	rm -rf $(DESTDIR)/usr/lib/livecd-creator
	rm -rf $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)
	rm -f $(DESTDIR)/usr/bin/mkbiarch

dist : all
	git archive --format=tar --prefix=livecd-tools-$(VERSION)/ HEAD | gzip -9v > livecd-tools-$(VERSION).tar.gz

release: dist
	git tag -s -a -m "Tag as livecd-tools-$(VERSION)" livecd-tools-$(VERSION)

clean:
	rm -f *~ creator/*~ installer/*~ config/*~ docs/*.8
