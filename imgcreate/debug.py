#
# debug.py: Helper routines for debugging
#
# Copyright 2008, Red Hat  Inc.
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
#

import logging
import logging.handlers
import optparse
import sys


def handle_logging(option, opt, val, parser, logger, level):
    if level < logger.level:
        logger.setLevel(level)

def handle_logfile(option, opt, val, parser, logger):

    try:
        logfile = logging.FileHandler(val,"a")
    except IOError, e:
        raise optparse.OptionValueError("Cannot open file '%s' : %s" %
                                        (val, e.strerror))
    logger.addHandler(logfile)

def handle_quiet(option, opt, val, parser, logger, stream):
    logger.removeHandler(stream)

def setup_logging(parser = None):
    """Set up the root logger and add logging options.

    Set up the root logger so only warning/error messages are logged to stderr
    by default.

    Also, optionally, add --debug, --verbose and --logfile command line options
    to the supplied option parser, allowing the root logger configuration to be
    modified by the user.

    Note, to avoid possible namespace clashes, setup_logging() will only ever
    add these three options. No new options will be added in the future.

    parser -- an optparse.OptionParser instance, or None

    """
    logger = logging.getLogger()

    logger.setLevel(logging.WARN)

    stream = logging.StreamHandler(sys.stderr)

    logger.addHandler(stream)

    if parser is None:
        return

    group = optparse.OptionGroup(parser, "Debugging options",
                                 "These options control the output of logging information during image creation")

    group.add_option("-d", "--debug",
                     action = "callback", callback = handle_logging,
                     callback_args = (logger, logging.DEBUG),
                     help = "Output debugging information")

    group.add_option("-v", "--verbose",
                     action = "callback", callback = handle_logging,
                     callback_args = (logger, logging.INFO),
                     help = "Output verbose progress information")

    group.add_option("-q", "--quiet",
                     action = "callback", callback = handle_quiet,
                     callback_args = (logger, stream),
                     help = "Supress stdout")

    group.add_option("", "--logfile", type="string",
                     action = "callback", callback = handle_logfile,
                     callback_args = (logger,),
                     help = "Save debug information to FILE", metavar = "FILE")

    parser.add_option_group(group)
