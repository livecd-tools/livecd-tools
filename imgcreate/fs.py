# coding: utf-8
#
# fs.py : Filesystem related utilities and classes
#
# Copyright 2007, Red Hat, Inc.
# Copyright 2016, Neal Gompa
# Copyright 2017, Sugar Labs®
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
import shutil
import subprocess
import random
import string
import logging
import tempfile
import time

from imgcreate.util import *
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
                (args, err.decode('utf-8'), p.returncode))
        else:
            compress_type = 'undetermined'
            for l in out.splitlines():
                if l.split(None, 1)[0] == b'Compression':
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
        args.append('-no-progress')

    if ops == 'show-squashing':
        p = subprocess.Popen(args, stdout=None, stderr=subprocess.STDOUT)
        p.wait()
        ret = p.returncode
    else:
        ret = call(args)

    if ret != 0:
        raise SquashfsError("'%s' exited with error (%d)" %
                            (' '.join(args), ret))

def resize2fs(fs, size=None, minimal=False, ops=''):
    if minimal and size is not None:
        raise ResizeError("Can't specify both minimal and a size for resize!")

    args = ['resize2fs', '-p', fs]
    if ops == 'nocheck':
        args.append('-f')
    else:
        e2fsck(fs)

    logging.info('resizing %s' % (fs,))
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

def get_dm_table(device):
    """Return the table for a Device-mapper device."""

    table = None
    table = rcall(['dmsetup', 'table', device])[0].rstrip()
    return table

def disc_free_info(path, options=None):
    """Return the disc free information for a file or device path."""

    info = [''] * 7
    if os.path.exists(path):
        st_mode = os.stat(path).st_mode
        if stat.S_ISBLK(st_mode) or os.path.ismount(path) or stat.S_ISDIR(
                                                                      st_mode):
            df_args = ['df']
            if options:
                df_args += [options]
            df_args += [path]
            devinfo = rcall(df_args)[0].splitlines()
            info = devinfo[1].split(None)
            if len(info) == 1:
                info += [devinfo[2].split(None)]
    return info

def get_file_info(path):
    """Retrieve brief file information.  (A minimal implementation.)"""

    info = [None] * 16
    if os.path.exists(path):
        info = rcall(['file', '-b', path])[0].split()
    return info

def findmnt(ops=None, search=[]):
    """Return output from the findmnt command of the util-linux package."""

    args = ['findmnt']
    if ops:
        ops = ops.split()
        args += ops
    if search:
        args += [search]
    return rcall(args)[0].strip()

def lsblk(ops=None, search=[]):
    """Use command lsblk from the util-linux package."""

    args = ['lsblk']
    if ops:
        ops = ops.split()
        args += ops
    if search:
        args += [search]
    return rcall(args)[0].strip()

def losetup(ops=None, search=[]):
    """Use command losetup from the util-linux package."""

    args = ['losetup']
    if ops:
        ops = ops.split()
        args += ops
    if search:
        args += [search]
    return rcall(args)[0].strip()

def get_blockdev(major_minor):
    """Return a block device node name from the devtmpfs."""

    try:
        dev = os.path.join('/dev', os.path.basename((os.readlink(os.path.join(
                           '/dev', 'block', major_minor)))))
    except OSError:
        dev = None
    finally:
        return dev

def get_blockdev_size(device):
    """Return the device size in bytes."""

    return rcall(['blockdev', '-q', '--getsize64', device])[0].rstrip()

def unmount_all(device):
    """Attempt to unmount a block device."""

    # Include loop attachments to device.
    devs = losetup('-nO NAME -j', device).split()
    for d in devs:
        dd = losetup('-nO NAME -j', d).split()
        for _d in dd:
            devs.append(dd.pop(0))
            dd += losetup('-nO NAME -j', _d).split()
    else:
        devs.append(device)

    # decode for spaces & other special characters in mount point.
    with open('/proc/self/mountinfo', 'rb') as mounts:
        mdevs = [[i[0].decode('unicode_escape'), i[5].decode('unicode_escape')]
                for i in [m.split(b' ')[4:] for m in mounts]
                    if i[5].decode('unicode_escape') in devs]

    # Order last-mounted first.
    mdevs.reverse()
    ret = None
    for m in mdevs:
        out, err, rc = rcall(['umount', '-lR', m[0]])
        if err:
            print('umount error: %s :: %s' % (out, err))
            return False
        else:
            print('Unmounted %s at %s' % (m[1], m[0]))
            ret = True
    return ret

