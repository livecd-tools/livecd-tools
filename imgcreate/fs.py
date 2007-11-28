#!/usr/bin/python -tt
#
# fs.py : Filesystem related utilities and classes
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
import os.path
import errno
import stat
import subprocess

class MountError(Exception):
    def __init__(self, msg):
        Exception.__init__(self, msg)

def makedirs(dirname):
    """A version of os.makedirs() that doesn't throw an
    exception if the leaf directory already exists.
    """
    try:
        os.makedirs(dirname)
    except OSError, (err, msg):
        if err != errno.EEXIST:
            raise

def mksquashfs(output, filelist, cwd = None):
    args = ["/sbin/mksquashfs"]
    args.extend(filelist)
    args.append(output)
    if not sys.stdout.isatty():
        args.append("-no-progress")
    if cwd is None:
        cwd = os.getcwd()
    return subprocess.call(args, cwd = cwd,  env={"PWD": cwd})

class BindChrootMount:
    """Represents a bind mount of a directory into a chroot."""
    def __init__(self, src, chroot, dest = None):
        self.src = src
        self.root = chroot

        if not dest:
            dest = src
        self.dest = self.root + "/" + dest

        self.mounted = False

    def mount(self):
        if not self.mounted:
            makedirs(self.dest)
            rc = subprocess.call(["/bin/mount", "--bind", self.src, self.dest])
            if rc != 0:
                raise MountError("Bind-mounting '%s' to '%s' failed" % (self.src, self.dest))
            self.mounted = True

    def umount(self):
        if self.mounted:
            rc = subprocess.call(["/bin/umount", self.dest])
            self.mounted = False
        

class LoopbackMount:
    def __init__(self, lofile, mountdir, fstype = None):
        self.lofile = lofile
        self.mountdir = mountdir
        self.fstype = fstype

        self.mounted = False
        self.losetup = False
        self.rmdir   = False
        self.loopdev = None

    def cleanup(self):
        self.umount()
        self.lounsetup()

    def umount(self):
        if self.mounted:
            rc = subprocess.call(["/bin/umount", self.mountdir])
            self.mounted = False

        if self.rmdir:
            try:
                os.rmdir(self.mountdir)
            except OSError, e:
                pass
            self.rmdir = False

    def lounsetup(self):
        if self.losetup:
            rc = subprocess.call(["/sbin/losetup", "-d", self.loopdev])
            self.losetup = False
            self.loopdev = None

    def loopsetup(self):
        if self.losetup:
            return

        losetupProc = subprocess.Popen(["/sbin/losetup", "-f"],
                                       stdout=subprocess.PIPE)
        losetupOutput = losetupProc.communicate()[0]

        if losetupProc.returncode:
            raise MountError("Failed to allocate loop device for '%s'" % self.lofile)
        else:
            self.loopdev = losetupOutput.split()[0]

        rc = subprocess.call(["/sbin/losetup", self.loopdev, self.lofile])
        if rc != 0:
            raise MountError("Failed to allocate loop device for '%s'" % self.lofile)

        self.losetup = True

    def mount(self):
        if self.mounted:
            return

        self.loopsetup()

        if not os.path.isdir(self.mountdir):
            os.makedirs(self.mountdir)
            self.rmdir = True

        args = [ "/bin/mount", self.loopdev, self.mountdir ]
        if self.fstype:
            args.extend(["-t", self.fstype])

        rc = subprocess.call(args)
        if rc != 0:
            raise MountError("Failed to mount '%s' to '%s'" % (self.loopdev, self.mountdir))

        self.mounted = True

class SparseExt3LoopbackMount(LoopbackMount):
    def __init__(self, lofile, mountdir, size, blocksize, fslabel):
        LoopbackMount.__init__(self, lofile, mountdir, fstype = "ext3")
        self.size = size
        self.blocksize = blocksize
        self.fslabel = fslabel

    def _expandSparseFile(self, create = False):
        flags = os.O_WRONLY
        if create:
            flags |= os.O_CREAT
            makedirs(os.path.dirname(self.lofile))

        fd = os.open(self.lofile, flags)

        os.lseek(fd, self.size, 0)
        os.write(fd, '\x00')
        os.close(fd)

    def _truncateSparseFile(self):
        fd = os.open(self.lofile, os.O_WRONLY )
        os.ftruncate(fd, self.size)
        os.close(fd)

    def _formatFilesystem(self):
        rc = subprocess.call(["/sbin/mkfs.ext3", "-F", "-L", self.fslabel,
                              "-m", "1", "-b", str(self.blocksize), self.lofile,
                              str(self.size / self.blocksize)])
        if rc != 0:
            raise MountError("Error creating ext3 filesystem")
        rc = subprocess.call(["/sbin/tune2fs", "-c0", "-i0", "-Odir_index",
                              "-ouser_xattr,acl", self.lofile])

    def _resizeFilesystem(self):
        dev_null = os.open("/dev/null", os.O_WRONLY)
        try:
            return subprocess.call(["/sbin/resize2fs",
                                    self.lofile, "%sk" % (self.size / 1024,)],
                                   stdout = dev_null, stderr = dev_null)
        finally:
            os.close(dev_null)

    def create(self):
        self._expandSparseFile(create = True)
        self._formatFilesystem()

    def resize(self):
        current_size = os.stat(self.lofile)[stat.ST_SIZE]

        if self.size == current_size:
            return

        if self.size < current_size:
            self._expandSparseFile()

        self._resizeFilesystem()

        if self.size > current_size:
            self._truncateSparseFile()

    def mount(self):
        if not os.path.isfile(self.lofile):
            self.create()
        else:
            self.resize()
        return LoopbackMount.mount(self)
