#
# errors.py : exception definitions
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

class CreatorError(Exception):
    """An exception base class for all imgcreate errors."""
    def __init__(self, msg):
        Exception.__init__(self, msg)

    # Some error messages may contain unicode strings (especially if your system
    # locale is different from 'C', e.g. 'de_DE'). Python's exception class does
    # not handle this appropriately (at least until 2.5) because str(Exception)
    # returns just self.message without ensuring that all characters can be
    # represented using ASCII. So we try to return a str and fall back to repr
    # if this does not work.
    #
    # Please use unicode for your error logging strings so that we can really
    # print nice error messages, e.g.:
    #     log.error(u"Internal error: " % e)
    # instead of
    #     log.error("Internal error: " % e)
    # With our custom __str__ and __unicode__ methods both will work but the
    # first log call print a more readable error message.
    def __str__(self):
        try:
            return str(self.message)
        except UnicodeEncodeError:
            return repr(self.message)

    def __unicode__(self):
        return unicode(self.message)

class KickstartError(CreatorError):
    pass
class MountError(CreatorError):
    pass
class SnapshotError(CreatorError):
    pass
class SquashfsError(CreatorError):
    pass
class ResizeError(CreatorError):
    pass
