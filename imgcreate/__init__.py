#
# imgcreate : Support for creating system images, including Live CDs
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

from imgcreate.live import *
from imgcreate.creator import *
from imgcreate.yuminst import *
from imgcreate.kickstart import *
from imgcreate.fs import *
from imgcreate.debug import *

"""A set of classes for building Fedora system images.

The following image creators are available:
  - ImageCreator - installs to a directory
  - LoopImageCreator - installs to an ext3 image
  - LiveImageCreator - installs to a bootable ISO

Also exported are:
  - CreatorError - all exceptions throw are of this type
  - FSLABEL_MAXLEN - the length to which LoopImageCreator.fslabel is truncated
  - read_kickstart() - a utility function for kickstart parsing
  - build_name() - a utility to construct an image name

Each of the creator classes are designed to be subclassable, allowing the user
to create new creator subclasses in order to support the building other types
of system images.

The subclassing API consists of:

  1) Attributes available to subclasses, e.g. ImageCreator._instroot

  2) Hooks - methods which may be overridden by subclasses, e.g.
     ImageCreator._mount_instroot()

  3) Helpers - methods which may be used by subclasses in order to implement
     hooks, e.g. ImageCreator._chroot()

Overriding public methods (e.g. ImageCreator.package()) or subclassing helpers
is not supported and is not guaranteed to continue working as expect in the
future.

"""

__all__ = (
    'CreatorError',
    'ImageCreator',
    'LiveImageCreator',
    'LoopImageCreator',
    'FSLABEL_MAXLEN',
    'read_kickstart',
    'construct_name',
    'setup_logging',
)
