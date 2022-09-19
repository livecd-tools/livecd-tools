#
# util.py : Various utility methods
#
# Copyright 2010, Red Hat, Inc.
# Copyright 2017-2021, Fedora Project
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
import io
from imgcreate.errors import *

def call(*popenargs, **kwargs):
    """
        Calls subprocess.Popen() with the provided arguments.  All stdout and
        stderr output is sent to logging.debug().  The return value is the exit
        code of the command.
    """
    p = subprocess.Popen(*popenargs, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, **kwargs)
    rc = p.wait()
    fp = io.open(p.stdout.fileno(), mode="r", encoding="utf-8", closefd=False)
    stdout = fp.read().splitlines(keepends=False)
    fp.close()

    # Log output using logging module
    for buf in stdout:
        logging.debug("%s", buf)

    return rc

def rcall(args, stdin='', raise_err=True, cwd=None, env=None):
    """Return stdout, stderr, & returncode from a subprocess call."""

    out, err, p, environ = '', '', None, None
    if env is not None:
        environ = os.environ.copy()
        environ.update(env)
    try:
        p = subprocess.Popen(args, stdin=subprocess.PIPE, cwd=cwd, env=environ,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, err = p.communicate(stdin.encode('utf-8'))
    except OSError as e:
        err = 'Failed executing:\n%s\nerror: %s' % (args, e)
        if raise_err:
            raise CreatorError('Failed executing:\n%s\nerror: %s' % (args, e))
    except Exception as e:
        err = 'Failed to execute:\n%s\nerror: %s' % (args, e)
        if raise_err:
            raise CreatorError('Failed ta execute:\n%s\n'
                                'error: %s\nstdout: %s\nstderr: %s' %
                               (args, e, out, err))
    else:
        if p.returncode != 0 and raise_err:
            raise CreatorError('Error in call:\n%s\nenviron: %s\n'
                                'stdout: %s\nstderr: %s\nreturncode: %s' %
                               (args, environ, out, err, p.returncode))
    finally:
        return out.decode('utf-8'), err.decode('utf-8'), p.returncode
