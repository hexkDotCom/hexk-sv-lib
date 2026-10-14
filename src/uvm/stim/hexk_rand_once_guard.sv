// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_rand_once_guard.sv
//
// Guard against the accidental second randomization of an object that must be randomized
// exactly once, such as the top cfg of an environment or the plan of a test. A second
// randomize() silently replaces values that other objects already used; the guard turns it
// into an error with the name of the object and a stack trace.
// The guarded class has a guard as a member and calls on_pre_randomize() from its
// pre_randomize() and on_post_randomize() from its post_randomize(); the macro
// `hexk_rand_once_guard_decl declares all three. Only a randomization that succeeds counts:
// post_randomize() runs only then. A test that re-randomizes on purpose calls
// allow_rerandomize() before each such randomization; a failed attempt does not use it up.
// +hexk_rand_once_trap=<full name> reports the first randomization of that object with a
// stack trace, to find out who randomizes it.
//
//! @module    hexk_rand_once
//! @since     0.7.0
//! @stability experimental
//! @serves    CFG-3
//! @emits     HEXK_RAND_ONCE:error HEXK_RAND_ONCE_TRAP:info
//! @plusargs  +hexk_rand_once_trap

`ifndef HEXK_RAND_ONCE_GUARD_SV
`define HEXK_RAND_ONCE_GUARD_SV

class hexk_rand_once_guard;

   local uvm_object guarded;
   local bit        randomized;
   local bit        rerandomize_allowed;

   // Creates the guard of owner, whose full name is used in the messages.
   function new(uvm_object owner);
      guarded = owner;
   endfunction : new

   // To be called from pre_randomize() of the owner: reports a randomization after a successful one, before the
   // solver replaces any value.
   function void on_pre_randomize();
      if (!randomized) begin
         if (owner_name() == hexk_plusarg::get_str("hexk_rand_once_trap", "")) begin
            `uvm_info("HEXK_RAND_ONCE_TRAP",
                      $sformatf("%s is randomized for the first time; +hexk_rand_once_trap asks for the stack trace",
                                owner_name()), UVM_NONE)
            `HEXK_STACKTRACE;
         end
         return;
      end
      if (rerandomize_allowed) begin
         return;
      end
      `uvm_error("HEXK_RAND_ONCE", $sformatf(
                 "%s is randomized again, but it must be randomized only once; values that were read earlier %s",
                 owner_name(),
                 "may no longer match (call allow_rerandomize() first if this is intended)"
                 ))
      `HEXK_STACKTRACE;
   endfunction : on_pre_randomize

   // To be called from post_randomize() of the owner, which runs only after a successful randomization: from now on
   // the owner counts as randomized, and a successful rerandomization uses up its allowance.
   function void on_post_randomize();
      if (randomized) begin
         rerandomize_allowed = 0;
      end
      randomized = 1;
   endfunction : on_post_randomize

   // Allows the next successful randomization of the owner; later ones are errors again.
   function void allow_rerandomize();
      rerandomize_allowed = 1;
   endfunction : allow_rerandomize

   // 1 once a randomization of the owner succeeded; a failed one does not count.
   function bit was_randomized();
      return randomized;
   endfunction : was_randomized

   // Full name of the owner for messages.
   local function string owner_name();
      return (guarded == null) ? "an object without a name" : guarded.get_full_name();
   endfunction : owner_name

endclass : hexk_rand_once_guard

`endif  // HEXK_RAND_ONCE_GUARD_SV
