## automake - create Makefile.in from Makefile.am
## Copyright (C) 2001-2015 Free Software Foundation, Inc.

## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 2, or (at your option)
## any later version.

## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.

## You should have received a copy of the GNU General Public License
## along with this program.  If not, see <http://www.gnu.org/licenses/>.

## New parallel test driver.
##
## The first version of the code here was adapted from check.mk, which was
## originally written at EPITA/LRDE, further developed at Gostai, then made
## its way from GNU coreutils to end up, largely rewritten, in Automake.
## The current version is an heavy rewrite of that, to allow for support
## of more test metadata, and the use of custom test drivers and protocols
## (among them, TAP).

## Used by (at least) 'check-typos.am'.
am.conf.using-parallel-tests := yes

am.test-suite.is-xfail = \
  $(if $(filter-out $(am.test-suite.xfail-test-bases), \
                    $(patsubst $(srcdir)/%,%,$(1))),no,yes)

am.test-suite.runtest = \
  $(am.test-suite.tty-colors);						\
  if test '$(TEST_SUITE_LOG)' = '$*.log'; then				\
    echo "fatal: $*.log: depends on itself (check TESTS content)" >&2;	\
    exit 1;								\
  fi;									\
  srcdir=$(srcdir); export srcdir;					\
## Creates the directory for the log file if needed.  Avoid extra forks.
  test x$(@D) = x. || test -d $(@D) || $(MKDIR_P) $(@D) || exit $$?;	\
