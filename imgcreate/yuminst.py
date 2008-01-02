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

import os
import sys

import yum
import rpmUtils
import pykickstart.parser

from yuminst import *

class TextProgress(object):
    def start(self, filename, url, *args, **kwargs):
        sys.stdout.write("Retrieving %s " % (url,))
        self.url = url
    def update(self, *args):
        pass
    def end(self, *args):
        sys.stdout.write("...OK\n")

class LiveCDYum(yum.YumBase):
    def __init__(self):
        yum.YumBase.__init__(self)

    def doFileLogSetup(self, uid, logfile):
        # don't do the file log for the livecd as it can lead to open fds
        # being left and an inability to clean up after ourself
        pass

    def close(self):
        try:
            os.unlink(self.conf.installroot + "/yum.conf")
        except:
            pass
        try:
            yum.YumBase.close(self)
        except AttributeError:
            # FIXME: Make one last ditch effort to close fds still open
            # in the install root; this is only needed when
            # there's no way to ask yum to close its sqlite dbs,
            # though. See https://bugzilla.redhat.com/236409
            for i in range(3, os.sysconf("SC_OPEN_MAX")):
                try:
                    os.close(i)
                except:
                    pass

    def _writeConf(self, confpath, installroot):
        conf  = "[main]\n"
        conf += "installroot=%s\n" % installroot
        conf += "cachedir=/var/cache/yum\n"
        conf += "plugins=0\n"
        conf += "reposdir=\n"

        f = file(confpath, "w+")
        f.write(conf)
        f.close()

        os.chmod(confpath, 0644)

    def setup(self, confpath, installroot):
        self._writeConf(confpath, installroot)
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
            map(lambda x: self.tsInfo.remove(x.pkgtup), txmbrs)
        else:
            print >> sys.stderr, "No such package %s to remove" %(pkg,)

    def selectGroup(self, grp, include = pykickstart.parser.GROUP_DEFAULT):
        yum.YumBase.selectGroup(self, grp)
        if include == pykickstart.parser.GROUP_REQUIRED:
            map(lambda p: self.deselectPackage(p), grp.default_packages.keys())
        elif include == pykickstart.parser.GROUP_ALL:
            map(lambda p: self.selectPackage(p), grp.optional_packages.keys())

    def addRepository(self, name, url = None, mirrorlist = None):
        def _varSubstitute(option):
            # takes a variable and substitutes like yum configs do
            option = option.replace("$basearch", rpmUtils.arch.getBaseArch())
            option = option.replace("$arch", rpmUtils.arch.getCanonArch())
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
        # disable gpg check???
        repo.gpgcheck = 0
        repo.enable()
        repo.setup(0)
        repo.setCallback(TextProgress())
        self.repos.add(repo)
        return repo
            
    def runInstall(self):
        try:
            (res, resmsg) = self.buildTransaction()
        except yum.Errors.RepoError, e:
            raise CreatorError("Unable to download from repo : %s" %(e,))
        if res != 2 and False:
            raise CreatorError("Failed to build transaction : %s" % str.join("\n", resmsg))
        
        dlpkgs = map(lambda x: x.po, filter(lambda txmbr: txmbr.ts_state in ("i", "u"), self.tsInfo.getMembers()))
        self.downloadPkgs(dlpkgs)
        # FIXME: sigcheck?
        
        self.initActionTs()
        self.populateTs(keepold=0)
        self.ts.check()
        self.ts.order()
        # FIXME: callback should be refactored a little in yum 
        sys.path.append('/usr/share/yum-cli')
        import callback
        cb = callback.RPMInstallCallback()
        cb.tsInfo = self.tsInfo
        cb.filelog = False
        return self.runTransaction(cb)
