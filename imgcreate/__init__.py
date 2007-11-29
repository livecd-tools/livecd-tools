#!/usr/bin/python -tt
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

"""A set of classes for building Fedora system images.

The following image creators are available:
  - ImageCreator - installs to a directory
  - LoopImageCreator - installs to an ext3 image
  - LiveImageCreator - installs to a bootable ISO

Each of the creator classes are designed to be subclassable, allowing the user
to create new creator subclasses in order to support the building other types
of system images.

Also exported are:
  - CreatorError - all exceptions throw are of this type
  - read_kickstart() - a utility function for kickstart parsing

"""

__all__ = (
    'CreatorError',
    'ImageCreator',
    'LiveImageCreator',
    'LoopImageCreator',
    'read_kickstart'
)
