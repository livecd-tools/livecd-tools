#
# dnfinst.py : dnf utilities
#
# Copyright 2007, Red Hat  Inc.
# Copyright 2016, Kevin Kofler
# Copyright 2016, Neal Gompa
#
# Portions from Anaconda dnfpayload.py
# DNF/rpm software payload management.
#
# Copyright (C) 2013-2015  Red Hat, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Library General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

from __future__ import print_function
import glob
import os
import sys
import logging
import itertools

import dnf
import dnf.rpm
# FIXME: Why are these hidden inside dnf.cli? Any text-mode app should be able
#        to make use of these.
from dnf.cli.progress import MultiFileProgressMeter as DownloadProgress
from dnf.cli.output import CliTransactionDisplay as TransactionProgress
import hawkey
from pykickstart.constants import GROUP_DEFAULT, GROUP_REQUIRED, GROUP_ALL

from imgcreate.errors import *

class DnfLiveCD(dnf.Base):
    def __init__(self, releasever=None, useplugins=False):
        """
        releasever = optional value to use in replacing $releasever in repos
        """
        dnf.Base.__init__(self)
        self.releasever = releasever
        self.useplugins = useplugins

    def doFileLogSetup(self, uid, logfile):
        # don't do the file log for the livecd as it can lead to open fds
        # being left and an inability to clean up after ourself
        pass

    def close(self):
        try:
            os.unlink(self.conf.installroot + "/dnf.conf")
        except:
            pass
        dnf.Base.close(self)

    def __del__(self):
        pass

    def _writeConf(self, confpath, installroot):
        conf  = "[main]\n"
        conf += "installroot=%s\n" % installroot
        conf += "cachedir=/var/cache/dnf\n"
        if self.useplugins:
            conf += "plugins=1\n"
        else:
            conf += "plugins=0\n"
        conf += "reposdir=\n"
        conf += "failovermethod=priority\n"
        conf += "keepcache=1\n"
        conf += "tsflags=nocontexts\n"

        f = open(confpath, "w+")
        f.write(conf)
        f.close()

        os.chmod(confpath, 0o644)

    def _cleanupRpmdbLocks(self, installroot):
        # cleans up temporary files left by bdb so that differing
        # versions of rpm don't cause problems
        for f in glob.glob(installroot + "/var/lib/rpm/__db*"):
            os.unlink(f)

    def setup(self, confpath, installroot, cacheonly=False, excludeWeakdeps=False):
        self._writeConf(confpath, installroot)
        self._cleanupRpmdbLocks(installroot)
        self.conf.read(confpath)
        self.conf.installroot = installroot
        self.conf.prepend_installroot("cachedir")
        self.conf.prepend_installroot("persistdir")
        self.conf.install_weak_deps = not excludeWeakdeps
        if cacheonly:
            dnf.repo.Repo.DEFAULT_SYNC = dnf.repo.SYNC_ONLY_CACHE
        else:
            dnf.repo.Repo.DEFAULT_SYNC = dnf.repo.SYNC_TRY_CACHE

    def deselectPackage(self, pkg):
        """Deselect a given package.  Can be specified with name.arch or name*"""
        subj = dnf.subject.Subject(pkg)
        pkgs = subj.get_best_query(self.sack)
        # The only way to get expected behavior is to declare it
        # as excluded from the installable set
        return self.sack.add_excludes(pkgs)

    def selectPackage(self, pkg):
        """Select a given package.  Can be specified with name.arch or name*"""
        return self.install(pkg)
        
    def selectGroup(self, group_id, exclude, include = GROUP_DEFAULT):
        grp = self.comps.group_by_pattern(group_id)
        if grp is None:
            raise dnf.exceptions.MarkingError('no such group', '@' + group_id)
        # default to getting mandatory and default packages from a group
        # unless we have specific options from kickstart
        package_types = {'mandatory', 'default'}
        if include == GROUP_REQUIRED:
            package_types.remove('default')
        elif include == GROUP_ALL:
            package_types.add('optional')
        try:
            self.group_install(grp.id, package_types, exclude=exclude)
        except dnf.exceptions.CompsError as e:
            # DNF raises this when it is already selected
            pass

    def environmentGroups(self, environmentid, optional=True):
        env = self.comps.environment_by_pattern(environmentid)
        if env is None:
            dnf.exceptions.MarkingError('no such environment', '@^' + environmentid)
        group_ids = (id_.name for id_ in env.group_ids)
        option_ids = (id_.name for id_ in env.option_ids)
        if optional:
            return list(itertools.chain(group_ids, option_ids))
        else:
            return list(group_ids)

    def selectEnvironment(self, env_id, excluded, excludedPkgs):
        # dnf.base.environment_install excludes on packages instead of groups,
        # which is unhelpful. Instead, use group_install for each group in
        # the environment so we can skip the ones that are excluded.
        for groupid in set(self.environmentGroups(env_id, optional=False)) - set(excluded):
            self.selectGroup(groupid, excludedPkgs)

    def addRepository(self, name, url = None, mirrorlist = None):
        def _varSubstitute(option):
            # takes a variable and substitutes like dnf configs do
            arch = hawkey.detect_arch()
            option = option.replace("$basearch", dnf.rpm.basearch(arch))
            option = option.replace("$arch", arch)
            # If the url includes $releasever substitute user's value or
            # current system's version.
            if option.find("$releasever") > -1:
                if self.releasever:
                    option = option.replace("$releasever", self.releasever)
                else:
                    try:
                        detected_releasever = dnf.rpm.detect_releasever("/")
                    except dnf.exceptions.Error:
                        detected_releasever = None
                    if detected_releasever:
                        option = option.replace("$releasever", detected_releasever)
                    else:
                        raise CreatorError("$releasever in repo url, but no releasever set")
            return option

        try:
            # dnf 2
            repo = dnf.repo.Repo(name, parent_conf = self.conf)
        except TypeError as e:
            # dnf 1
            repo = dnf.repo.Repo(name, cachedir = self.conf.cachedir)
        if url:
            repo.baseurl.append(_varSubstitute(url))
        if mirrorlist:
            repo.mirrorlist = _varSubstitute(mirrorlist)
        repo.enable()
        repo.set_progress_bar(DownloadProgress())
        self.repos.add(repo)
        return repo

    def runInstall(self):
        import dnf.exceptions
        os.environ["HOME"] = "/"
        try:
            res = self.resolve()
        except dnf.exceptions.RepoError as e:
            raise CreatorError("Unable to download from repo : %s" %(e,))
        except dnf.exceptions.Error as e:
            raise CreatorError("Failed to build transaction : %s" %(e,))
        # Empty transactions are generally fine, we might be rebuilding an
        # existing image with no packages added
        if not res:
            return True

        dlpkgs = self.transaction.install_set
        self.download_packages(dlpkgs, DownloadProgress())
        # FIXME: sigcheck?

        ret = self.do_transaction(TransactionProgress())
        print("")
        self._cleanupRpmdbLocks(self.conf.installroot)
        return ret