## We need to invoke the test in way that won't cause a PATH search.
## Quotes around '$<' are required to avoid extra errors when a circular
## dependency is detected (e.g., because $(TEST_SUITE_LOG) is in
## $(am.test-suite.test-logs)), because in that case '$<' expands to empty and an
## unquote usage of it could cause syntax errors in the shell.
  case '$<' in */*) tst='$<';; *) tst=./'$<';; esac;			\
## Executes the developer-defined and user-defined test
## setups (if any), in that order.
  $(AM_TESTS_ENVIRONMENT) $(TESTS_ENVIRONMENT)				\
  $($(1)LOG_DRIVER)							\
  --test-name '$(patsubst $(srcdir)/%,%,$<)'				\
  --log-file $*.log							\
  --trs-file $*.trs							\
  --color-tests "$$am__color_tests"					\
  --enable-hard-errors $(if $(DISABLE_HARD_ERRORS),no,yes)		\
  --expect-failure $(call am.test-suite.is-xfail,$*)			\
  $(AM_$(1)LOG_DRIVER_FLAGS)						\
  $($(1)LOG_DRIVER_FLAGS)						\
  --									\
  $($(1)LOG_COMPILER)							\
  $(AM_$(1)LOG_FLAGS)							\
  $($(1)LOG_FLAGS)							\
  "$$tst"								\
  $(AM_TESTS_FD_REDIRECT)

define am.test-suite.handle-suffix.helper
ifeq ($$(call am.vars.is-undef,$(2)LOG_DRIVER),yes)
$(2)LOG_DRIVER = $(SHELL) $(am.conf.aux-dir)/test-driver
endif
%.log %.trs: %$1 $$($(2)LOG_DEPENDENCIES)
	@$$(call am.test-suite.runtest,$2)
ifdef EXEEXT
%.log %.trs: %$1$(EXEEXT) $$($(2)LOG_DEPENDENCIES)
	@$$(call am.test-suite.runtest,$2)
endif
endef

define am.test-suite.handle-suffix
$(call $0.helper,$1,$(if $1,$(call am.util.toupper,$(patsubst .%,%_,$1))))
endef

ifeq ($(call am.vars.is-undef,TEST_EXTENSIONS),yes)
  TEST_EXTENSIONS := .test
endif

$(foreach e,$(filter-out .%,$(TEST_EXTENSIONS)),\
  $(call am.error,invalid test extension: '$e'))
$(foreach e,$(TEST_EXTENSIONS), \
  $(eval $(call am.test-suite.handle-suffix,$e)))
# It is *imperative* that the "empty" suffix goes last.  Otherwise, a
# declaration like "TESTS = all.test" would cause GNU make to mistakenly
# try to build the 'all.log' and 'all.trs' files from a non-existent
# 'all' program (because the Makefile contains an explicit 'all' target,
# albeit .PHONY), rather than from the 'all.test' script, thus causing
# all sort of mishaps and confusion.
$(eval $(call am.test-suite.handle-suffix))

# The names of the given tests scripts with any possible registered
# test extension removed, as well as any leading '$(srcdir)' component
# (if any) stripped.
# The stripping of $(srcdir) is required to support explicit use of
# $(srcdir) in TESTS entries.  That might actually be very useful in
# practice, for example in usages like this:
#   TESTS = $(wildcard $(srcdir)/t[0-9][0-9]*.sh)
# where removing the $(srcdir) from the $(wildcard) invocation would
# cause the idiom to break in VPATH builds.
define am.test-suite.get-test-bases
$(patsubst $(srcdir)/%,%,$(strip \
  $(call am.util.strip-suffixes, $(TEST_EXTENSIONS), \
  $(if $(EXEEXT),$(patsubst %$(EXEEXT),%,$1),$1))))
endef

am.test-suite.rx.recheck = ^[ 	]*:recheck:[ 	]*
am.test-suite.rx.global-result = ^[ 	]*:global-test-result:[ 	]*
am.test-suite.rx.result = ^[ 	]*:test-result:[ 	]*
am.test-suite.rx.copy-in-global-log = ^[ 	]*:copy-in-global-log:[ 	]*

# Some awk code fragments used by one another and eventually by the
# 'check' and 'recheck' recipes.
# Note that in those scripts we are careful to close all the '.trs' and
# '.log' files once we are done with them.  This is done to avoid leaking
# open file descriptors, which could cause serious problems when there
# are many tests and thus lots of '.log' and '.trs' files to open (yes,
# there would be problems even on Linux).

am.test-suite.awk-functions = \
  function error(msg) \
  { \
    print msg | "cat >&2"; \
    exit_status = 1; \
  } \
  function input_error(file) \
  { \
    error("awk" ": cannot read \"" file "\""); \
## Never leak file descriptors, not even on errors.
    close ($$0 ".trs"); close ($$0 ".log"); \
  }

# Loop on the lines in the current '.trs' or '.log' file,
# punting on I/O errors.
am.test-suite.awk-io-loop/BEGIN = \
  while ((rc = (getline line < ($$0 ".$1"))) != 0) { \
    if (rc < 0) { input_error($$0 ".$1"); next; }
am.test-suite.awk-io-loop/END = \
  }; close ($$0 ".$1");

# A command that, given a newline-separated list of test names on the
# standard input, print the name of the tests that are to be re-run
# upon "make recheck".
am.test-suite.list-tests-to-recheck = $(AWK) '{ \
## By default, we assume the test is to be re-run.
  recheck = 1; \
  while ((rc = (getline line < ($$0 ".trs"))) != 0) \
    { \
      if (rc < 0) \
        { \
##
## If we have encountered an I/O error here, there are three possibilities:
##
##  [1] The '.log' file exists, but the '.trs' does not; in this case,
##      we "gracefully" recover by assuming the corresponding test is
##      to be re-run (which will re-create the missing '.trs' file).
##
##  [2] Both the '.log' and '.trs' files are missing; this means that
##      the corresponding test has not been run, and is thus *not* to
##      be re-run.
##
##  [3] We have encountered some corner-case problem (e.g., a '.log' or
##      '.trs' files somehow made unreadable, or issues with a bad NFS
##      connection, or whatever); we do not handle such corner cases.
##
          if ((getline line2 < ($$0 ".log")) < 0) \
	    recheck = 0; \
          break; \
        } \
      else if (line ~ /$(am.test-suite.rx.recheck)[nN][Oo]/) \
## A directive explicitly specifying the test is *not* to be re-run.
        { \
          recheck = 0; \
          break; \
        } \
      else if (line ~ /$(am.test-suite.rx.recheck)[yY][eE][sS]/) \
        { \
## A directive explicitly specifying the test *is* to be re-run.
          break; \
        } \
## else continue with the next iteration.
    }; \
  if (recheck) \
    print $$0; \
## Never leak file descriptors.
  close ($$0 ".trs"); close ($$0 ".log"); \
}'

# A command that, given a newline-separated list of test names on the
# standard input, output a shell code snippet setting variables that
# count occurrences of each test result (PASS, FAIL, etc) declared in
# the '.trs' files of that given tests.  For example, the count of
# PASSes will be saved in the '$am_PASS' variable, the count of SKIPs
# in the '$am_SKIP' variable, and so on.
am.test-suite.count-results = $(AWK) ' \
$(am.test-suite.awk-functions) \
BEGIN { exit_status = 0; } \
{ \
  $(call am.test-suite.awk-io-loop/BEGIN,trs) \
      if (line ~ /$(am.test-suite.rx.result)/) \
        { \
          sub("$(am.test-suite.rx.result)", "", line); \
          sub("[: 	].*$$", "", line); \
          counts[line]++;\
        } \
  $(call am.test-suite.awk-io-loop/END,trs) \
} \
END { \
  if (exit_status != 0) \
    error("fatal: making $@: I/O error reading test results"); \
  else \
    { \
      global_count = 0; \
      for (k in counts) \
        { \
          print "am_" k "=" counts[k]; \
          global_count += counts[k]; \
        } \
     } \
  print "am_ALL=" global_count; \
  exit(exit_status); \
}'

# A command that, given a newline-separated list of test names on the
# standard input, create the global log from their .trs and .log files.
am.test-suite.create-global-log = $(AWK) ' \
$(am.test-suite.awk-functions) \
function rst_section(header) \
{ \
  print header; \
  len = length(header); \
  for (i = 1; i <= len; i = i + 1) \
    printf "="; \
  printf "\n\n"; \
} \
BEGIN { exit_status = 0; } \
{ \
## By default, we assume the test log is to be copied in the global log,
## and that its result is simply "RUN" (i.e., we still do not know what
## it outcome was, but we know that at least it has run).
  copy_in_global_log = 1; \
  global_test_result = "RUN"; \
  $(call am.test-suite.awk-io-loop/BEGIN,trs) \
      if (line ~ /$(am.test-suite.rx.global-result)/) \
        { \
          sub("$(am.test-suite.rx.global-result)", "", line); \
          sub("[ 	]*$$", "", line); \
          global_test_result = line; \
        } \
      else if (line ~ /$(am.test-suite.rx.copy-in-global-log)[nN][oO]/) \
        copy_in_global_log = 0; \
  $(call am.test-suite.awk-io-loop/END,trs) \
  if (copy_in_global_log) \
    { \
      rst_section(global_test_result ": " $$0); \
      $(call am.test-suite.awk-io-loop/BEGIN,log) \
        print line; \
      $(call am.test-suite.awk-io-loop/END,log) \
      printf "\n"; \
    }; \
} \
END { \
  if (exit_status != 0) \
    error("fatal: making $@: I/O error reading test results"); \
  exit(exit_status); \
}'

# Restructured Text title.
am.test-suite.rst-title = { sed 's/.*/   &   /;h;s/./=/g;p;x;s/ *$$//;p;g' && echo; }