def find_overlay(liveosdir):
    """Return the path to a LiveOS overlay file."""

    result = None
    for f in os.listdir(liveosdir):
        if f.find('overlay-') == 0:
            result = os.path.join(liveosdir, f)
            break
    return result

def unavailable_space(filesystem):
    """Return the space held in unlinked but locked files in filesystem."""

    out, err, rc = rcall(['lsof', '+aL1', '-Fs', filesystem])
    print(err)
    size = 0
    for v in out.split():
        if v[0] == 's':
            size += int(v[1:])
    return size

def dm_nodes():
    """Return list of Device-mapper node names."""

    return rcall(['dmsetup', 'info', '-c', '--noheadings',
                  '-o', 'name'])[0].split()

def config_mirror_targets(src_fs, tmpdir='/tmp', legs=2, ops=None):
    """Configure filesystems for mirror targets."""

    mirroot = tempfile.mkdtemp(prefix='mir-', dir=tmpdir)
    mirname = os.path.basename(mirroot)
    imgdev = None
    dm_node = None
    loopobj = None
    if src_fs in dm_nodes():
        table = get_dm_table(src_fs)
        dm_table_list = table.split()
        m_m = dm_table_list[3]
        imgsize = int(dm_table_list[1]) * 512
        imgdev = get_blockdev(m_m)
        dm_node = src_fs, table
    elif os.path.isfile(src_fs):
        imgsize = os.stat(src_fs).st_size
        imgdev = losetup('-nO NAME -j', src_fs)
    else:
        # src_fs is a block device.
        imgsize = int(get_blockdev_size(src_fs))
        if not findmnt('-no TARGET', src_fs):
            imgdev = src_fs
    if imgdev is None:
        loopobj = LoopbackDisk(src_fs, None, '-r', 0o700)
        loopobj.create()
        imgdev = loopobj.device

    fslabel = lsblk('-ndo LABEL', imgdev)
    fstype = lsblk('-ndo FSTYPE', imgdev)
    blocksize = os.stat(imgdev).st_blksize

    def _create_target_object(i):
        leg = os.path.join(tmpdir, ''.join((mirname, str(i), '.img')))
        try:
            if not ops:
                return ExtDiskMount(SparseLoopbackDisk(leg, imgsize),
                                    mirroot, fstype, blocksize, fslabel)
            elif ops == 'encrypt':
                # Note: Assumes a fixed offset.
                return DiskMount(CryptoLUKSDevice('EncHome' + mirname + str(i),
                                          leg, imgsize + 4096*512, ops='raw'),
                                 tempfile.mkdtemp(dir=mirroot), dirmode=0o700)
        except:
            raise MountError("Failed to allocate device for '%s'" % leg)

    target_objs = [_create_target_object(i) for i in range(legs - 1)]

    imgsize //= 512
    return imgdev, dm_node, imgsize, target_objs, mirname, loopobj

