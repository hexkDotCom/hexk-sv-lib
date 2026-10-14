// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// slang.f - options for slang elaboration in Gate 1 (make elab).
// Warnings are errors (guide rule LNG-32). Warnings from the UVM sources themselves are
// suppressed by path on the make command line, not here.

--std=1800-2017
--timescale=1ns/1ps
-Wextra
-Werror