# These support runtime overriding of $(TESTS) and $(XFAIL_TESTS).
# The first one must be left overridable (hence the definition with '?=',
# because the 'recheck' target need to override  it (and in a tricky way).
am.test-suite.test-bases ?= \
  $(call am.memoize,am.test-suite.test-bases,$(call am.test-suite.get-test-bases,$(TESTS)))
am.test-suite.xfail-test-bases = \
  $(call am.memoize,am.test-suite.xfail-test-bases,$(call am.test-suite.get-test-bases,$(XFAIL_TESTS)))

# The $(strip) is to work around the GNU make 3.80 bug where trailing
# whitespace in "TESTS = foo.test $(empty)" causes $(TESTS_LOGS) to
# erroneously expand to "foo.log .log".
am.test-suite.test-results = \
  $(call am.memoize,am.test-suite.test-results,$(addsuffix .trs,$(strip $(am.test-suite.test-bases))))
am.test-suite.test-logs = \
  $(call am.memoize,am.test-suite.test-logs,$(addsuffix .log,$(strip $(am.test-suite.test-bases))))

am.clean.mostly.f += $(am.test-suite.test-results) $(am.test-suite.test-logs)

# $(TEST_LOGS) is a published interface.
TEST_LOGS = $(am.test-suite.test-logs)

