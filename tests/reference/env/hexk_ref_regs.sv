// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_regs.sv
//
// Register model of the reference DUT: the map of the comment at the top of hexk_ref_dut.sv as a
// uvm_reg_block. One register class serves every register; the block adds the fields. Fields
// that the DUT changes by itself are volatile, so that the mirror does not pretend to know them
// and hexk_csr_util leaves them out of the reset check. The 64 words of the RAM are 64 registers
// without a reset value.
// REG-1 waived: the model is written by hand, because this repository has no register generator;
// a project generates it from the specification of its registers.

`ifndef HEXK_REF_REGS_SV
`define HEXK_REF_REGS_SV

// The register block: every register of the DUT and the 64 words of its RAM, in one map.
class hexk_ref_regs extends uvm_reg_block;

   // Number of words of the RAM, and the address of the first one.
   localparam int unsigned MEM_WORDS = 64;
   localparam int unsigned MEM_BASE = 'h100;

   // Byte offsets of the registers, as in the register map at the top of hexk_ref_dut.sv.
   localparam int unsigned ID_OFFSET = 'h00;
   localparam int unsigned CTRL_OFFSET = 'h04;
   localparam int unsigned BASE_OFFSET = 'h08;
   localparam int unsigned STATUS_OFFSET = 'h0C;
   localparam int unsigned IRQ_OFFSET = 'h10;
   localparam int unsigned CRC_OFFSET = 'h14;
   localparam int unsigned CYCLES_OFFSET = 'h18;
   localparam int unsigned ERR_OFFSET = 'h1C;
   localparam int unsigned DEBUG_OFFSET = 'h20;
   localparam int unsigned INJ_LO_OFFSET = 'h24;
   localparam int unsigned INJ_HI_OFFSET = 'h28;
   localparam int unsigned INJ_CTRL_OFFSET = 'h2C;
   localparam int unsigned RAW_ADDR_OFFSET = 'h30;
   localparam int unsigned RAW_LO_OFFSET = 'h34;
   localparam int unsigned RAW_HI_OFFSET = 'h38;

   // The registers, named as in the register map; ident is ID. mem[i] is word i of the RAM.
   hexk_ref_reg  ident;
   hexk_ref_reg  ctrl;
   hexk_ref_reg  base;
   hexk_ref_reg  status;
   hexk_ref_reg  irq;
   hexk_ref_reg  crc;
   hexk_ref_reg  cycles;
   hexk_ref_reg  err;
   hexk_ref_reg  debug;
   hexk_ref_reg  inj_lo;
   hexk_ref_reg  inj_hi;
   hexk_ref_reg  inj_ctrl;
   hexk_ref_reg  raw_addr;
   hexk_ref_reg  raw_lo;
   hexk_ref_reg  raw_hi;
   hexk_ref_reg  mem                [MEM_WORDS];

   // The fields that the tests use by name.
   uvm_reg_field ctrl_en;
   uvm_reg_field ctrl_scramble;
   uvm_reg_field ctrl_irq_en;
   uvm_reg_field ctrl_len;
   uvm_reg_field irq_done;
   uvm_reg_field status_busy;
   uvm_reg_field status_pkt_count;
   uvm_reg_field err_corrected;
   uvm_reg_field err_uncorrectable;
   uvm_reg_field debug_corrupt_read;
   uvm_reg_field debug_hang;

   `uvm_object_utils(hexk_ref_regs)

   // Creates the block; build() fills it.
   function new(string name = "hexk_ref_regs");
      super.new(name, UVM_NO_COVERAGE);
   endfunction : new

   // Creates the registers and their fields and maps them; a derived block may add registers after super.build().
   // The environment locks the model when build() returns.
   virtual function void build();
      uvm_reg_field unused;
      default_map        = create_map("map", 0, 4, UVM_LITTLE_ENDIAN, 1);
      ident              = new_reg("id", ID_OFFSET, "RO");
      unused             = ident.new_field("value", 32, 0, "RO", 'h4845_5852);
      ctrl               = new_reg("ctrl", CTRL_OFFSET, "RW");
      ctrl_en            = ctrl.new_field("en", 1, 0, "RW");
      ctrl_scramble      = ctrl.new_field("scramble", 1, 1, "RW");
      ctrl_irq_en        = ctrl.new_field("irq_en", 1, 2, "RW");
      ctrl_len           = ctrl.new_field("len", 4, 4, "RW", 4);
      base               = new_reg("base", BASE_OFFSET, "RW");
      unused             = base.new_field("base", 6, 0, "RW");
      status             = new_reg("status", STATUS_OFFSET, "RO");
      status_busy        = status.new_field("busy", 1, 0, "RO", 0, 1);
      status_pkt_count   = status.new_field("pkt_count", 8, 8, "RO", 0, 1);
      irq                = new_reg("irq", IRQ_OFFSET, "RW");
      irq_done           = irq.new_field("done", 1, 0, "W1C", 0, 1);
      crc                = new_reg("crc", CRC_OFFSET, "RO");
      unused             = crc.new_field("crc", 32, 0, "RO", 0, 1);
      cycles             = new_reg("cycles", CYCLES_OFFSET, "RO");
      unused             = cycles.new_field("cycles", 16, 0, "RO", 0, 1);
      err                = new_reg("err", ERR_OFFSET, "RO");
      err_corrected      = err.new_field("corrected", 8, 0, "RO", 0, 1);
      err_uncorrectable  = err.new_field("uncorrectable", 8, 8, "RO", 0, 1);
      debug              = new_reg("debug", DEBUG_OFFSET, "RW");
      debug_corrupt_read = debug.new_field("corrupt_read", 1, 0, "RW");
      debug_hang         = debug.new_field("hang", 1, 1, "RW");
      inj_lo             = new_reg("inj_lo", INJ_LO_OFFSET, "RW");
      unused             = inj_lo.new_field("mask", 32, 0, "RW");
      inj_hi             = new_reg("inj_hi", INJ_HI_OFFSET, "RW");
      unused             = inj_hi.new_field("mask", 7, 0, "RW");
      inj_ctrl           = new_reg("inj_ctrl", INJ_CTRL_OFFSET, "RW");
      unused             = inj_ctrl.new_field("arm", 1, 0, "RW", 0, 1);
      raw_addr           = new_reg("raw_addr", RAW_ADDR_OFFSET, "RW");
      unused             = raw_addr.new_field("addr", 6, 0, "RW");
      raw_lo             = new_reg("raw_lo", RAW_LO_OFFSET, "RO");
      unused             = raw_lo.new_field("code", 32, 0, "RO", 0, 1, 0);
      raw_hi             = new_reg("raw_hi", RAW_HI_OFFSET, "RO");
      unused             = raw_hi.new_field("code", 7, 0, "RO", 0, 1, 0);
      foreach (mem[i]) begin
         mem[i] = new_reg($sformatf("mem_%0d", i), MEM_BASE + 4 * i, "RW");
         unused = mem[i].new_field("data", 32, 0, "RW", 0, 1, 0);
      end
   endfunction : build

   // The register that holds a word of the RAM.
   function hexk_ref_reg mem_reg(int unsigned word);
      return mem[word%MEM_WORDS];
   endfunction : mem_reg

   // The value of CTRL with its fields: EN, LEN (16 is written as 0), IRQ_EN and SCRAMBLE.
   static function bit [31:0] ctrl_value(bit en, int unsigned len, bit irq_en, bit scramble = 0);
      return {24'd0, 4'(len), 1'b0, irq_en, scramble, en};
   endfunction : ctrl_value

   // Creates a register through the factory under the name of this block, configures it here and maps it.
   protected function hexk_ref_reg new_reg(string reg_name, uvm_reg_addr_t offset, string rights);
      hexk_ref_reg rg = hexk_ref_reg::type_id::create(reg_name, null, get_full_name());
      rg.configure(this);
      default_map.add_reg(rg, offset, rights);
      return rg;
   endfunction : new_reg

endclass : hexk_ref_regs

`endif  // HEXK_REF_REGS_SV
