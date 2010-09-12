#!/usr/bin/env python

__author__ = "Jasper Hartline"
__credits__ = ""
__license__ = "GPL?"
__version__ = "Alpha"
__description__ = "Attempts to create a 32/64 bit combination live Fedora image."

import os
import sys
import shutil
import parted
import subprocess
import tempfile
import math

from optparse import OptionParser

def main():

    def cleanup():
        pass


    def mount(src, dst, options=None):
        if os.path.exists(src):         # Is src the lodev device?
            if not os.path.exists(dst): 
                os.makedir(dst)
            if options:                 # None is the same as Null so you can test for existence instead.
                args = ("/bin/mount", options, src, dst)
            else:
                args = ("/bin/mount", src, dst)
                
            rc = subprocess.call(args)
            return rc
        else:                           # Let's make sure only one return statement get's triggered.
            return False                # Might as well return something useful so we can test for failure.


    def umount(src):
        if os.path.exists(src):
                args = ("/bin/umount", src)
                rc = subprocess.call(args)
                return rc
        else:
            return False


    def copy(src, dst):
        if os.path.exists(src):
            shutil.copy(src, dst)
            return True
        else:
            return False


    def move(src, dst):
        if os.path.exists(src):
            shutil.mopve(src, dst)
            return True
        else:
            return False


    def losetup(src, dst, offset=None):
        if os.path.exists(src) and os.path.exists(dst):
            if offset:
                args = ("/sbin/losetup", "-o", offset, src, dst)
            else:
                args = ("/sbin/losetup", src, dst)
                    
            rc = subprocess.call(args)
            return rc
        else:
            return False
        

    def null():
        fd = open("/dev/null", "w")
        return fd

    def lo():
        args = ("/sbin/losetup", "--find")
        rc = subprocess.call(args, stdout=open(null())).communicate()[0].rstrip()
        return rc


    def mkimage(bs, count):
        tmp = tempfile.mkstemp()
        image = tmp[1]
        args = ("/bin/dd",
                "if=/dev/zero",
                "of=%s" % image,
                "bs=%s" % bs,
                "count=%s" % count)
        rc = subprocess.call(args)
        return image


    def size(ent):
        size = os.path.getsize(ent)
        if size >= 0:
            return os.path.getsize(ent)
        else:
            print "Something is wrong, %s has no size." % ent
            return False


    def blocks(block_size, size):
        # Round up to nearest block
        # Make sure floating math, not integer math or we don't get remainders.
        # Turn back into an integer for return statement.
        return int(math.ceil(size / float(block_size)))


    def setup(x86, x64, multi):
        # Reworked the logic a bit.
        block_size = 2048               # Should this be a global constant instead?
        sz = size(x86) + size(x64)
        count = blocks(block_size, sz)
        
        multi = mkimage(str(blsz), count)
        losetup(multi, lo())         
 

    def parse(x86, x64, multi):
        for file in x86, x64, multi:    # Do we expect that multi exists yet?
            if os.path.exists(file):    # Should we test for existance or isfile?
                pass
            else:
                parser.error("One of the images does not exist.")
        setup(x86, x64, multi)

    # Generate parser and fill with options.
    usage = "usage: %prog [options] <32bit image> <64bit image> <biarch image>"
    version = "%prog " + __version__
    parser = OptionParser(usage=usage, description=__description__, version=version)
    parser.add_option("--test", action="store_true", default=False,
                      dest="test", help="Doesn't do anything yet.")
    (options, args) = parser.parse_args()
    if len(args) != 3:
        parser.error("You must specify all three arguments.")
        sys.exit(0)
        
    try:                                # Any reason this would fail?
        parse(args[0], args[1], args[2])
    except:
        parser.error("Something failed. Better luck next time!")
        sys.exit(1)
               
if __name__ == "__main__":
    sys.exit(main())