am.test-suite.workdir = $(am.dir)/test-harness

am.test-suite.append-to-list-of-bases = \
  @lst='$1'; for x in $$lst; do echo $$x; done \
    >> $(am.test-suite.workdir)/bases$(am.chars.newline)

define am.setup-test-harness-workdir
	@rm -rf $(am.test-suite.workdir)
	@$(MKDIR_P) $(am.test-suite.workdir)
	@touch $(am.test-suite.workdir)/bases
	$(call am.xargs-map,am.test-suite.append-to-list-of-bases, \
	       $(am.test-suite.test-bases))
	@workdir='$(am.test-suite.workdir)' \
	  && sed 's/$$/.log/' $$workdir/bases > $$workdir/logs \
	  && sed 's/$$/.trs/' $$workdir/bases > $$workdir/trs
endef

ifeq ($(call am.vars.is-undef,TEST_SUITE_LOG),yes)
  TEST_SUITE_LOG = test-suite.log
endif

$(TEST_SUITE_LOG): $(am.test-suite.test-logs) $(am.test-suite.test-results)
	$(am.setup-test-harness-workdir)
	@set +e; $(am.test-suite.tty-colors); \
	fatal () { echo "fatal: making $@: $$*" >&2; exit 1; }; \
	workdir='$(am.test-suite.workdir)'; \
## Prepare data for the test suite summary.  These do not take into account
## unreadable test results, but they'll be appropriately updated later if
## needed.
	am_PASS=0 am_FAIL=0 am_SKIP=0 am_XPASS=0 am_XFAIL=0 am_ERROR=0; \
	count_test_results_command=`\
	  $(am.test-suite.count-results) <$$workdir/bases` \
	  && eval "$$count_test_results_command" \
          || fatal "unknown error reading test results"; \
## Whether the testsuite was successful or not.
	if test `expr $$am_FAIL + $$am_XPASS + $$am_ERROR` -eq 0; then \
	  success=true; \
	else \
	  success=false; \
	fi; \
## Make $br a line of exactly 76 '=' characters, that will be used to
## enclose the testsuite summary report when displayed on the console.
	br='==================='; br=$$br$$br$$br$$br; \
## When writing the test summary to the console, we want to color a line
## reporting the count of some result *only* if at least one test
## experienced such a result.  This function is handy in this regard.
	display_result_count () \
	{ \
	    if test x"$$1" = x"--maybe-color"; then \
	      maybe_colorize=yes; \
	    elif test x"$$1" = x"--no-color"; then \
	      maybe_colorize=no; \
	    else \
	      echo "$@: invalid 'display_result_count' usage" >&2; \
	      exit 4; \
	    fi; \
	    shift; \
	    desc=$$1 count=$$2; \
	    if test $$maybe_colorize = yes && test $$count -gt 0; then \
	      color_start=$$3 color_end=$$std; \
	    else \
	      color_start= color_end=; \
	    fi; \
	    echo "$${color_start}# $$desc $$count$${color_end}"; \
	}; \
## A shell function that creates the testsuite summary.  We need it
## because we have to create *two* summaries, one for test-suite.log,
## and a possibly-colorized one for console output.
	create_testsuite_report () \
	{ \
	  opts=$$*; \
	  display_result_count $$opts "TOTAL:" $$am_ALL   "$$brg"; \
	  display_result_count $$opts "PASS: " $$am_PASS  "$$grn"; \
	  display_result_count $$opts "SKIP: " $$am_SKIP  "$$blu"; \
	  display_result_count $$opts "XFAIL:" $$am_XFAIL "$$lgn"; \
	  display_result_count $$opts "FAIL: " $$am_FAIL  "$$red"; \
	  display_result_count $$opts "XPASS:" $$am_XPASS "$$red"; \
	  display_result_count $$opts "ERROR:" $$am_ERROR "$$mgn"; \
	}; \
