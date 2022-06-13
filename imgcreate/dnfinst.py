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
import os.path
import sys
import logging
import itertools
from urllib.parse import urljoin

import dnf
import dnf.conf.read
import dnf.rpm
import rpm
# FIXME: Why are these hidden inside dnf.cli? Any text-mode app should be able
#        to make use of these.
from dnf.cli.progress import MultiFileProgressMeter as DownloadProgress
from dnf.cli.output import CliTransactionDisplay as TransactionProgress
import hawkey
from pykickstart.constants import GROUP_DEFAULT, GROUP_REQUIRED, GROUP_ALL

from imgcreate.errors import *

class DnfLiveCD(dnf.Base):
    def __init__(self, releasever=None, useplugins=False, pkgverify_level=None):
        """
        releasever = optional value to use in replacing $releasever in repos
        """
        dnf.Base.__init__(self)
        self.releasever = releasever
        if releasever:
            self.conf.substitutions['releasever'] = releasever
        self.useplugins = useplugins
        self.pkgverify_level = pkgverify_level

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
        conf += "reposdir=/dev/null\n"
        conf += "failovermethod=priority\n"
        conf += "keepcache=1\n"
        conf += "obsoletes=1\n"
        conf += "best=1\n"
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
            self.group_install(grp.id, tuple(package_types), exclude=exclude)
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
            # some overly clever trickery in dnf 3 prevents us just
            # using repo.baseurl.append here:
            # https://bugzilla.redhat.com/show_bug.cgi?id=1595917
            # with the change to representing it as a tuple in DNF 3.6
            # this '+= (tuple)' approach seems to work for DNF 2,
            # 3.0-3.5 *and* 3.6
            repo.baseurl += (_varSubstitute(url),)
        if mirrorlist:
            repo.mirrorlist = _varSubstitute(mirrorlist)
        repo.enable()
        repo.set_progress_bar(DownloadProgress())
        self.repos.add(repo)
        return repo

    def addRepositoryFromConfigFile(self, repo):
        """
        Import repository configuration from a DNF repo file instead of
        from kickstart. If repo is a directory, all *.repo files in that
        directory are imported.
        """

        def _to_abs_paths(basedir, paths):
            # replace filenames (relative to basedir) with absolute URLs
            for path in map(str, paths):
                path = os.path.expanduser(path)
                absurl = urljoin(
                    'file://%s/' % os.path.abspath(basedir),
                    path
                )
                yield absurl

        logging.debug("searching for DNF repositories in \"%s\"", repo)
        if os.path.isdir(repo):
            repo_dir = repo
            self.conf.reposdir = (repo)
            self.conf.config_file_path = '/dev/null'
        elif os.path.exists(repo):
            repo_dir = os.path.dirname(repo)
            self.conf.reposdir = ()
            self.conf.config_file_path = repo
        else:
            raise CreatorError(\
                "Unable to read repo configuration: \"%s\" does not exist" \
                    % (repo))

        self.read_all_repos()

        # override configuration
        found_enabled_repos = 0
        for repo in self.repos.iter_enabled():
            logging.debug("repo:\n%s", repo.dump())
            logging.info('repo: %s (gpg=%s): %s', repo.id,
                         repo.gpgcheck, repo.name)

            repo.set_progress_bar(DownloadProgress())
            repo.gpgkey = list(_to_abs_paths(repo_dir, repo.gpgkey))
            found_enabled_repos += 1

        # read_all_repos() may pass errors silently
        # check that the command loaded at least one enabled repo
        if found_enabled_repos <= 0:
            with_dir = ''
            if os.path.isdir(repo):
                with_dir = ' .repo files with'
            raise CreatorError(
                "Unable to read repo configuration: \"%s\" does not " % repo +
                "contain any%s enabled RPM repositories. " % with_dir +
                "Check that this path contains dnf INI-style repo " +
                "definitions like /etc/yum.repos.d. See `man 5 dnf.conf`.")

    def setPkgVerifyLevel(self, pkgverify_level):
        """
        Configure RPM's %_pkgverify_level macro

        Enforced package verification level (see /usr/lib/rpm/macros):
          all           require valid digest(s) and signature(s)
          signature     require valid signature(s)
          digest        require valid digest(s)
          none          traditional rpm behavior, nothing required
        """
        self.pkgverify_level = pkgverify_level

    def runInstall(self):
        """
        Install packages
        """
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

        # check gpg signatures (repo must be gpgcheck=1)
        #   We auto-import all dnf repository keys as we
        #   encounter them.
        if self.pkgverify_level not in ('digest', 'none'):
            for pkg in dlpkgs:
                res, err = self.package_signature_check(pkg)
                if res == 0:
                    continue
                elif res == 1:
                    self.package_import_key(pkg, lambda _x, _y, _z: True)
                    res, err = self.package_signature_check(pkg)

                if res != 0:
                    raise CreatorError(err)

        if self.pkgverify_level:
            rpm.addMacro("_pkgverify_level", self.pkgverify_level)

        ret = self.do_transaction(TransactionProgress())
        print("")
        self._cleanupRpmdbLocks(self.conf.installroot)
        return ret