def mirror_fs(fs_dev, dm_node, imgsize, mirloops, mirname):
    """Use Device Mapper to mirror a registered filesystem or block device to
    a pre-configured extensible disk mount or a cryptoLUKS code object."""

    dmsetup_cmd = ['dmsetup']
    if '--noudevsync' in rcall(['dmsetup', '-h'])[1]:
        dmsetup_cmd = ['dmsetup', '--noudevrules', '--noudevsync']

    # Create target loop filesystems.
    if isinstance(mirloops[0].disk, CryptoLUKSDevice):
        [obj.disk.create() for obj in mirloops]

    else:
        [obj._ExtDiskMount__create(ops='raw') for obj in mirloops]
    tgtloops = [''.join((' ', obj.disk.device, ' 0')) for obj in mirloops]

    device = fs_dev
    logging.info('creating vfs %s' % (mirname,))

    if dm_node:
        device = os.path.join('/dev', 'mapper', dm_node[0])

    mirror = ''.join(('0 %s mirror core 2 32 sync %s %s 0' % (str(imgsize),
                       str(len(mirloops) + 1), device), ''.join(tgtloops)))

    # Loading mirror configuration.
    logging.info('loading mirror %s to %s' % (device, repr(tgtloops)))

    call(dmsetup_cmd + ['create', mirname, '--readonly', '--table', mirror])
    time.sleep(2)

    print('  Copying filesystem %s to %s.' % (device, mirname))
    while 'waiting':
        num, denom = rcall(['dmsetup', 'status', mirname]
                           )[0].split()[-5].split('/')
        if num == denom: break
        percent = 100.0 * int(num) / int(denom)
        print('\r  Mirroring  {0:4.1f} % complete. '.format(percent),
              '\b|\b', end='')
        sys.stdout.flush()
        time.sleep(.5)
        print('/\b', end='')
        sys.stdout.flush()
        time.sleep(.5)
        print('-\b', end='')
        sys.stdout.flush()
        time.sleep(.5)
        print('\\\b', end='')
        sys.stdout.flush()
        time.sleep(.5)
    print('\r  Mirroring 100 % complete.   ')
    sys.stdout.flush()


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

    def mount(self, ops='', dirmode=None):
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

    def __resize_to_minimal(self, ops=''):
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

        device = losetupOutput.split()[0].decode('utf-8')
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
                logging.warning("Unmounting directory %s failed, using lazy "
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
        elif ops: 
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


class OverlayFSMount(Mount):
    """An OverlayFS mount that can modify its overlay."""
    def __init__(self, name, lower, upper=None, work=None, dest=None,
                 size=None, fstype=None, blksz=None, ops='', dirmode=None):
        self.name = name
        self.lower = lower  # A LoopbackDisk object
        self.upper = upper  # A       "        "    or a path to the overlay
        self.work = work
        self.cowmnt = None
        self.ops = ops
        self.dirmode = dirmode
        self.mountdir = dest

        self.mounted = False

        if isinstance(self.upper, str):
            if os.path.isdir(self.upper):
                self.upper = ''.join((',upperdir=', self.upper))
                self.work = ''.join((',workdir=', self.work))
            else:
                self.cowloop = SparseLoopbackDisk(self.upper, size)
                self.upper = self.cowloop
        if isinstance(self.upper, LoopbackDisk):
            mntdir = tempfile.mkdtemp('', 'cow-', '/run')
            self.cowloop = self.upper
            self.cowmnt = DiskMount(self.cowloop, mntdir, ops=ops,
                                    dirmode=dirmode)
            self.upper = ''.join((',upperdir=',
                                  os.path.join(mntdir, 'overlayfs')))
            self.work = ''.join((',workdir=',
                                 os.path.join(mntdir, 'ovlwork')))

        mntdir = tempfile.mkdtemp('', 'img-', '/run')
        self.imgmnt = DiskMount(self.lower, mntdir, ops=ops, dirmode=dirmode)
        self.lower = ''.join(('lowerdir=', mntdir))

    def recreate_overlay(self, fstype, blksz, label, ops=None, dirmode=None):
        if self.cowmnt.disk.device:
            self.cowmnt.cleanup()
        self.cowmnt = ExtDiskMount(self.cowloop, self.cowmnt.mountdir, fstype,
                                   blksz, 'overlay', ops=ops, dirmode=0o755)
        self.cowmnt._ExtDiskMount__create()
        self.cowmnt._ExtDiskMount__format_filesystem()
        self.cowmnt.mount()
        d = os.path.join(self.cowmnt.mountdir, 'overlayfs')
        makedirs(d)
        makedirs(os.path.join(self.cowmnt.mountdir, 'ovlwork'))
        args = ['chcon', '--reference=/', d]
        rc = call(args)
        if rc != 0:
            raise MountError("OverlayFS mount:  '%s' failed" % args)
        
        self.cowmnt.cleanup()

    def mount(self, name=None, ops='', dirmode=None):
        if self.mounted:
            return

        if not ops:
            ops = self.ops
        if '-r' in ops or 'ro' in ops:
            lower = ''.join((self.upper.replace('upperdir', 'lowerdir'),
                                  ':', self.lower.replace('lowerdir=', '')))
            upper = ''
            work = ''
        else:
            lower = self.lower
            upper = self.upper
            work = self.work
        if dirmode is None:
            dirmode = self.dirmode
        makedirs(self.mountdir, dirmode)
        if name is None:
            name = self.name
        self.imgmnt.mount(ops='ro', dirmode=dirmode)
        if self.cowmnt:
            self.cowmnt.mount(ops=ops, dirmode=dirmode)
        args = ['mount', '-t', 'overlay', name, ''.join(('-o', ops, ',',
                lower, upper, work)), self.mountdir]
        rc = call(args)
        if rc != 0:
            raise MountError("OverlayFS mount:  '%s' failed" % args)

        self.mounted = True

    def unmount(self):
        if not self.mounted:
            return

        rc = call(['umount', self.mountdir])
        if rc != 0:
            logging.info("Unable to unmount %s normally, using lazy unmount" %
                         self.mountdir)
            rc = call(['umount', '-l', self.mountdir])
            if rc != 0:
                raise MountError("Unable to unmount fs at %s" % self.mountdir)
            else:
                logging.info("lazy umount succeeded on %s" % self.mountdir)
                print("lazy umount succeeded on '%s'" % (self.mountdir),
                      sys.stdout)
        if self.cowmnt:
            self.cowmnt.unmount()
        self.imgmnt.unmount()
 
        self.mounted = False

    def cleanup(self):
        self.unmount()
        self.imgmnt.cleanup()
        self.mounted = False
        if self.cowmnt:
            self.cowmnt.cleanup()
        self.created = False


class BindChrootMount():
    """Represents a bind mount of a directory into a chroot."""
    def __init__(self, src, chroot, dest=None, ops='', dirmode=None):
        self.src = src
        self.root = chroot
        self.ops = ops
        self.dirmode = dirmode

        if not dest:
            dest = src
        self.dest = os.path.join(self.root, dest.lstrip('/'))
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
        if not self.mounted or not os.path.ismount(self.dest):
            self.mounted = False
            return

        remount_ops = ''.join(('remount,', ops))
        args = ['mount', '-o', remount_ops, self.dest]
        rc = call(args)
        if rc != 0:
            raise MountError("%s of '%s' to '%s' failed." %
                             (remount_ops, self.src, self.dest))

    def unmount(self):
        if not self.mounted or not os.path.ismount(self.dest):
            self.mounted = False
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
                if line.startswith(field):
                    return line[len(field):].strip()

            raise KeyError("Failed to find field '%s' in output" % field)

        dev_null = os.open('/dev/null', os.O_WRONLY)
        try:
            out = subprocess.Popen(['dumpe2fs', '-h', self.disk.lofile],
                                   stdout=subprocess.PIPE,
                                   stderr=dev_null).communicate()[0]
        finally:
            os.close(dev_null)

        return int(parse_field(out, b'Block count:')) * self.blocksize

    def __resize_to_minimal(self, ops=''):
        resize2fs(self.disk.lofile, minimal=True, ops=ops)
        return self.__get_size_from_filesystem()

    def resparse(self, size=None, ops=None):
        self.cleanup()
        minsize = self.__resize_to_minimal(ops=ops)
        self.disk.truncate(minsize)
        self.__resize_filesystem(size, ops=ops)
        return minsize


class DeviceMapperLinear(object):
    def __init__(self, imgloop, ops=[]):
        self.imgloop = imgloop    # A LoopbackDisk object
        self.ops = ops

        self.__created = False
        self.__name = None

    def get_path(self):
        if self.__name is None:
            return None
        return self.device
        return os.path.join('/dev/mapper', self.__name)
    path = property(get_path)

    def create(self, ops=[]):
        if self.__created:
            return
        ops += ['--direct-io']
        self.imgloop.create(ops)

        self.DeviceMapperTarget__name = self.__name = 'imgcreate-%d-%d' % (
            os.getpid(), random.randint(0, 2**16))

        size = os.stat(self.imgloop.lofile)[stat.ST_SIZE]

        table = '0 %d linear %s 0' % (size // 512, self.imgloop.device)

        args = ['dmsetup', 'create', self.__name, '-vv', '--verifyudev',
                '--uuid', 'LIVECD-%s' % self.__name, '--table', table]

        if not ops:
            ops = self.ops
        if '--readonly' in ops or '-r' in ops or 'ro' in ops:
            args += ['--readonly']

        if call(args) != 0:
            time.sleep(1)
            self.imgloop.cleanup()
            raise SnapshotError('Could not create snapshot device using: ' +
                                ' '.join(args))
        self.__created = True
        self.device = os.path.join('/dev/mapper', self.__name)

    def cleanup(self):
        self.remove()

    def remove(self, ignore_errors = False):
        if not self.__created:
            return

        # sleep to try to avoid any dm shenanigans
        time.sleep(2)
        rc = call(['dmsetup', 'remove', self.__name])
        if not ignore_errors and rc != 0:
            raise SnapshotError('Could not remove dm-linear device.')

        self.DeviceMapperTarget__name = self.__name = None
        self.__created = False

        self.imgloop.cleanup()


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
        if ('tmpfs' == findmnt('-no FSTYPE -T', self.cowloop.lofile)
            or 'N' in ops):
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
            raise SnapshotError('Failed to parse dmsetup status: ' + out)


class CryptoLUKSDevice(object):
    def __init__(self, name, source, size=0, fstype=None, blksz=None,
                 ops=''):
        self.ops = ops
        self.size = str( size // (1024 ** 2))
        self.fstype = fstype
        self.blksz = blksz
        self.__created = False
        self.__name = name
        self.__backed = False
        self.__formatted = False
        self.device = None
        self.lofile = source
        if self.ops == 'raw':
            self.__formatted = True
        if call(['cryptsetup', 'isLuks', source]) == 0:
            self.__backed = True
            self.__formatted = True

    def get_path(self):
        if self.__name is None:
            return None
        return self.device
        return os.path.join('/dev/mapper', self.__name)
    path = property(get_path)

    def __get_offset_and_size(self):
        def parse_field(output, field):
            for line in output.split('\n'):
                if line.startswith(field):
                    return int(line.split()[1])

            raise CryptoLUKSError("Failed to find field '%s' in output." %
                                  field)

        args = ['cryptsetup', 'status', self.__name]
        info, err, rc = rcall(args)
        if err:
            raise CryptoLUKSError(''.join((
                  'Could not read the status of crypto_LUKS device using:\n  ',
                  args)))

        return (parse_field(info, '  offset:'), parse_field(info, '  size:'))

    def __resize_filesystem(self, size=None, ops=''):
        self.backing_obj = ExistingSparseLoopbackDisk(self.lofile, size)
        current_size = os.stat(self.lofile)[stat.ST_SIZE]

        if size is None:
            size = int(self.size) * 1024 ** 2

        if size == current_size:
            return

        args = ['cryptsetup', 'resize', self.__name,]
        if size > current_size:
            self.backing_obj.expand(size=size)
            self.create(ops=ops)
            if call(args) != 0:
                raise CryptoLUKSError(''.join((
                      'Could not resize the crypto_LUKS device using:\n  ',
                      args)))
            resize2fs(self.device, size=None, ops=ops)
            self.cleanup()
        else:
            self.create(ops=ops)
            resize2fs(self.device, size, ops=ops)
            args += ['--size', str(size // 512)]
            if call(args) != 0:
                raise CryptoLUKSError(''.join((
                      'Could not resize the crypto_LUKS device using:\n  ',
                      args)))
            current_size = self.__get_offset_and_size()
            truncate_size = (current_size[0] + current_size[1]) * 512
            self.cleanup()
            self.backing_obj.truncate(size=truncate_size)
        return size

    def back(self, ops=''):
        if self.__backed:
            return
        print('Preparing persistent home.img file.')
        if findmnt('-no FSTYPE', self.lofile) in ('vfat', 'msdos'):
            args = ['dd', 'if=/dev/urandom', 'of=' + self.lofile,
                    'count=' + self.size, 'bs=1M']
        else:
            args = ['dd', 'if=/dev/null', 'of=' + self.lofile, 'count=1',
                    'bs=1M', 'seek=' + self.size]
        if call(args) != 0:
            raise CryptoLUKSError(''.join((
                  'Could not create a crypto_LUKS backing file using:\n  ',
                  args)))
        print('Encrypting persistent home.img filesystem.')
        os.system('while ! cryptsetup luksFormat ' + self.lofile +
                  '; do :; done;')
        self.__backed = True
        print('Please enter the password again to unlock the device.')
        self.create(self.ops)
        self.format(self.ops)

    def format(self, ops=''):
        if not self.__backed:
            self.back(self.ops)
        if self.__formatted:
            return

    def __format_filesystem(self):
        logging.info('Formating %s filesystem on %s' % (self.fstype,
                                                        self.device))
        args = ['mkfs.' + self.fstype]
        if self.fstype.startswith("ext"):
            args = args + ['-F', '-b', str(self.blksz)]
        elif self.fstype == 'xfs':
            args = args + ['-b', 'size=%s' % str(self.blksz)]
        args = args + [self.device]
        logging.info('Formating args: %s' % args)
        if call(args) != 0:
            raise CryptoLUKSError(''.join(('Could not make an ', self.fstype,
                                  ' filesystem using:  ', args)))
        logging.info('Tuning filesystem on %s' % self.disk.device)
        call(['tune2fs', '-c0', '-i0', '-Odir_index',
              '-ouser_xattr,acl', self.disk.device])

        args = ['tune2fs', '-c0', '-i0', '-ouser_xattr,acl', self.device]
        logging.info("Tuning filesystem on %s" % self.device)
        if call(args) != 0:
            raise CryptoLUKSError(''.join(('Could not tune the ', self.fstype,
                                  ' filesystem using:  ', args)))
        time.sleep(2)
        self.__formatted = True

    def open(self, ops=''):
        args = ['cryptsetup', 'open', self.lofile, self.__name]
        if not ops:
            ops = self.ops
        if '--readonly' in ops or '-r' in ops or 'ro' in ops:
            args += ['--readonly']
        if call(args) != 0:
            time.sleep(1)
            raise CryptoLUKSError(''.join((
                  'Could not create a crypto_LUKS device using:  ', args)))

        self.device = os.path.join('/dev/mapper', self.__name)
        self.__created = True

    def create(self, ops=''):
        if not self.__backed:
            self.back(self.ops)
        if self.__created:
            return

        self.open(self.ops)

    def suspend(self):
        args = ['cryptsetup', 'luksSupend', self.__name]
        if call(args) != 0:
            time.sleep(1)
            raise CryptoLUKSError(''.join((
                  'Could not suspend a crypto_LUKS device using:  ', args)))

    def __close(self, ignore_errors=False):
        rc = call(['cryptsetup', 'close', self.__name])
        if not ignore_errors and rc != 0:
            raise CryptoLUKSError('Could not remove crypto_LUKS device.')

        self.device = None

    def cleanup(self, ignore_errors=False):
        if not self.__created:
            return

        self.__close()
        self.__created = False


class LiveImageMount(object):
    """
    A class for mounting a LiveOS image together with an active overlay.

    The source directory must be a mount point for a LiveOS-bearing .iso image,
    block device, or simply a directory path for a folder holding the files of
    a LiveOS image.
    """
    def __init__(self, srcdir, mountdir, ovloop=None, ops='', dirmode=None):
        self.srcdir = srcdir
        self.liveosdir = None
        self.mountdir = mountdir
        self.mounted = False
        self.imgloop = None
        self.overlay = ovloop     # file, directory, or loop_object
        self.ovltype = None
        self.cowloop = None
        self.ops = ops
        self.dirmode = dirmode
        self.__created = False
        self.squashmnt = None
        self.livemount = None
        self.dm_target = None
        self.homemnt = None
        self.EncHome = None

    def __create(self, ops=[], dirmode=None):
        if self.__created:
            return
        if not ops:
            ops = self.ops
        self.liveosdir = os.path.join(self.srcdir, 'LiveOS')
        if not os.path.isdir(self.liveosdir):
            self.liveosdir = self.srcdir
        sqfs_img = os.path.join(self.liveosdir, 'squashfs.img')
        if os.path.exists(sqfs_img):
            self.squashloop = LoopbackDisk(sqfs_img, None, ['-r'])

            self.squashmnt = DiskMount(self.squashloop, ''.join((self.mountdir,
                                       'sqmt')), ops='ro', dirmode=dirmode)
            self.squashmnt.mount('ro')
            rootfs_img = os.path.join(self.squashmnt.mountdir,
                                      'LiveOS', 'rootfs.img')
            if not os.path.exists(rootfs_img):
                rootfs_img = os.path.join(self.squashmnt.mountdir,
                                          'LiveOS', 'ext3fs.img')
            self.imgloop = LoopbackDisk(rootfs_img, None, ['-r'])
        else:
            rootfs_img = os.path.join(self.liveosdir, 'rootfs.img')
            if not os.path.exists(rootfs_img):
                rootfs_img = os.path.join(self.liveosdir, 'ext3fs.img')
            if not os.path.exists(rootfs_img):
                raise SnapshotError('Failed to find a LiveOS root image.')
            self.imgloop = LoopbackDisk(rootfs_img, None)
        if self.overlay is None:
            self.overlay = find_overlay(self.liveosdir)
            if self.overlay:
                if os.path.isdir(self.overlay):
                    self.ovltype = 'dir'
                    cow = self.overlay
                    work = os.path.join(self.liveosdir, 'ovlwork')
                else:
                    cow = self.cowloop = LoopbackDisk(self.overlay, None,
                                                      ops=ops)
                    work = None
                    self.cowloop.create(['ro'])
                    call(['udevadm', 'settle'])
                    self.ovltype = lsblk('-ndo FSTYPE', self.cowloop.device)
                    self.cowloop.cleanup()
                if self.ovltype not in ('', 'DM_snapshot_cow', 'temp'):
                    self.livemount = OverlayFSMount(
                                     'overlayfs', self.imgloop, cow, work,
                                     self.mountdir, ops=ops, dirmode=dirmode)
        else:
            self.cowloop = self.overlay
        if not self.overlay:
            if self.squashmnt is None:
                # Uncompressed live rootfs
                self.dm_target = DeviceMapperLinear(self.imgloop, ops)
                self.ovltype = ''
            else:
                self.overlay = tempfile.NamedTemporaryFile(dir=self.mountdir,
                                                           delete=False).name
                self.overlay = self.cowloop = SparseLoopbackDisk(
                                                  self.overlay, 32 * 1024 ** 3)
                self.ovltype = 'temp'
        if not self.dm_target and self.ovltype in ('', 'DM_snapshot_cow',
                                                   'temp'):
            self.dm_target = DeviceMapperSnapshot(self.imgloop,
                                                  self.cowloop, ops=ops)
        if not self.livemount:
            self.livemount = DiskMount(self.dm_target, self.mountdir,
                                       ops=ops, dirmode=dirmode)
            self.livemount.rmdir = True
        home_img = os.path.join(self.liveosdir, 'home.img')
        if os.path.exists(home_img):
            homedir = os.path.join(self.mountdir, 'home')
            if call(['cryptsetup', 'isLuks', home_img]) == 0:
                self.EncHome = CryptoLUKSDevice('EncHome', home_img, ops=ops)
                self.homemnt = DiskMount(self.EncHome, homedir, ops=ops,
                                         dirmode=dirmode)
            else:
                self.homemnt = LoopbackMount(home_img, homedir, ops=ops,
                                             dirmode=dirmode)
        self.__created = True

    def make_overlay(self, size=512*1024**2, existing_size=0, ovl_fstype='',
                     ovl_blksz=None, ops=[], dirmode=None):
        """Register a new or modified LiveOS overlay."""

        device = findmnt('-no UUID,LABEL -T', self.srcdir)
        device = device.partition(' ')
        label = device[2].strip()
        if ovl_fstype != 'dir' and any(n in ' \t\n\r\f\v' for n in label):
            source = findmnt('-no SOURCE,FSTYPE -T', self.srcdir).split()
            print("\nALERT:\n      The filesystem label on '", source[0],
            "' contains spaces, tabs, newlines,\n      or other whitespace ",
            'that is incompatible with a LiveOS overlay.\n\nAttempting to ',
            'rename it with whitespace replaced by underscores...', sep='')
            label = label.translate(string.maketrans(' \t\n\r\f\v', '______'))
            self.unmount()
            if source[1] == 'vfat':
                args = ['fatlabel']
            elif source[1].startswith('ext'):
                args = ['e2label']
            elif source[1] == 'btrfs':
                args = ['btrfs', 'filesystem', 'label']
            args += [source[0], label]
            if call(args) != 0:
                print('ERROR:\nRelabel of', source[0], 'has failed.\n')

        overfile = os.path.join(self.liveosdir,
                                '-'.join(('overlay', label, device[0])))

        def _wipe_overlay(otype):
            self.unmount()
            if otype in ('', 'temp', 'DM_snapshot_cow'):
                call(['wipefs', '-a', self.livemount.disk.cowloop.device])
            elif otype == 'dir':
                shutil.rmtree(os.path.join(overfile, '..', 'ovlwork'))
                shutil.rmtree(overfile)
            else:
                call(['wipefs', '-a', self.livemount.cowloop.device])
            self.cleanup()
            
        if ovl_fstype == 'dir':
            call(['rm', '-rf', overfile])
            makedirs(overfile, 0o755)
            makedirs(os.path.join(overfile, '..', 'ovlwork'), 0o755)
        else:
            resize = True
            if ovl_fstype in ('', 'temp', 'DM_snapshot_cow'):
                if os.path.exists(overfile):
                    _wipe_overlay(self.ovltype)
                    self.overlay = ExistingSparseLoopbackDisk(overfile, size)
                else:
                    self.overlay = SparseLoopbackDisk(overfile, size)
                    resize = False
                self._LiveImageMount__created = False
                self.livemount = None
                self.overlay.create(ops=ops, dirmode=dirmode)
            else:
                _wipe_overlay(self.ovltype)
                self.livemount = OverlayFSMount('overlayfs', self.imgloop,
                                                overfile, None,
                                                self.mountdir, size=size,
                                                ops=ops, dirmode=dirmode)
            self.ovltype = ovl_fstype
            if resize:
                self.resize_overlay(size, existing_size, ovl_fstype, ovl_blksz)
            return self.overlay

    def resize_overlay(self, overlay_size_mb, existing_size, ovl_fstype,
                       ovl_blksz):
        if ovl_fstype in ('', 'temp', 'DM_snapshot_cow'):
            overlay = self.overlay
        else:
            overlay = self.livemount.cowloop

        if overlay_size_mb > existing_size:
            overlay.expand(create=True, size=overlay_size_mb)
        else:
            overlay.truncate(size=overlay_size_mb)

        if ovl_fstype in ('', 'temp', 'DM_snapshot_cow'):
            self.reset_overlay()
        else:
            self.livemount.recreate_overlay(ovl_fstype, ovl_blksz, 'overlayfs',
                                            dirmode=0o755)

    def reset_overlay(self):
        if self.ovltype in ('', 'temp', 'DM_snapshot_cow'):
            reset_overlay_args = ['dd', 'if=/dev/zero', 'of=%s' %
                                  self.overlay, 'bs=64k', 'count=1',
                                  'conv=notrunc,fsync']
            call(reset_overlay_args)
        else:
            self.unmount()
            if self.ovltype == 'dir':
                ovl = self.livemount.upper[10:]
            else:
                self.livemount.cowmnt.mount(ops='rw')
                ovl = os.path.join(self.livemount.cowmnt.mountdir, 'overlayfs')
            shutil.rmtree(ovl)
            os.mkdir(ovl, 0o755)
            call(['chcon', '--reference=/', ovl])
            if self.ovltype != 'dir':
                self.livemount.cowmnt.cleanup()

    def mount(self, ops='', dirmode=None):
        if self.mounted:
            return
        if not ops:
            ops = self.ops
        try:
            self.__create(ops=ops, dirmode=dirmode)
            self.livemount.mount(ops=ops, dirmode=dirmode)
            if self.homemnt:
                self.homemnt.mount(ops=ops)
        except MountError as e:
            self.cleanup()
            raise MountError('Failed to mount %s : %s' % (self.srcdir, e))
        else:
            self.mounted = True

    def unmount(self):
        if not self.mounted:
            return
        if self.homemnt:
            self.homemnt.unmount()
            time.sleep(2)
        if self.livemount:
            self.livemount.unmount()
        self.mounted = False

    def cleanup(self):
        self.unmount()
        if self.homemnt:
            self.homemnt.cleanup()
        if self.dm_target:
            self.dm_target.remove()
            self.dm_target = None
        if self.livemount:
            self.livemount.cleanup()
        if self.imgloop:
            self.imgloop.cleanup()
        if isinstance(self.cowloop, LoopbackDisk):
            self.cowloop.cleanup()
        if self.squashmnt:
            self.squashmnt.cleanup()
        self.__created = False


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

    cowloop = SparseLoopbackDisk(os.path.join(os.path.dirname(path), 'osmin'),
                                 64 * 1024 ** 2)

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

