#
# fs.py : Filesystem related utilities and classes
#
# Copyright 2007, Red Hat  Inc.
# Copyright 2016, Neal Gompa
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
from __future__ import absolute_import
from __future__ import division
import os
import os.path
import sys
import errno
import stat
import subprocess
import random
import string
import logging
import tempfile
import time
from imgcreate.util import call

from imgcreate.errors import *

def chrootentitycheck(entity, chrootdir):
    """Check for entity availability in the chroot image.

    This is a blind check--be sure that the entity command is innocuous.
    """
    def _chroot():
        os.chroot(chrootdir)
        os.chdir('/')

    with open(os.devnull, 'w') as DEVNULL:
        try:
            subprocess.call(entity, stdout=DEVNULL, stderr=DEVNULL,
                            preexec_fn=_chroot)
        except OSError as e:
            if e.errno == errno.ENOENT:
                logging.info("The '%s' entity is not available." % entity)
                return False
        else:
            return True

def makedirs(dirname, dirmode=None):
    """A version of os.makedirs() that doesn't throw an
    exception if the leaf directory already exists.
    """

    dirmode = dirmode or 0o777
    try:
        os.makedirs(dirname, dirmode)
    except OSError as e:
        if e.errno != errno.EEXIST:
            raise

def squashfs_compression_type(sqfs_img):
    """Check the compression type of a SquashFS image. If the type cannot be
    ascertained, return 'undetermined'. The calling code must decide what to
    do."""

    env = os.environ.copy()
    env['LC_ALL'] = 'C'
    args = ['unsquashfs', '-s', sqfs_img]
    try:
        p = subprocess.Popen(args, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, env=env)
        out, err = p.communicate()
    except OSError as e:
        raise SquashfsError(u"Error white stat-ing '%s'\n'%s'" % (args, e))
    except:
        raise SquashfsError(u"Error while stat-ing '%s'" % args)
    else:
        if p.returncode != 0:
            raise SquashfsError(
                u"Error while stat-ing '%s'\n'%s'\nreturncode: '%s'" %
                (args, err, p.returncode))
        else:
            compress_type = 'undetermined'
            for l in out.splitlines():
                if l.split(None, 1)[0] == 'Compression':
                    compress_type = l.split()[1]
                    break
    return compress_type

def mksquashfs(in_img, out_img, compress_type, ops=None):
# Allow gzip to work for older versions of mksquashfs
    if not compress_type or compress_type == "gzip":
        args = ['mksquashfs', in_img, out_img]
    else:
        args = ['mksquashfs', in_img, out_img, '-comp', compress_type]

    if not sys.stdout.isatty():
        args.append("-no-progress")

    if ops == 'show-squashing':
        p = subprocess.Popen(args, stdout=None, stderr=subprocess.STDOUT)
        p.wait()
        ret = p.returncode
    else:
        ret = call(args)

    if ret != 0:
        raise SquashfsError("'%s' exited with error (%d)" %
                            (" ".join(args), ret))

