#
# util.py : Various utility methods
#
# Copyright 2010, Red Hat  Inc.
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

import subprocess
import logging

def call(*popenargs, **kwargs):
    '''
        Calls subprocess.Popen() with the provided arguments.  All stdout and
        stderr output is sent to logging.debug().  The return value is the exit
        code of the command.
    '''
    p = subprocess.Popen(*popenargs, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kwargs)
    rc = p.wait()

    # Log output using logging module
    while True:
        # FIXME choose a more appropriate buffer size
        buf = p.stdout.read(4096)
        if not buf:
            break
        logging.debug("%s", buf)

    return rc
