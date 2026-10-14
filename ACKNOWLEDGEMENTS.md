# Acknowledgements

hexk-sv-lib is written clean-room: **no code is copied** from any of the projects below or
from anywhere else. They are credited because they showed which utilities a verification
library needs and which ideas work in practice. Each module is written from its own
specification, the contract in `docs/api/`, alone.

| Project | Ideas | Link | License |
|---|---|---|---|
| OpenTitan DV libraries | check macros with fatal variants, spin-wait and timeout macros, report catcher by ID, enum plusargs, string helpers, sparse memory model, clock/reset interface | <https://github.com/lowRISC/opentitan> | Apache-2.0 |
| OpenHW core-v-verif | heartbeat monitor, scoreboard modes, report servers | <https://github.com/openhwgroup/core-v-verif> | see the repository |
| SVUnit | unit-test framework used for the self-tests; changelog and versioning practice | <https://github.com/svunit/svunit> | Apache-2.0 |
| PULP common_verification | simulation timeout and stream watchdog, random ready/valid drivers | <https://github.com/pulp-platform/common_verification> | see the repository |
| Verilab svlib | string and path helpers | <https://www.verilab.com/resources/svlib/> | see the project page |
| AMIQ SVAUnit | testing the assertions of an interface | <https://github.com/amiq-consulting/svaunit> | see the repository |

The licenses in the table are stated where the project publishes a machine-readable license
identifier; for the others, read the license file of the project.

SVUnit and UVM are external test and run-time dependencies. They are not vendored into this
repository.
