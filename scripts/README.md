# scripts

| Script | Purpose | Make target |
|---|---|---|
| `hexk_style_check.py` | library style rules that Verible does not cover | `make style_check` |
| `hexk_rebrand.py` | `--check`: rebrandable-prefix rules; `--prefix <name>`: a copy of the repository with another prefix | `make rebrand_check` |
| `hexk_gen_api_docs.py` | generate and check `docs/api/*.md` | `make docs` |
| `hexk_gen_version.py` | write the files derived from `VERSION` | `make version` |
| `hexk_slang.py` | slang command line on top of the `pyslang` package | `make elab` |
| `hexk_example_run.do` | Questa commands that run one example and tell whether it ended by itself | `make examples` |
| `hexk_core_errors.awk` | the `$error` messages of the core in a log of unit tests, per suite, for Verilator, Questa and VCS | `make test` |
| `hexk_check_run.py` | how a run of a testbench on `hexk_base_test` ended, against what it must end with; `--check-list` checks a list of runs ([docs/regression.md](../docs/regression.md)) | `make reference` |

The Python scripts need Python 3.8 or newer; only `hexk_slang.py` needs a third-party package
(`pyslang`). `hexk_example_run.do` runs in Questa; `hexk_core_errors.awk` in any POSIX `awk`.
