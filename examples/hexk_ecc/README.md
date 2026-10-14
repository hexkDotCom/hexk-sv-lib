# examples/hexk_ecc

`hexk_ecc_example.sv` encodes a 32-bit word with the check bits above the data, reads it
back with one flipped bit (corrected) and with two flipped bits (reported). It needs the core
filelist only (`src/core/hexk_core.f`).
