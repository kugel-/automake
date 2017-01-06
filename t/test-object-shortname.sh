#! /bin/sh
# Copyright (C) 1996-2015 Free Software Foundation, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Test to make sure the object-shortname option works as advertised

. test-init.sh

mkdir -p one/two

cat >> configure.ac << 'END'
AC_PROG_CC

AC_CONFIG_FILES([Makefile2])
AC_OUTPUT
END

# Files required because we are using '--gnu'.
: > INSTALL
: > NEWS
: > README
: > COPYING
: > AUTHORS
: > ChangeLog

cat > Makefile.am << 'END'
AUTOMAKE_OPTIONS = subdir-objects
include one/Makefile.inc
END

cat > Makefile2.am << 'END'
AUTOMAKE_OPTIONS = subdir-objects object-shortname
include one/Makefile.inc
END

cat > one/Makefile.inc << 'END'
include %D%/two/Makefile.inc
END

cat > one/two/Makefile.inc << 'END'
noinst_PROGRAMS = %D%/test
%C%_test_CFLAGS = $(AM_CFLAGS)
%C%_test_SOURCES = %D%/test.c
END

cat > one/two/test.c << 'END'
int main()
{
	return 0;
}
END

$ACLOCAL
$AUTOCONF
$AUTOMAKE --gnu

./configure
$MAKE -f Makefile && test -f one/two/one_two_test-test.o && test ! -f one/two/test-test.o
$MAKE clean
$MAKE -f Makefile2 && test -f one/two/test-test.o && test ! -f one/two/one_two_test-test.o
