# Contributing

hexk-sv-lib does not accept external pull requests. All code is written by HEXK, so that the
provenance of every line stays clear (clean-room rule, see `ACKNOWLEDGEMENTS.md`).

## Pull requests

Pull requests are not accepted and are closed without review. This is a policy about
provenance and licensing, not a judgement of the change.

## Issues and Discussions

Issues are welcome for bug reports and for requests for a module or an API change;
questions, opinions and general ideas go to Discussions. A useful bug report has:

- the library version (`VERSION`, or `HEXK_VERSION_STR` from your log),
- the simulator and its version, and the UVM version (1.2 or IEEE 1800.2),
- the smallest code that shows the problem, and what you expected to happen.

Please describe the problem and the behaviour you want; do not paste code from other
libraries or from your employer's code base as a proposed fix.

A finding from a code review or from an AI assistant is welcome too. If you have not
reproduced it in a simulation yet, post it in Discussions rather than as an issue; once it
is reproduced, it becomes an issue.

## Your own modifications

The Apache-2.0 license lets you modify and redistribute the library. If you need the library
under another prefix (company naming policy, or two versions in one simulation),
`scripts/hexk_rebrand.py --prefix <name>` writes a copy with that prefix; see "Another prefix"
in `docs/integration.md`.
