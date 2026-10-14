# examples/hexk_mem_model

`hexk_mem_model_example.sv` models a RAM with 32-bit words and byte enables: a write of a
word, a write of two of its bytes, reads of a word and of a byte, a read of a word that was
never written under two policies, an access outside the legal range, and a copy of the
content into a second memory through a `$readmemh` file. It writes the file
`hexk_mem_model_example.hex` into the directory of the simulation. It needs UVM and the UVM
filelist (`src/uvm/hexk_uvm.f`).
