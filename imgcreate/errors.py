#
# errors.py : exception definitions
#
# Copyright 2007, Red Hat, Inc.
# Copyright 2017, Fedora Project
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

class CreatorError(Exception):
    """An exception base class for all imgcreate errors."""
    def __init__(self, message):
        Exception.__init__(self, message)

class KickstartError(CreatorError):
    pass
class MountError(CreatorError):
    pass
class SnapshotError(CreatorError):
    pass
class CryptoLUKSError(CreatorError):
    pass
class SquashfsError(CreatorError):
    pass
class ResizeError(CreatorError):
    pass
