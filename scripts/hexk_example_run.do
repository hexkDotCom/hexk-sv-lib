# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 HEXK
#
# hexk_example_run.do
#
# Questa commands of 'make examples': runs an example for at most the time given as the two
# arguments, a number and a unit, and says whether it was still running then.
#   vsim -c -do "do hexk_example_run.do 10 ms" <example>
# An example that ends with $finish, as every UVM test does, leaves the simulator at that
# point. One that just runs out of events is over too: the simulator steps to the time
# limit and finds nothing more to do. One that is stuck while its clock keeps running still
# has events after the time limit; the line HEXK_EXAMPLE_STILL_RUNNING in the log says so,
# and 'make examples' fails on it.

run $1 $2
set hexk_time_limit $now
# The first step may only finish the events of the current time; the second one moves on to
# the next time that has an event, if there is one.
run -next
run -next
if {$now != $hexk_time_limit} {
   echo "HEXK_EXAMPLE_STILL_RUNNING after $1 $2"
}
quit -f
