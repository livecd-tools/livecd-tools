
VERSION = 20.6

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

man:
	pod2man --section=8 --release="livecd-tools $(VERSION)" --center "LiveCD Tools" docs/livecd-creator.pod > docs/livecd-creator.8
	pod2man --section=8 --release="livecd-tools $(VERSION)" --center "LiveCD Tools" docs/livecd-iso-to-disk.pod > docs/livecd-iso-to-disk.8


install: man
	$(INSTALL_PROGRAM) -D tools/livecd-creator $(DESTDIR)/usr/bin/livecd-creator
	ln -s ./livecd-creator $(DESTDIR)/usr/bin/image-creator
	$(INSTALL_PROGRAM) -D tools/liveimage-mount $(DESTDIR)/usr/bin/liveimage-mount
	$(INSTALL_PROGRAM) -D tools/livecd-iso-to-disk.sh $(DESTDIR)/usr/bin/livecd-iso-to-disk
	$(INSTALL_PROGRAM) -D tools/livecd-iso-to-pxeboot.sh $(DESTDIR)/usr/bin/livecd-iso-to-pxeboot
	$(INSTALL_PROGRAM) -D tools/edit-livecd $(DESTDIR)/usr/bin/edit-livecd
	$(INSTALL_PROGRAM) -D tools/mkbiarch.py $(DESTDIR)/usr/bin/mkbiarch
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

uninstall:
	rm -f $(DESTDIR)/usr/bin/livecd-creator
	rm -rf $(DESTDIR)/usr/lib/livecd-creator
	rm -rf $(DESTDIR)/usr/share/doc/livecd-tools-$(VERSION)
	rm -f $(DESTDIR)/usr/bin/mkbiarch

dist : all
	git archive --format=tar --prefix=livecd-tools-$(VERSION)/ HEAD | bzip2 -9v > livecd-tools-$(VERSION).tar.bz2

release: dist
	git tag -s -a -m "Tag as livecd-tools-$(VERSION)" livecd-tools-$(VERSION)
	scp livecd-tools-$(VERSION).tar.bz2 fedorahosted.org:livecd

clean:
	rm -f *~ creator/*~ installer/*~ config/*~ docs/*.8
