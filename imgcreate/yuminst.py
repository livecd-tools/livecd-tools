#
# yum.py : yum utilities
#
# Copyright 2007, Red Hat  Inc.
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

import glob
import os
import sys
import logging

import yum
import rpmUtils
import pykickstart.parser

from imgcreate.errors import *

class TextProgress(object):
    logger = logging.getLogger()
    def emit(self, lvl, msg):
        '''play nice with the logging module'''
        for hdlr in self.logger.handlers:
            if lvl >= self.logger.level:
                hdlr.stream.write(msg)
                hdlr.stream.flush()

    def start(self, filename, url, *args, **kwargs):
        self.emit(logging.INFO, "Retrieving %s " % (url,))
        self.url = url
    def update(self, *args):
        pass
    def end(self, *args):
        self.emit(logging.INFO, "...OK\n")

class LiveCDYum(yum.YumBase):
    def __init__(self, releasever=None):
        """
        releasever = optional value to use in replacing $releasever in repos
        """
        yum.YumBase.__init__(self)
        self.releasever = releasever

    def doFileLogSetup(self, uid, logfile):
        # don't do the file log for the livecd as it can lead to open fds
        # being left and an inability to clean up after ourself
        pass

    def close(self):
        try:
            os.unlink(self.conf.installroot + "/yum.conf")
        except:
            pass
        yum.YumBase.close(self)

    def __del__(self):
        pass

    def _writeConf(self, confpath, installroot):
        conf  = "[main]\n"
        conf += "installroot=%s\n" % installroot
        conf += "cachedir=/var/cache/yum\n"
        conf += "plugins=0\n"
        conf += "reposdir=\n"
        conf += "failovermethod=priority\n"
        conf += "keepcache=1\n"

        f = file(confpath, "w+")
        f.write(conf)
        f.close()

        os.chmod(confpath, 0644)

    def _cleanupRpmdbLocks(self, installroot):
        # cleans up temporary files left by bdb so that differing
        # versions of rpm don't cause problems
        for f in glob.glob(installroot + "/var/lib/rpm/__db*"):
            os.unlink(f)

    def setup(self, confpath, installroot):
        self._writeConf(confpath, installroot)
        self._cleanupRpmdbLocks(installroot)
        self.doConfigSetup(fn = confpath, root = installroot)
        self.conf.cache = 0
        self.doTsSetup()
        self.doRpmDBSetup()
        self.doRepoSetup()
        self.doSackSetup()

    def selectPackage(self, pkg):
        """Select a given package.  Can be specified with name.arch or name*"""
        return self.install(pattern = pkg)
        
    def deselectPackage(self, pkg):
        """Deselect package.  Can be specified as name.arch or name*"""
        sp = pkg.rsplit(".", 2)
        txmbrs = []
        if len(sp) == 2:
            txmbrs = self.tsInfo.matchNaevr(name=sp[0], arch=sp[1])

        if len(txmbrs) == 0:
            exact, match, unmatch = yum.packages.parsePackages(self.pkgSack.returnPackages(), [pkg], casematch=1)
            for p in exact + match:
                txmbrs.append(p)

        if len(txmbrs) > 0:
            for x in txmbrs:
                self.tsInfo.remove(x.pkgtup)
                # we also need to remove from the conditionals
                # dict so that things don't get pulled back in as a result
                # of them.  yes, this is ugly.  conditionals should die.
                for req, pkgs in self.tsInfo.conditionals.iteritems():
                    if x in pkgs:
                        pkgs.remove(x)
                        self.tsInfo.conditionals[req] = pkgs
        else:
            logging.warn("No such package %s to remove" %(pkg,))

    def selectGroup(self, grp, include = pykickstart.parser.GROUP_DEFAULT):
        # default to getting mandatory and default packages from a group
        # unless we have specific options from kickstart
        package_types = ['mandatory', 'default']
        if include == pykickstart.parser.GROUP_REQUIRED:
            package_types.remove('default')
        elif include == pykickstart.parser.GROUP_ALL:
            package_types.append('optional')
        yum.YumBase.selectGroup(self, grp, group_package_types=package_types)

    def addRepository(self, name, url = None, mirrorlist = None):
        def _varSubstitute(option):
            # takes a variable and substitutes like yum configs do
            option = option.replace("$basearch", rpmUtils.arch.getBaseArch())
            option = option.replace("$arch", rpmUtils.arch.getCanonArch())
            # If the url includes $releasever substitute user's value or
            # current system's version.
            if option.find("$releasever") > -1:
                if self.releasever:
                    option = option.replace("$releasever", self.releasever)
                else:
                    try:
                        option = option.replace("$releasever", yum.config._getsysver("/", "redhat-release"))
                    except yum.Errors.YumBaseError:
                        raise CreatorError("$releasever in repo url, but no releasever set")
            return option

        repo = yum.yumRepo.YumRepository(name)
        if url:
            repo.baseurl.append(_varSubstitute(url))
        if mirrorlist:
            repo.mirrorlist = _varSubstitute(mirrorlist)
        conf = yum.config.RepoConf()
        for k, v in conf.iteritems():
            if v or not hasattr(repo, k):
                repo.setAttribute(k, v)
        repo.basecachedir = self.conf.cachedir
        repo.failovermethod = "priority"
        repo.metadata_expire = 0
        repo.mirrorlist_expire = 0
        repo.timestamp_check = 0
        # disable gpg check???
        repo.gpgcheck = 0
        repo.enable()
        repo.setup(0)
        repo.setCallback(TextProgress())
        self.repos.add(repo)
        return repo

    def installHasFile(self, file):
        provides_pkg = self.whatProvides(file, None, None)
        dlpkgs = map(lambda x: x.po, filter(lambda txmbr: txmbr.ts_state in ("i", "u"), self.tsInfo.getMembers()))
        for p in dlpkgs:
            for q in provides_pkg:
                if (p == q):
                    return True
        return False

            
    def runInstall(self):
        os.environ["HOME"] = "/"
        try:
            (res, resmsg) = self.buildTransaction()
        except yum.Errors.RepoError, e:
            raise CreatorError("Unable to download from repo : %s" %(e,))
        # Empty transactions are generally fine, we might be rebuilding an
        # existing image with no packages added
        if resmsg and resmsg[0].endswith(" - empty transaction"):
            return res
        if res != 2:
            raise CreatorError("Failed to build transaction : %s" % str.join("\n", resmsg))
        
        dlpkgs = map(lambda x: x.po, filter(lambda txmbr: txmbr.ts_state in ("i", "u"), self.tsInfo.getMembers()))
        self.downloadPkgs(dlpkgs)
        # FIXME: sigcheck?
        
        self.initActionTs()
        self.populateTs(keepold=0)
        deps = self.ts.check()
        if len(deps) != 0:
            raise CreatorError("Dependency check failed!")
        rc = self.ts.order()
        if rc != 0:
            raise CreatorError("ordering packages for installation failed!")

        # FIXME: callback should be refactored a little in yum 
        sys.path.append('/usr/share/yum-cli')
        import yum.misc
        yum.misc.setup_locale()
        import callback
        cb = callback.RPMInstallCallback()
        cb.tsInfo = self.tsInfo
        cb.filelog = False
        ret = self.runTransaction(cb)
        print ""
        self._cleanupRpmdbLocks(self.conf.installroot)
        return ret