def resize2fs(fs, size=None, minimal=False, ops=''):
    if minimal and size is not None:
        raise ResizeError("Can't specify both minimal and a size for resize!")

    args = ['resize2fs', '-p', fs]
    if ops == 'nocheck':
        args.append('-f')
    else:
        e2fsck(fs)

    logging.info("resizing %s" % (fs,))
    if minimal:
        args.append('-M')
    elif size:
        args.append('%sK' %(size // 1024,))
    ret = call(args)
    if ret != 0:
        raise ResizeError("resize2fs returned an error (%d)!" % (ret,))

    if ops != 'nocheck':
        ret = e2fsck(fs)
        if ret != 0:
            raise ResizeError("fsck after resize returned an error (%d)!" %
                              (ret,))

    return 0

def e2fsck(fs):
    logging.info("Checking filesystem %s" % fs)
    return call(['e2fsck', '-f', '-y', fs])


class LoopbackMount:
    """LoopbackMount  compatibility layer for old API"""
    def __init__(self, lofile, mountdir, fstype=None, ops=[], dirmode=None):
        self.diskmount = DiskMount(LoopbackDisk(lofile, size=0, ops=ops,
                                                dirmode=dirmode),
                                   mountdir, fstype, rmmountdir=True, ops=ops,
                                   dirmode=dirmode)
        self.losetup = False
        self.ops = ops
        self.dirmode = dirmode
        
    def cleanup(self):
        self.diskmount.cleanup()

    def unmount(self):
        self.diskmount.unmount()

    def lounsetup(self):
        if self.losetup:
            rc = call(['losetup', '-d', self.loopdev])
            self.losetup = False
            self.loopdev = None

    def loopsetup(self, ops=[]):
        if self.losetup:
            return

        losetupProc = subprocess.Popen(['losetup', '-f'],
                                       stdout=subprocess.PIPE)
        losetupOutput = losetupProc.communicate()[0]

        if losetupProc.returncode:
            raise MountError("Failed to allocate loop device for '%s'" %
                             self.lofile)

        self.loopdev = losetupOutput.split()[0]

        args = ['losetup', self.loopdev, self.lofile]
        if not ops:
            ops = self.ops
        if '-r' in ops or 'ro' in ops:
            args += ['-r']
        if '--direct-io' in ops:
            args.insert(1, '--direct-io')
        rc = call(args)
        if rc != 0:
            raise MountError("Failed to allocate loop device for '%s'" %
                             self.lofile)

        self.losetup = True

    def mount(self, ops=[], dirmode=None):
        self.diskmount.mount(ops, dirmode)


class SparseLoopbackMount(LoopbackMount):
    """SparseLoopbackMount  compatibility layer for old API"""
    def __init__(self, lofile, mountdir, size, fstype=None, ops=[],
                 dirmode=None):
        self.diskmount = DiskMount(SparseLoopbackDisk(lofile, size), mountdir,
                                   fstype, rmmountdir=True, ops=ops,
                                   dirmode=dirmode)

    def expand(self, create=False, size=None):
        self.diskmount.disk.expand(create, size)

    def truncate(self, size=None):
        self.diskmount.disk.truncate(size)

    def create(self):
        self.diskmount.disk.create()


class SparseExtLoopbackMount(SparseLoopbackMount):
    """SparseExtLoopbackMount  compatibility layer for old API"""
    def __init__(self, lofile, mountdir, size, fstype, blocksize, fslabel,
                 ops=[], dirmode=None):
        self.diskmount = ExtDiskMount(SparseLoopbackDisk(lofile,size),
                                      mountdir, fstype, blocksize, fslabel,
                                      rmmountdir=True, ops=ops,
                                      dirmode=dirmode)

    def __format_filesystem(self):
        self.diskmount.__format_filesystem()

    def create(self):
        self.diskmount.disk.create()

    def resize(self, size=None):
        return self.diskmount.__resize_filesystem(size)

    def mount(self, ops='', dirmode=None):
        self.diskmount.mount(ops, dirmode)

    def __fsck(self):
        self.extdiskmount.__fsck()

    def __get_size_from_filesystem(self):
        return self.diskmount.__get_size_from_filesystem()

    def __resize_to_minimal(self, ops=None):
        return self.diskmount.__resize_to_minimal(ops=ops)

    def resparse(self, size=None, ops=None):
        return self.diskmount.resparse(size, ops=ops)


class Disk:
    """Generic base object for a disk

    The 'create' method must make the disk visible as a block device - eg
    by calling losetup. For RawDisk, this is obviously a no-op. The 'cleanup'
    method must undo the 'create' operation.
    """
    def __init__(self, size, device=None):
        self._device = device
        self._size = size

    def create(self, ops=[]):
        pass

    def cleanup(self):
        pass

    def get_device(self):
        return self._device

    def set_device(self, path):
        self._device = path

    device = property(get_device, set_device)

    def get_size(self):
        return self._size

    size = property(get_size)


class RawDisk(Disk):
    """A Disk backed by a block device.
    Note that create() is a no-op.
    """
    def __init__(self, size, device):
        Disk.__init__(self, size, device)

    def fixed(self):
        return True

    def exists(self):
        return True


class LoopbackDisk(Disk):
    """A Disk backed by a file via the loop module."""
    def __init__(self, lofile, size, ops=[], dirmode=None):
        Disk.__init__(self, size)
        self.lofile = lofile
        self.ops = ops
        self.dirmode = dirmode

    def fixed(self):
        return False

    def exists(self):
        return os.path.exists(self.lofile)

    def create(self, ops=[]):
        if self.device is not None:
            return

        losetupProc = subprocess.Popen(['losetup', '-f'],
                                       stdout=subprocess.PIPE)
        losetupOutput = losetupProc.communicate()[0]

        if losetupProc.returncode:
            raise MountError("Failed to allocate loop device for '%s'" %
                             self.lofile)

        device = losetupOutput.split()[0].decode('utf_8')
        args = ['losetup', device, self.lofile]
        if not ops:
            ops = self.ops
        if '--direct-io' in ops:
            args.insert(1, '--direct-io')
        if '-r' in ops or 'ro' in ops:
            args += ['-r']

        logging.info("Losetup add %s mapping to %s"  % (device, self.lofile))
        rc = call(args)
        if rc != 0:
            raise MountError("Failed to allocate loop device for '%s'" %
                             self.lofile)
        self.device = device

    def cleanup(self):
        if self.device is None:
            return
        logging.info("Losetup remove %s" % self.device)
        rc = call(['losetup', '-d', self.device])
        self.device = None


class SparseLoopbackDisk(LoopbackDisk):
    """A Disk backed by a sparse file via the loop module."""
    def __init__(self, lofile, size, ops=[], dirmode=None):
        LoopbackDisk.__init__(self, lofile, size, ops=ops, dirmode=dirmode)

    def expand(self, create=False, size=None, dirmode=None):
        flags = os.O_WRONLY
        if create:
            flags |= os.O_CREAT
            if dirmode is None:
                dirmode = self.dirmode
            makedirs(os.path.dirname(self.lofile), dirmode)

        if size is None:
            size = self.size

        logging.info("Extending sparse file %s to %d" % (self.lofile, size))
        fd = os.open(self.lofile, flags)

        if size <= 0:
            size = 1
        os.lseek(fd, size-1, 0)
        os.write(fd, b'\x00')
        os.close(fd)

    def truncate(self, size=None):
        if size is None:
            size = self.size

        logging.info("Truncating sparse file %s to %d" % (self.lofile, size))
        fd = os.open(self.lofile, os.O_WRONLY)
        os.ftruncate(fd, size)
        os.close(fd)

    def create(self, ops=[], dirmode=None):
        self.expand(create=True, dirmode=dirmode)
        LoopbackDisk.create(self, ops=ops)


class ExistingSparseLoopbackDisk(SparseLoopbackDisk):
    """Don't expand the disk on creation."""

    def __init__(self, lofile, size, ops=[], dirmode=None):
        SparseLoopbackDisk.__init__(self, lofile, size, ops=ops,
                                    dirmode=dirmode)

    def create(self, ops=[], dirmode=None):
        LoopbackDisk.create(self, ops=ops)


class Mount:
    """A generic base class to deal with mounting things."""
    def __init__(self, mountdir):
        self.mountdir = mountdir

    def cleanup(self):
        self.unmount()

    def mount(self):
        pass

    def unmount(self):
        pass


class DiskMount(Mount):
    """A Mount object that handles mounting of a Disk."""
    def __init__(self, disk, mountdir, fstype=None, rmmountdir=True, ops='',
                 dirmode=None):
        Mount.__init__(self, mountdir)

        self.disk = disk
        self.fstype = fstype
        self.ops = ops
        self.dirmode = dirmode
        self.rmmountdir = rmmountdir

        self.mounted = False
        self.rmdir   = False
        self.created = False

    def cleanup(self):
        Mount.cleanup(self)
        self.mounted = False
        self.disk.cleanup()
        self.created = False

    def unmount(self):
        if self.mounted:
            logging.info("Unmounting directory %s" % self.mountdir)
            rc = call(['umount', self.mountdir])
            if rc == 0:
                self.mounted = False
            else:
                logging.warn("Unmounting directory %s failed, using lazy "
                             "umount" % self.mountdir)
                print("Unmounting directory %s failed, using lazy umount" %
                      self.mountdir, file=sys.stdout)
                rc = call(['umount', '-l', self.mountdir])
                if rc != 0:
                    raise MountError("Unable to unmount filesystem at %s" %
                                     self.mountdir)
                else:
                    logging.info("lazy umount succeeded on %s" % self.mountdir)
                    print("lazy umount succeeded on %s" % self.mountdir,
                          file=sys.stdout)
                    self.mounted = False

        if self.rmdir and not self.mounted:
            try:
                os.rmdir(self.mountdir)
            except OSError as e:
                pass
            self.rmdir = False

    def __create(self, ops=''):
        if not self.created:
            self.disk.create(ops=ops)
            self.created = True

    def mount(self, ops='', dirmode=None):
        if self.mounted:
            return

        if not os.path.isdir(self.mountdir):
            if dirmode is None:
                dirmode = self.dirmode
            dirmode = dirmode or 0o777
            logging.info("Creating mount point %s" % self.mountdir)
            os.makedirs(self.mountdir, dirmode)
            self.rmdir = self.rmmountdir

        self.__create(ops=ops)

        logging.info("Mounting %s at %s" % (self.disk.device, self.mountdir))
        args = ['mount', self.disk.device, self.mountdir]
        if self.fstype:
            args.extend(['-t', self.fstype])
        if self.fstype == 'squashfs' and 'ro' not in ops:
            ops += ',ro'
        if not ops:
            ops = self.ops
        if isinstance(ops, list) and ('-r' in ops or 'ro' in ops):
            args.extend(['-o', 'ro'])
        else: 
            args.extend(['-o', ops])

        rc = call(args)
        if rc != 0:
            raise MountError("Failed to mount '%s' to '%s'" %
                             (self.disk.device, self.mountdir))

        self.mounted = True

    def remount(self, ops):
        if not self.mounted:
            return

        remount_ops = ''.join(('remount,', ops))
        args = ['mount', '-o', remount_ops, self.mountdir]
        rc = call(args)
        if rc != 0:
            raise MountError("%s of '%s' to '%s' failed." %
                             (remount_ops, self.disk.device, self.mountdir))


class BindChrootMount():
    """Represents a bind mount of a directory into a chroot."""
    def __init__(self, src, chroot, dest=None, ops='', dirmode=None):
        self.src = src
        self.root = chroot
        self.ops = ops
        self.dirmode = dirmode

        if not dest:
            dest = src
        self.dest = self.root + '/' + dest
        self.mountdir = self.dest

        self.mounted = False

    def mount(self, ops='', dirmode=None):
        if self.mounted:
            return

        if dirmode is None:
            dirmode = self.dirmode
        makedirs(self.dest, dirmode)
        args = ['mount', '--bind', self.src, self.dest]
        rc = call(args)
        if rc != 0:
            raise MountError("Bind-mounting '%s' to '%s' failed" %
                             (self.src, self.dest))
        if not ops:
            ops = self.ops
        if '-r' in ops or 'ro' in ops:
            self.remount('ro')

        self.mounted = True

    def remount(self, ops):
        if not self.mounted:
            return

        remount_ops = ''.join(('remount,', ops))
        args = ['mount', '-o', remount_ops, self.dest]
        rc = call(args)
        if rc != 0:
            raise MountError("%s of '%s' to '%s' failed." %
                             (remount_ops, self.src, self.dest))

    def unmount(self):
        if not self.mounted:
            return

        rc = call(['umount', self.dest])
        if rc != 0:
            logging.info("Unable to unmount %s normally, using lazy unmount" %
                         self.dest)
            rc = call(['umount', '-l', self.dest])
            if rc != 0:
                raise MountError("Unable to unmount fs at %s" % self.dest)
            else:
                logging.info("lazy umount succeeded on %s" % self.dest)
                print("lazy umount succeeded on %s" % self.dest,
                      file=sys.stdout)
 
        self.mounted = False

    def cleanup(self):
        self.unmount()


class ExtDiskMount(DiskMount):
    """A DiskMount object that can format/resize ext[234] filesystems."""
    def __init__(self, disk, mountdir, fstype, blocksize, fslabel,
                 rmmountdir=True, ops='', dirmode=None):
        DiskMount.__init__(self, disk, mountdir, fstype, rmmountdir, ops=ops,
                           dirmode=dirmode)
        self.blocksize = blocksize
        self.fslabel = '_' + fslabel
        self.created = False

    def __format_filesystem(self):
        logging.info("Formating %s filesystem on %s" % (self.fstype,
                                                        self.disk.device))
        call(['wipefs', '-a', self.disk.device])
        args = ['mkfs.' + self.fstype]
        if self.fstype.startswith('ext'):
            args = args + ['-F', '-L', self.fslabel, '-m', '1', '-b',
                           str(self.blocksize)]
        elif self.fstype == 'xfs':
            args = args + ['-L', self.fslabel[0:10], '-b', 'size=%s' %
                           str(self.blocksize)]
        elif self.fstype == 'btrfs':
            args = args + ['-L', self.fslabel]
        args = args + [self.disk.device]
        logging.info("Formating args: %s" % args)
        rc = call(args)

        if rc != 0:
            raise MountError("Error creating %s filesystem" % (self.fstype,))
        if self.fstype.startswith('ext'):
            logging.info('Tuning filesystem on %s' % self.disk.device)
            call(['tune2fs', '-c0', '-i0', '-Odir_index',
                  '-ouser_xattr,acl', self.disk.device])

    def __resize_filesystem(self, size=None, ops=''):
        current_size = os.stat(self.disk.lofile)[stat.ST_SIZE]

        if size is None:
            size = self.disk.size

        if size == current_size:
            return

        if size > current_size:
            self.disk.expand(size=size)

        if self.fstype.startswith('ext'):
            resize2fs(self.disk.lofile, size, ops=ops)
        elif size < current_size:
            self.disk.truncate(size=size)
        return size

    def __create(self, ops=''):
        if self.created:
            return
        resize = False
        if not self.disk.fixed() and self.disk.exists():
            resize = True

        self.disk.create(ops=ops)

        if resize:
            self.__resize_filesystem(ops=ops)
        elif ops != 'raw':
            self.__format_filesystem()

        self.created = True

    def mount(self, ops='', dirmode=None):
        self.__create(ops)
        DiskMount.mount(self, ops, dirmode)

    def __fsck(self):
        return e2fsck(self.disk.lofile)
        return rc

    def __get_size_from_filesystem(self):
        def parse_field(output, field):
            for line in output.split(b'\n'):
                if line.startswith(field.encode('utf_8') + b':'):
                    return line[len(field) + 1:].strip()

            raise KeyError("Failed to find field '%s' in output" % field)

        dev_null = os.open('/dev/null', os.O_WRONLY)
        try:
            out = subprocess.Popen(['dumpe2fs', '-h', self.disk.lofile],
                                   stdout=subprocess.PIPE,
                                   stderr=dev_null).communicate()[0]
        finally:
            os.close(dev_null)

        return int(parse_field(out, "Block count")) * self.blocksize

    def __resize_to_minimal(self, ops=''):
        resize2fs(self.disk.lofile, minimal=True, ops=ops)
        return self.__get_size_from_filesystem()

    def resparse(self, size=None, ops=None):
        self.cleanup()
        minsize = self.__resize_to_minimal(ops=ops)
        self.disk.truncate(minsize)
        self.__resize_filesystem(size, ops=ops)
        return minsize


class DeviceMapperSnapshot(object):
    def __init__(self, imgloop, cowloop, ops=[]):
        self.imgloop = imgloop
        self.cowloop = cowloop
        self.persistent = 'PO'

        self.__created = False
        self.__name = None

    def get_path(self):
        if self.__name is None:
            return None
        return os.path.join('/dev/mapper', self.__name)
    path = property(get_path)

    def create(self, ops=[]):
        if self.__created:
            return

        self.imgloop.create(ops=ops)
        self.cowloop.create(ops=ops)

        self.DeviceMapperTarget__name = self.__name = 'imgcreate-%d-%d' % (
            os.getpid(), random.randint(0, 2**16))

        size = os.stat(self.imgloop.lofile)[stat.ST_SIZE]

        if '--readonly' in ops or '-r' in ops or 'ro' in ops:
            self.persistent = 'P'
        if 'tmpfs' == rcall(['df', '--output=fstype',
                             self.cowloop.lofile])[0].split()[1] or 'N' in ops:
            self.persistent = 'N'
        if 'P' in ops:
            self.persistent = 'P'
        if 'PO' in ops:
            self.persistent = 'PO'

        table = '0 %d snapshot %s %s %s 8' % (size // 512,
                                              self.imgloop.device,
                                              self.cowloop.device,
                                              self.persistent)

        args = ['dmsetup', 'create', self.__name, '-vv', '--verifyudev',
                '--uuid', 'LIVECD-%s' % self.__name, '--table', table]

        if '--readonly' in ops or '-r' in ops or 'ro' in ops:
            args += ['--readonly']
        if call(args) != 0:
            time.sleep(1)
            self.cowloop.cleanup()
            self.imgloop.cleanup()
            raise SnapshotError('Could not create snapshot device using: ' +
                                ' '.join(args))

        self.__created = True
        self.device = os.path.join('/dev/mapper', self.__name)

    def remove(self, ignore_errors=False):
        if not self.__created:
            return

        # sleep to try to avoid any dm shenanigans
        time.sleep(2)
        rc = call(['dmsetup', 'remove', self.__name])
        if not ignore_errors and rc != 0:
            raise SnapshotError('Could not remove snapshot device.')

        self.DeviceMapperTarget__name = self.__name = None
        self.__created = False

        self.cowloop.cleanup()
        self.imgloop.cleanup()

    def cleanup(self):
        self.remove()

    def get_cow_used(self):
        if not self.__created:
            return 0

        dev_null = os.open('/dev/null', os.O_WRONLY)
        try:
            out = subprocess.Popen(['dmsetup', 'status', self.__name],
                                   stdout=subprocess.PIPE,
                                   stderr=dev_null).communicate()[0]
        finally:
            os.close(dev_null)

        # dmsetup status on a snapshot returns, e.g.,
        #   "0 8388608 snapshot 416/1048576 260"
        # following the pattern:
        #   "A B snapshot C/D E"
        # where C is the number of 512 byte sectors allocated
        #  from D          "        "   "     "     in the overlay
        #   and E          "        "   "     "     of metadata
        #       A is the start sector of the filesystem
        #       B        size of the filesystem in 512 byte sectors.
        try:
            return int((out.split()[3]).split(b'/')[0]) * 512
        except ValueError:
            raise SnapshotError("Failed to parse dmsetup status: " + out)


def create_image_minimizer(path, image, compress_type, target_size=None):
    """
    Builds a copy-on-write image which can be used to
    create a device-mapper snapshot of an image where
    the image's filesystem is as small as possible

    The steps taken are:
      1) Create a sparse COW
      2) Loopback mount the image and the COW
      3) Create a device-mapper snapshot of the image
         using the COW
      4) Resize the filesystem to the minimal size
      5) Determine the amount of space used in the COW
      6) Restroy the device-mapper snapshot
      7) Truncate the COW, removing unused space
      8) Create a squashfs of the COW
    """
    imgloop = LoopbackDisk(image, None) # Passing bogus size - doesn't matter

    cowloop = SparseLoopbackDisk(os.path.join(os.path.dirname(path), "osmin"),
                                 64 * 1024 * 1024)

    snapshot = DeviceMapperSnapshot(imgloop, cowloop)

    try:
        snapshot.create()

        if target_size is not None:
            resize2fs(snapshot.path, target_size)
        else:
            resize2fs(snapshot.path, minimal=True)

        cow_used = snapshot.get_cow_used()
    finally:
        snapshot.remove(ignore_errors = (not sys.exc_info()[0] is None))

    cowloop.truncate(cow_used)

    mksquashfs(cowloop.lofile, path, compress_type)

    os.unlink(cowloop.lofile)

