#! /bin/sh
# Copyright (C) 1996-2017 Free Software Foundation, Inc.
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

# Make sure that object names don't clash when using subdir-objects.

. test-init.sh

mkdir -p src

cat >> configure.ac << 'END'
AC_PROG_CC
AC_PROG_RANLIB
AC_OUTPUT
END

cat > Makefile.am << 'END'
AUTOMAKE_OPTIONS = subdir-objects foreign
noinst_PROGRAMS = foo
foo_SOURCES = src/foo.c src/main.c
foo_CPPFLAGS = -DVAL=0
noinst_LIBRARIES = libbar.a
libbar_a_SOURCES = src/foo.c
#noinst_PROGRAMS += bar
#bar_SOURCES = src/main.c
#bar_LDADD = libbar.a
include src/local.mk
END

cat > src/local.mk << 'END'
noinst_PROGRAMS += src/foo
src_foo_CPPFLAGS = -DVAL=1
src_foo_SOURCES = src/foo.c src/main.c
#noinst_PROGRAMS += src/bar
#noinst_LIBRARIES += src/libbar.a
#src_bar_SOURCES = src/main.c
#src_bar_LDADD = src/libbar.a
END

cat > src/foo.c << 'END'
int
foo ()
{
  return VAL;
}
END

cat > src/main.c << 'END'
int foo (void);

int
main ()
{
  return foo ();
}
END

$ACLOCAL
$AUTOCONF
$AUTOMAKE --add-missing

./configure
$MAKE
./foo || fail_ "./foo should return 0"
./src/foo && fail_ "./src/foo should return 1"
#~ ./bar || fail_ "./foo should return 0"
#~ ./src/bar && fail_ "./src/foo should return 1"
$MAKE clean
