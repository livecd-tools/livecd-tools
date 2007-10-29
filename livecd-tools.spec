%define debug_package %{nil}

Summary: Tools for building live CD's
Name: livecd-tools
Version: 013
Release: 1%{?dist}
License: GPL
Group: System Environment/Base
URL: http://git.fedoraproject.org/?p=hosted/livecd
Source0: %{name}-%{version}.tar.bz2
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
Requires: util-linux
Requires: coreutils
Requires: e2fsprogs
Requires: yum >= 3.0.0
Requires: mkisofs
Requires: squashfs-tools
Requires: pykickstart
Requires: dosfstools >= 2.11-8
Requires: isomd5sum
%ifarch %{ix86} x86_64
Requires: syslinux
%endif
%ifarch ppc ppc64
Requires: yaboot
%endif


%description 
Tools for generating live CD's on Fedora based systems including
derived distributions such as RHEL, CentOS and others. See
http://fedoraproject.org/wiki/FedoraLiveCD for more details.

%prep
%setup -q

%build
make

%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%doc AUTHORS COPYING README HACKING
%{_bindir}/livecd-creator
%{_bindir}/livecd-iso-to-disk
%dir /usr/lib/livecd-creator
/usr/lib/livecd-creator/mayflower
%dir %{_datadir}/livecd-tools
%{_datadir}/livecd-tools/*

%changelog
* Mon Oct 29 2007 Jeremy Katz <katzj@redhat.com> - 013-1
- Lots of config updates
- Support 'device foo' to say what modules go in the initramfs
- Support multiple kernels being installed
- Allow blacklisting kernel modules on boot with blacklist=foo
- Improve bootloader configs
- Split configs off for f8

* Tue Sep 25 2007 Jeremy Katz <katzj@redhat.com> - 012-1
- Allow %%post --nochroot to work for putting files in the root of the iso
- Set environment variables for when %%post is run
- Add progress for downloads (Colin Walters)
- Add cachedir option (Colin Walters)
- Fixes for ppc/ppc64 to work again
- Clean up bootloader config a little
- Enable swaps in the default desktop config
- Ensure all configs are installed (#281911)
- Convert method line to a repo for easier config reuse (jkeating)
- Kill the modprobe FATAL warnings (#240585)
- Verify isos with iso-to-disk script
- Allow passing xdriver for setting the xdriver (#291281)
- Add turboliveinst patch (Douglas McClendon)
- Make iso-to-disk support --resetmbr (#294041)
- Clean up filesystem layout (Douglas McClendon)
- Manifest tweaks for most configs

* Tue Aug 28 2007 Jeremy Katz <katzj@redhat.com> - 011-1
- Many config updates for Fedora 8
- Support $basearch in repo line of configs; use it
- Support setting up Xen kernels and memtest86+ in the bootloader config
- Handle rhgb setup
- Improved default fs label (Colin Walters)
- Support localboot from the bootloader (#252192)
- Use hidden menu support in syslinux
- Have a base desktop config included by the other configs (Colin Walters)
- Use optparse for optino parsing
- Remove a lot of command line options; things should be specified via the
  kickstart config instead
- Beginnings of PPC support (David Woodhouse)
- Clean up kernel module inclusion to take advantage of files in Fedora
  kernels listing storage drivers

* Wed Jul 25 2007 Jeremy Katz <katzj@redhat.com> - 010-1
- Separate out configs used for Fedora 7
- Add patch from Douglas McClendon to make images smaller
- Add patch from Matt Domsch to work with older syslinux without vesamenu
- Add support for using mirrorlists; use them
- Let livecd-iso-to-disk work with uncompressed images (#248081)
- Raise error if SELinux requested without being enabled (#248080)
- Set service defaults on level 2 also (#246350)
- Catch some failure cases
- Allow specifying tmpdir
- Add patch from nameserver specification from Elias Hunt

* Wed May 30 2007 Jeremy Katz <katzj@redhat.com> - 009-1
- miscellaneous live config changes
- fix isomd5 checking syntax error

* Fri May  4 2007 Jeremy Katz <katzj@redhat.com> - 008-1
- disable screensaver with default config
- add aic7xxx and sym53c8xx drivers to default initramfs
- fixes from johnp for FC6 support in the creator
- fix iso-to-stick to work on FC6

* Tue Apr 24 2007 Jeremy Katz <katzj@redhat.com> - 007-1
- Disable prelinking by default
- Disable some things that slow down the live boot substantially
- Lots of tweaks to the default package manifests
- Allow setting the root password (Jeroen van Meeuwen)
- Allow more specific network line setting (Mark McLoughlin)
- Don't pollute the host yum cache (Mark McLoughlin)
- Add support for mediachecking

* Wed Apr  4 2007 Jeremy Katz <katzj@redhat.com> - 006-1
- Many fixes to error handling from Mark McLoughlin
- Add the KDE config
- Add support for prelinking
- Fixes for installing when running from RAM or usb stick
- Add sanity checking to better ensure that USB stick is bootable

* Thu Mar 29 2007 Jeremy Katz <katzj@redhat.com> - 005-3
- have to use excludearch, not exclusivearch

* Thu Mar 29 2007 Jeremy Katz <katzj@redhat.com> - 005-2
- exclusivearch since it only works on x86 and x86_64 for now

* Wed Mar 28 2007 Jeremy Katz <katzj@redhat.com> - 005-1
- some shell quoting fixes
- allow using UUID or LABEL for the fs label of a usb stick
- work with ext2 formated usb stick

* Mon Mar 26 2007 Jeremy Katz <katzj@redhat.com> - 004-1
- add livecd-iso-to-disk for setting up the live CD iso image onto a usb 
  stick or similar

* Fri Mar 23 2007 Jeremy Katz <katzj@redhat.com> - 003-1
- fix remaining reference to run-init

* Thu Mar 22 2007 Jeremy Katz <katzj@redhat.com> - 002-1
- update for new version

* Fri Dec 22 2006 David Zeuthen <davidz@redhat.com> - 001-1%{?dist}
- Initial build.

