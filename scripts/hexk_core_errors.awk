# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 HEXK
#
# hexk_core_errors.awk
#
# Reads a log of SVUnit unit tests from Verilator, Questa or VCS and prints the $error messages
# of the core library in it, one per line as "<suite> <message>": the suite is the unit test
# that was running (its name without "_ut"), the message starts with "hexk_<class>::<function>:"
# as every message of the core does. Each simulator writes an $error its own way: Verilator as
# "%Error: <file>:<line>: Assertion failed in <scope>: <message>", Questa as
# "# ** Error: <message>", VCS as a line 'Error: "<file>", <line>: ...' with the message on the
# next line. 'make test' compares the result with tests/unit/expected_core_errors.txt.

/\]\[[A-Za-z0-9_]+_ut\]: [^ ]+::RUNNING/ {
   if (match($0, /\]\[[A-Za-z0-9_]+_ut\]/)) {
      suite = substr($0, RSTART + 2, RLENGTH - 6)
   }
}
/^Error: "/ {
   vcs = 1
   next
}
{
   line = $0
   found = 0
   if (vcs) {
      found = 1
   } else if (sub(/^.*%Error: [^ ]+ Assertion failed in [^ ]+ /, "", line)) {
      found = 1
   } else if (sub(/^# \*\* Error: /, "", line)) {
      found = 1
   }
   vcs = 0
   if (found && line ~ /^hexk_[a-z0-9_]+(\([^)]*\))?::[a-z0-9_]+: /) {
      print (suite == "" ? "-" : suite), line
   }
}
