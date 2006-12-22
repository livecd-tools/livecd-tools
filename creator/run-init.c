/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2006 H. Peter Anvin - All Rights Reserved
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * ----------------------------------------------------------------------- */

/*
 * run-init.c
 *
 * Usage: exec run-init [-c /dev/console] /real-root /sbin/init "$@"
 *
 * This program should be called as the last thing in a shell script
 * acting as /init in an initramfs; it does the following:
 *
 * - Delete all files in the initramfs;
 * - Remounts /real-root onto the root filesystem;
 * - Chroots;
 * - Opens /dev/console;
 * - Spawns the specified init program (with arguments.)
 */

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include "run-init.h"

static const char *program;

static void __attribute__ ((noreturn)) usage(void)
{
	fprintf(stderr,
		"Usage: exec %s [-c consoledev] /real-root /sbin/init [args]\n",
		program);
	exit(1);
}

int main(int argc, char *argv[])
{
	/* Command-line options and defaults */
	const char *console = "/dev/console";
	const char *realroot;
	const char *init;
	const char *error;
	char **initargs;

	/* Variables... */
	int o;

	/* Parse the command line */
	program = argv[0];

	while ((o = getopt(argc, argv, "c:")) != -1) {
		if (o == 'c') {
			console = optarg;
		} else {
			usage();
		}
	}

	if (argc - optind < 2)
		usage();

	realroot = argv[optind];
	init = argv[optind + 1];
	initargs = argv + optind + 1;

	error = run_init(realroot, console, init, initargs);

	/* If run_init returns, something went wrong */
	fprintf(stderr, "%s: %s: %s\n", program, error, strerror(errno));
	return 1;
}
