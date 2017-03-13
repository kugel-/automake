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

mkdir -p one/one one/two/sub one/three

cat >> configure.ac << 'END'
AC_PROG_CC
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
AUTOMAKE_OPTIONS  = subdir-objects
include one/Makefile.inc
END

cat > one/Makefile.inc << 'END'
noinst_PROGRAMS   =
include %D%/one/Makefile.inc
include %D%/two/Makefile.inc
include %D%/three/Makefile.inc
END

cat > one/one/Makefile.inc << 'END'
noinst_PROGRAMS  += %D%/test
%C%_test_CFLAGS   = $(AM_CFLAGS)
%C%_test_SOURCES  = %D%/test.c
END

cat > one/one/test.c << 'END'
int main()
{
	return 0;
}
END

cat > one/two/Makefile.inc << 'END'
noinst_PROGRAMS  += %D%/test
%C%_test_CFLAGS   = $(AM_CFLAGS)
%C%_test_SOURCES  = %D%/test.c
%C%_test_SOURCES += %D%/sub/test.c
END

cat > one/two/test.c << 'END'
int main()
{
	return 0;
}
END

: > one/two/sub/test.c

cat > one/three/Makefile.inc << 'END'
noinst_PROGRAMS  += %D%/my_test
%C%_my_test_CFLAGS   = $(AM_CFLAGS)
%C%_my_test_SOURCES  = %D%/my_test.c
END

cat > one/three/my_test.c << 'END'
int main()
{
	return 0;
}
END

$ACLOCAL
$AUTOCONF
$AUTOMAKE --gnu

./configure
$MAKE -f Makefile \
	&& test -f one/one/test-test.o && test ! -f one/one/one_two_test-test.o \
	&& test -f one/two/test-test.o && test ! -f one/two/one_two_test-test.o \
	&& test -f one/two/sub/test-test.o && test ! -f one/two/sub/one_two_test-test.o \
	&& test -f one/three/my_test-my_test.o && test ! -f one/three/one_three_my_test-my_test.o
$MAKE -f Makefile clean
