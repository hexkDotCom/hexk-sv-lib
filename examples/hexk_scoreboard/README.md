# examples/hexk_scoreboard

`hexk_scoreboard_example.sv` checks responses that a DUT returns out of order: a scoreboard
class with two small hooks matches them by their tag, holds the run phase until the last one
has arrived and prints a summary. It needs UVM and the UVM filelist (`src/uvm/hexk_uvm.f`).

`hexk_scoreboard_predictor_example.sv` puts a predictor in front of the scoreboard: the DUT
takes requests and returns responses of another type, the predictor turns each request into
the response it expects, `hexk_meta_item` carries the time and the ID of the request to the
scoreboard, and a reset in the middle of the traffic empties the scoreboard with
`on_reset()`. It needs the same files.