## Write "global" testsuite log.
	if {								\
	  st=0; 							\
	  echo "$(PACKAGE_STRING): $(subdir)/$(TEST_SUITE_LOG)" |	\
	    $(am.test-suite.rst-title);					\
	  create_testsuite_report --no-color;				\
	  echo;								\
	  echo ".. contents:: :depth: 2";				\
	  echo;								\
	  $(am.test-suite.create-global-log) <$$workdir/bases;		\
	} >$(TEST_SUITE_LOG).tmp; then					\
	  mv -f $(TEST_SUITE_LOG).tmp $(TEST_SUITE_LOG);		\
	else								\
## The awk program in $(am.test-suite.create-global-log) should have already
## emitted a proper error message about I/O error, no need to repeat it.
	  rm -f $(TEST_SUITE_LOG).tmp; exit 1;				\
	fi;								\
## Emit the test summary on the console.
	if $$success; then						\
	  col="$$grn";							\
	 else								\
	  col="$$red";							\
	  test x"$$VERBOSE" = x || cat $(TEST_SUITE_LOG);		\
	fi;								\
## Multi line coloring is problematic with "less -R", so we really need
## to color each line individually.
	echo "$${col}$$br$${std}"; 					\
	echo "$${col}Testsuite summary for $(PACKAGE_STRING)$${std}";	\
	echo "$${col}$$br$${std}"; 					\
## This is expected to go to the console, so it might have to be colorized.
	create_testsuite_report --maybe-color;				\
	echo "$$col$$br$$std";						\
	if $$success; then :; else					\
	  echo "$${col}See $(subdir)/$(TEST_SUITE_LOG)$${std}";		\
	  if test -n "$(PACKAGE_BUGREPORT)"; then			\
	    echo "$${col}Please report to $(PACKAGE_BUGREPORT)$${std}";	\
	  fi;								\
	  echo "$$col$$br$$std";					\
	fi;								\
	$$success || exit 1

am.clean.mostly.f += $(TEST_SUITE_LOG)

## ------------------------------------------ ##
## Running all tests, or rechecking failures. ##
## ------------------------------------------ ##

check-TESTS:
ifneq ($(AM_LAZY_CHECK),yes)
	@$(call am.clean-cmd.f, \
	        $(am.test-suite.test-results) $(am.test-suite.test-logs))
endif
## We always have to remove TEST_SUITE_LOG, to ensure its rule is run
## in any case even in lazy mode: otherwise, if no test needs rerunning,
## or a prior run plus reruns all happen within the same timestamp (can
## happen with a prior "make TESTS=<subset>"), then we get no log output.
## OTOH, this means that, in the rule for '$(TEST_SUITE_LOG)', we
## cannot use '$?' to compute the set of lazily rerun tests, lest
## we rely on .PHONY to work portably.
	@rm -f $(TEST_SUITE_LOG)
	$(MAKE) $(TEST_SUITE_LOG)
.PHONY: check-TESTS

# Recheck must depend on $(check_SCRIPTS), $(check_PROGRAMS), etc.
# It must also depend on the 'all' target.  See automake bug#11252.
recheck: all $(am.test-suite.deps)
	+$(am.setup-test-harness-workdir)
## See comments above in the check-TESTS recipe for why remove
## $(TEST_SUITE_LOG) here.
	@test -z "$(TEST_SUITE_LOG)" || rm -f $(TEST_SUITE_LOG)
	@bases=`$(am.test-suite.list-tests-to-recheck) \
	          <$(am.test-suite.workdir)/bases` || exit 1; \
## Remove newlines and normalize whitespace.
	bases=`echo $$bases`; \
## Re-run the relevant tests, without hitting command-line length limits.
	echo am.test-suite.test-bases="$$bases" | \
	  $(MAKE) -f- -f$(firstword $(MAKEFILE_LIST)) \
	          $(TEST_SUITE_LOG) .am/doing-recheck=yes
.PHONY: recheck

# One tricky requirement of the "recheck" target is that, in case (say)
# the test is a compiled program whose compilation fails, we must ensure
# that any '.log' and '.trs' file referring to such test are preserved,
# so that future "make recheck" invocations will still try to re-compile
# and re-run it (automake bug#11791).  This indirection is aimed at
# satisfying such a requirement.
ifeq ($(.am/doing-recheck),yes)
$(am.test-suite.test-logs) $(am.test-suite.test-results): .am/nil
endif

AM_RECURSIVE_TARGETS += check recheck