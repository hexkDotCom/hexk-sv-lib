// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_mem_model.sv
//
// Sparse memory model for reference models and scoreboards: write() and read() of data
// words at byte addresses, with byte enables, in a memory of up to 2**ADDR_WIDTH bytes of
// which only the bytes that were written take space.
// The storage is one byte per address, so accesses of different widths, unaligned accesses
// and partial writes all see the same memory. A word is DATA_WIDTH bits, a multiple of 8;
// big_endian selects which byte of a word has the lowest address. uninit_policy says what a
// read of a byte that was never written returns, and whether it is an error. load_hex() and
// dump_hex() read and write files in the format of $readmemh.
//
//! @module    hexk_mem_model
//! @since     0.7.0
//! @stability experimental
//! @emits     HEXK_MEM_UNINIT:error HEXK_MEM_RANGE:error HEXK_MEM_FILE:error HEXK_MEM_WIDTH:error
//! @emits     HEXK_MEM_UNKNOWN:error
//! @emits     HEXK_MEM_SUMMARY:info HEXK_COPY_TYPE:fatal
//! @plusargs  (none)

`ifndef HEXK_MEM_MODEL_SV
`define HEXK_MEM_MODEL_SV

// What a read of a byte that was never written does.
typedef enum bit [2:0] {
   // Reports an error and returns X.
   HEXK_MEM_UNINIT_ERROR,
   // Returns a random value that is the same at every read of that address.
   HEXK_MEM_UNINIT_RANDOM,
   // Returns 0.
   HEXK_MEM_UNINIT_ZERO,
   // Returns the byte uninit_pattern.
   HEXK_MEM_UNINIT_PATTERN,
   // Returns X without a message.
   HEXK_MEM_UNINIT_X
} hexk_mem_uninit_e;

class hexk_mem_model #(
    int ADDR_WIDTH = 64,
    int DATA_WIDTH = 32
) extends uvm_object implements hexk_checkable;

   // Number of bytes of a word.
   localparam int unsigned WORD_BYTES = DATA_WIDTH / 8;

   // Hash of a never-written address for HEXK_MEM_UNINIT_RANDOM: the address bits are folded into a word of
   // HASH_WORD_BITS bits, which is rotated by HASH_ROTATE bits and mixed with HASH_MIX after each word.
   localparam int unsigned HASH_WORD_BITS = 32;
   // Rotation of the hash word, in bits.
   localparam int unsigned HASH_ROTATE = 5;
   // Constant mixed into the hash word.
   localparam bit [31:0] HASH_MIX = 32'h9E37_79B9;

   // Four-state, so that an address or a byte enable with an X or Z bit, as a monitor may see it, is noticed.
   typedef logic [ADDR_WIDTH-1:0] addr_t;
   typedef logic [DATA_WIDTH-1:0] data_t;
   typedef logic [DATA_WIDTH/8-1:0] strobe_t;
   // The address of a stored byte, after the check for X and Z; internal.
   typedef bit [ADDR_WIDTH-1:0] index_t;
   // Wide enough for an address or a word read from a file.
   typedef logic [ADDR_WIDTH+DATA_WIDTH-1:0] file_value_t;
   // Wide enough for the byte address of any word of a file, also of one beyond the address space.
   typedef bit [ADDR_WIDTH+DATA_WIDTH:0] file_addr_t;

   // What a read of a byte that was never written does.
   hexk_mem_uninit_e            uninit_policy            = HEXK_MEM_UNINIT_ERROR;

   // The byte that policy HEXK_MEM_UNINIT_PATTERN returns.
   logic                  [7:0] uninit_pattern           = 8'hA5;

   // When 1, the most significant byte of a word has the lowest address; when 0, the least significant.
   bit                          big_endian               = 0;

   // Seed of the values of policy HEXK_MEM_UNINIT_RANDOM.
   int unsigned                 seed;

   // The written bytes by address.
   local logic            [7:0] bytes         [index_t];

   // Address limits of set_range(), and whether they are in use.
   local bit                    has_range;
   local index_t                range_lo;
   local index_t                range_hi;

   // Number of reads that touched a byte that was never written.
   local int unsigned           uninit_reads;

   // Set when the widths make no usable memory (HEXK_MEM_WIDTH); every access is then refused.
   local bit                    unusable;

   local hexk_rand_stream       stream;

   `uvm_object_param_utils(hexk_mem_model#(.ADDR_WIDTH(ADDR_WIDTH),
                                           .DATA_WIDTH(DATA_WIDTH)))

   // Name of the class in messages and printouts; without it UVM has none for a class with parameters.
   function string get_type_name();
      return "hexk_mem_model";
   endfunction : get_type_name

   // Creates an empty memory; the seed of the random policy is derived from the name.
   function new(string name = "hexk_mem_model");
      super.new(name);
      stream = new(name);
      seed   = uvm_create_random_seed("hexk_mem_model", name);
      if (DATA_WIDTH < 8 || (DATA_WIDTH % 8) != 0) begin
         `uvm_error("HEXK_MEM_WIDTH",
                    $sformatf("DATA_WIDTH is %0d; it must be a multiple of 8; every access is refused", DATA_WIDTH))
         unusable = 1;
      end else if (ADDR_WIDTH < 1 || (ADDR_WIDTH < 32 && (64'd1 << ADDR_WIDTH) < 64'(WORD_BYTES))) begin
         `uvm_error(
             "HEXK_MEM_WIDTH",
             $sformatf("ADDR_WIDTH is %0d: a word of %0d bytes does not fit the address space; every access is refused",
                       ADDR_WIDTH, WORD_BYTES))
         unusable = 1;
      end
   endfunction : new

   // UVM hook of copy() and clone(): a snapshot of the bytes, the settings, the range and the counter of reads of
   // bytes that were never written; afterwards the two memories are independent.
   function void do_copy(uvm_object rhs);
      hexk_mem_model #(ADDR_WIDTH, DATA_WIDTH) other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_fatal("HEXK_COPY_TYPE", $sformatf("%s cannot copy from %s, which is a %s", get_type_name(),
                                                rhs.get_name(), rhs.get_type_name()))
         return;
      end
      uninit_policy  = other.uninit_policy;
      uninit_pattern = other.uninit_pattern;
      big_endian     = other.big_endian;
      seed           = other.seed;
      bytes          = other.bytes;
      has_range      = other.has_range;
      range_lo       = other.range_lo;
      range_hi       = other.range_hi;
      uninit_reads   = other.uninit_reads;
      unusable       = other.unusable;
   endfunction : do_copy

   // Limits the legal addresses to lo..hi; an access outside is an error and is not carried out.
   function void set_range(addr_t lo, addr_t hi);
      if (!is_known(lo, "set_range") || !is_known(hi, "set_range")) begin
         return;
      end
      has_range = 1;
      range_lo  = lo;
      range_hi  = hi;
   endfunction : set_range

   // Writes the bytes of a word whose byte enable is set; addr is the address of the first byte of the word.
   function void write(addr_t addr, data_t data, strobe_t byte_en = '1);
      if (!is_known(addr, "write") || !is_legal(addr, WORD_BYTES, "write")) begin
         return;
      end
      if ($isunknown(byte_en)) begin
         `uvm_error("HEXK_MEM_UNKNOWN", $sformatf("%s: write at address 0x%0h with X or Z in the byte enable 'b%b; %s",
                                                  get_name(), addr, byte_en, "not carried out"))
         return;
      end
      for (int unsigned lane = 0; lane < WORD_BYTES; lane++) begin
         if (byte_en[lane]) begin
            bytes[lane_addr(addr, lane)] = data[8*lane+:8];
         end
      end
   endfunction : write

   // Reads a word; bytes that were never written follow uninit_policy.
   function data_t read(addr_t addr);
      data_t data = 'x;
      bit    missing = 0;
      if (!is_known(addr, "read") || !is_legal(addr, WORD_BYTES, "read")) begin
         return data;
      end
      for (int unsigned lane = 0; lane < WORD_BYTES; lane++) begin
         data[8*lane+:8] = byte_at(lane_addr(addr, lane), missing);
      end
      note_uninit_read(addr, missing);
      return data;
   endfunction : read

   // Writes one byte.
   function void write_byte(addr_t byte_addr, logic [7:0] data);
      if (is_known(byte_addr, "write") && is_legal(byte_addr, 1, "write")) begin
         bytes[byte_addr] = data;
      end
   endfunction : write_byte

   // Reads one byte; a byte that was never written follows uninit_policy.
   function logic [7:0] read_byte(addr_t byte_addr);
      logic [7:0] data = 'x;
      bit         missing = 0;
      if (is_known(byte_addr, "read") && is_legal(byte_addr, 1, "read")) begin
         data = byte_at(byte_addr, missing);
         note_uninit_read(byte_addr, missing);
      end
      return data;
   endfunction : read_byte

   // 1 when every byte of the word at addr was written; 0 for a word that does not fit below the top address.
   function bit is_written(addr_t addr);
      if (unusable || !is_known(addr, "is_written") || !fits_below_top(addr, WORD_BYTES)) begin
         return 0;
      end
      for (int unsigned lane = 0; lane < WORD_BYTES; lane++) begin
         if (!bytes.exists(index_t'(addr) + index_t'(lane))) begin
            return 0;
         end
      end
      return 1;
   endfunction : is_written

   // Number of bytes that were written.
   function int unsigned num_written();
      return bytes.num();
   endfunction : num_written

   // Number of reads so far that touched a byte that was never written.
   function int unsigned num_uninit_reads();
      return uninit_reads;
   endfunction : num_uninit_reads

   // Forgets every written byte and the count of uninitialised reads.
   function void clear();
      bytes.delete();
      uninit_reads = 0;
   endfunction : clear

   // Loads a file in the format of $readmemh with words of DATA_WIDTH bits; word n goes to base + n * WORD_BYTES.
   function void load_hex(string file, addr_t base = 0);
      int          handle;
      string       line;
      string       tokens              [$];
      file_addr_t  word_index = 0;
      file_addr_t  byte_addr;
      file_value_t word;
      bit          in_comment = 0;
      bit          has_xz;
      bit          beyond_reported = 0;
      int          line_number = 0;
      if (!is_known(base, "load_hex")) begin
         return;
      end
      handle = $fopen(file, "r");
      if (handle == 0) begin
         `uvm_error("HEXK_MEM_FILE", $sformatf("%s cannot be opened for reading", file))
         return;
      end
      while ($fgets(
          line, handle
      ) != 0) begin
         line_number++;
         // A tab and the end of a line separate tokens like a blank; a file from Windows ends its lines with CR LF.
         // The language has no escape sequence for CR: it is written as the octal code.
         line = hexk_str::replace(hexk_str::replace(hexk_str::replace(line, "\t", " "), "\015", " "), "\n", " ");
         hexk_str::split(strip_comments(line, in_comment), tokens, " ");
         foreach (tokens[i]) begin
            if (tokens[i].len() == 0) begin
               continue;
            end
            if (tokens[i][0] == "@") begin
               if (!parse_hex(
                       tokens[i].substr(1, tokens[i].len() - 1), ADDR_WIDTH, word, has_xz
                   ) || has_xz || (word >> ADDR_WIDTH) != 0) begin
                  `uvm_error("HEXK_MEM_FILE", $sformatf("%s line %0d: '%s' is not an address", file, line_number,
                                                        tokens[i]))
                  continue;
               end
               word_index      = file_addr_t'(word);
               beyond_reported = 0;
            end else begin
               // In a type wider than an address, so that a word beyond the address space is seen and not wrapped.
               byte_addr = file_addr_t'(base) + word_index * file_addr_t'(WORD_BYTES);
               if (!parse_hex(tokens[i], DATA_WIDTH, word, has_xz)) begin
                  `uvm_error("HEXK_MEM_FILE", $sformatf("%s line %0d: '%s' is not a hexadecimal word of %0d bits",
                                                        file, line_number, tokens[i], DATA_WIDTH))
               end else if ((byte_addr >> ADDR_WIDTH) != 0) begin
                  // Reported for the first word only; an address in the file starts a new report.
                  if (!beyond_reported) begin
                     `uvm_error("HEXK_MEM_FILE",
                                $sformatf("%s line %0d: word 0x%0h is beyond the address space of %0d bits; %s", file,
                                          line_number, word_index, ADDR_WIDTH,
                                          "it and the words that follow it are not loaded"))
                     beyond_reported = 1;
                  end
               end else begin
                  load_word(byte_addr, data_t'(word), x_lanes(tokens[i]), file, line_number, word_index);
               end
               word_index++;
            end
         end
      end
      $fclose(handle);
   endfunction : load_hex

   // Writes the written words to a file in the format of $readmemh; a byte that was never written, and a byte of
   // the last word that would be beyond the top address, is "xx".
   function void dump_hex(string file);
      int         handle = $fopen(file, "w");
      // Word numbers and byte addresses in a type wider than an address: WORD_BYTES need not fit an address, and
      // the last word may run past the top address.
      file_addr_t word_index;
      file_addr_t word_start;
      file_addr_t lane_byte;
      file_addr_t next_index = 0;
      bit         first = 1;
      bit         missing;
      string      text;
      if (handle == 0) begin
         `uvm_error("HEXK_MEM_FILE", $sformatf("%s cannot be opened for writing", file))
         return;
      end
      foreach (bytes[addr]) begin
         word_index = file_addr_t'(addr) / file_addr_t'(WORD_BYTES);
         word_start = word_index * file_addr_t'(WORD_BYTES);
         // The bytes come in rising order: a word is written when its first written byte is seen.
         if (!first && word_index < next_index) begin
            continue;
         end
         if (first || word_index != next_index) begin
            $fdisplay(handle, "@%0h", word_index);
         end
         text = "";
         for (int lane = int'(WORD_BYTES) - 1; lane >= 0; lane--) begin
            lane_byte = file_lane_addr(word_start, $unsigned(lane));
            missing   = (lane_byte >> ADDR_WIDTH) != 0 || !bytes.exists(index_t'(lane_byte));
            text      = {text, missing ? "xx" : $sformatf("%02h", bytes[index_t'(lane_byte)])};
         end
         $fdisplay(handle, "%s", text);
         next_index = word_index + 1;
         first      = 0;
      end
      $fclose(handle);
   endfunction : dump_hex

   // What the memory holds, on one line.
   function string convert2string();
      // A string variable and not ?: of two literals in the arguments, where the literals are packed values and the
      // shorter one is padded with NULs.
      string order = "little";
      if (big_endian) begin
         order = "big";
      end
      return $sformatf(
          "%0d bytes written, %0d reads of bytes that were never written, policy %s, %s endian",
          bytes.num(),
          uninit_reads,
          uninit_policy.name(),
          order
      );
   endfunction : convert2string

   // hexk_checkable: reports what the memory holds at the end of the test; a derived class adds its checks.
   virtual function void eot_check();
      `uvm_info("HEXK_MEM_SUMMARY", {get_name(), ": ", convert2string()}, UVM_MEDIUM)
   endfunction : eot_check

   // Address of the byte that holds bits 8*lane+7..8*lane of the word at addr.
   local function index_t lane_addr(index_t addr, int unsigned lane);
      int unsigned offset = big_endian ? (WORD_BYTES - 1 - lane) : lane;
      return addr + index_t'(offset);
   endfunction : lane_addr

   // As lane_addr, for a word of a file: in a type wider than an address, so that a byte beyond the top address
   // is seen and does not wrap to a low address.
   local function file_addr_t file_lane_addr(file_addr_t start, int unsigned lane);
      int unsigned offset = big_endian ? (WORD_BYTES - 1 - lane) : lane;
      return start + file_addr_t'(offset);
   endfunction : file_lane_addr

   // Writes a word of a file whose first byte is below the top address, except the lanes in skip. A word that runs
   // past the top address is written byte by byte up to the top; a lane beyond the top that is not in skip is the
   // error HEXK_MEM_FILE.
   local function void load_word(file_addr_t start, data_t data, strobe_t skip, string file, int line_number,
                                 file_addr_t word_index);
      strobe_t    lanes = ~skip;
      file_addr_t lane_byte;
      bit         beyond = 0;
      if (fits_below_top(index_t'(start), WORD_BYTES)) begin
         if (lanes != '0) begin
            write(addr_t'(start), data, lanes);
         end
         return;
      end
      for (int unsigned lane = 0; lane < WORD_BYTES; lane++) begin
         lane_byte = file_lane_addr(start, lane);
         if (!lanes[lane]) begin
            continue;
         end
         if ((lane_byte >> ADDR_WIDTH) != 0) begin
            beyond = 1;
         end else begin
            write_byte(addr_t'(lane_byte), data[8*lane+:8]);
         end
      end
      if (beyond) begin
         `uvm_error("HEXK_MEM_FILE",
                    $sformatf(
                        "%s line %0d: word 0x%0h has bytes beyond the top address of %0d bits that are not xx; %s",
                        file, line_number, word_index, ADDR_WIDTH, "they are not loaded, the bytes below the top are"))
      end
   endfunction : load_word

   // The lanes of a word of a file whose two hexadecimal digits are both x, as dump_hex writes a byte that was
   // never written. A digit that the word does not have is its first digit when that is x, else 0, as in
   // $readmemh. Taken from the text, so that it works also where variables have two states.
   local function strobe_t x_lanes(string text);
      string   digits = "";
      bit      fill_x;
      strobe_t lanes = '0;
      foreach (text[i]) begin
         if (text[i] != "_") begin
            digits = {digits, text.substr(i, i)};
         end
      end
      fill_x = digits.len() != 0 && (digits[0] == "x" || digits[0] == "X");
      for (int unsigned lane = 0; lane < WORD_BYTES; lane++) begin
         lanes[lane] = is_x_digit(digits, 2 * lane, fill_x) && is_x_digit(digits, 2 * lane + 1, fill_x);
      end
      return lanes;
   endfunction : x_lanes

   // 1 when the digit at position from_right (0 is the last digit) is x; fill_x for a digit beyond the first.
   local function bit is_x_digit(string digits, int unsigned from_right, bit fill_x);
      byte c;
      if (from_right >= digits.len()) begin
         return fill_x;
      end
      c = digits[digits.len()-1-from_right];
      return c == "x" || c == "X";
   endfunction : is_x_digit

   // The byte at an address, by uninit_policy when it was never written; missing is set for such a byte.
   local function logic [7:0] byte_at(index_t addr, ref bit missing);
      int unsigned folded = seed;
      if (bytes.exists(addr)) begin
         return bytes[addr];
      end
      missing = 1;
      case (uninit_policy)
         HEXK_MEM_UNINIT_ZERO:    return 8'h00;
         HEXK_MEM_UNINIT_PATTERN: return uninit_pattern;
         HEXK_MEM_UNINIT_RANDOM: begin
            // The value depends on the seed and the address only, so every read of an address returns the same.
            for (int unsigned i = 0; i < ADDR_WIDTH; i++) begin
               folded[i%HASH_WORD_BITS] = folded[i%HASH_WORD_BITS] ^ addr[i];
               if (i % HASH_WORD_BITS == HASH_WORD_BITS - 1) begin
                  folded = (folded << HASH_ROTATE) ^ (folded >> (HASH_WORD_BITS - HASH_ROTATE)) ^ HASH_MIX;
               end
            end
            folded = (folded << HASH_ROTATE) ^ (folded >> (HASH_WORD_BITS - HASH_ROTATE)) ^ HASH_MIX;
            stream.seed(folded);
            return 8'(stream.next_u32());
         end
         default:                 return 8'hxx;
      endcase
   endfunction : byte_at

   // Counts a read that touched a byte that was never written, and reports it under policy HEXK_MEM_UNINIT_ERROR.
   local function void note_uninit_read(index_t addr, bit missing);
      if (!missing) begin
         return;
      end
      uninit_reads++;
      if (uninit_policy == HEXK_MEM_UNINIT_ERROR) begin
         `uvm_error("HEXK_MEM_UNINIT", $sformatf("%s: read at address 0x%0h touches a byte that was never written",
                                                 get_name(), addr))
      end
   endfunction : note_uninit_read

   // 1 when the address has no X or Z bit; otherwise the error HEXK_MEM_UNKNOWN, and the access is not carried out.
   local function bit is_known(addr_t addr, string access);
      if (!$isunknown(addr)) begin
         return 1;
      end
      `uvm_error("HEXK_MEM_UNKNOWN", $sformatf(
                 "%s: %s at address 'h%h, which has X or Z bits; not carried out", get_name(), access, addr))
      return 0;
   endfunction : is_known

   // 1 when the bytes addr..addr+size-1 are all at or below the top address; computed in a type wider than an
   // address, so that a span larger than the address space is not cut short.
   local function bit fits_below_top(index_t addr, int unsigned size);
      int unsigned span = size - 1;
      file_addr_t  last = file_addr_t'(addr) + file_addr_t'(span);
      return (last >> ADDR_WIDTH) == 0;
   endfunction : fits_below_top

   // 1 when the bytes addr..addr+size-1 exist and are inside the range of set_range(), if one is set.
   // An access that would go on at address 0 after the top address is never legal.
   local function bit is_legal(index_t addr, int unsigned size, string access);
      int unsigned span = size - 1;
      index_t      last = addr + index_t'(span);
      if (unusable) begin
         return 0;
      end
      if (!fits_below_top(addr, size)) begin
         `uvm_error(
             "HEXK_MEM_RANGE",
             $sformatf("%s: %s of %0d bytes at address 0x%0h goes beyond the top address of %0d bits; not carried out",
                       get_name(), access, size, addr, ADDR_WIDTH))
         return 0;
      end
      if (!has_range || (addr >= range_lo && last <= range_hi)) begin
         return 1;
      end
      `uvm_error("HEXK_MEM_RANGE", $sformatf(
                 "%s: %s of %0d bytes at address 0x%0h is outside 0x%0h to 0x%0h; not carried out",
                 get_name(),
                 access,
                 size,
                 addr,
                 range_lo,
                 range_hi
                 ))
      return 0;
   endfunction : is_legal

   // Removes // and block comments from a line; in_comment carries an open block comment to the next line.
   // A block comment leaves a blank: it separates two tokens, as in $readmemh.
   local function string strip_comments(string line, ref bit in_comment);
      string kept;
      int    i = 0;
      byte   c;
      byte   following;
      while (i < line.len()) begin
         c         = line[i];
         following = (i + 1 < line.len()) ? line[i+1] : 8'h00;
         if (in_comment) begin
            if (c == "*" && following == "/") begin
               in_comment = 0;
               i++;
            end
         end else if (c == "/" && following == "*") begin
            in_comment = 1;
            kept       = {kept, " "};
            i++;
         end else if (c == "/" && following == "/") begin
            break;
         end else begin
            kept = {kept, string'(c)};
         end
         i++;
      end
      return kept;
   endfunction : strip_comments

   // Converts hexadecimal text with optional x, z and _ to a value of the given width; 0 when it is not such text.
   // Text with fewer digits than the width is extended with 0, or with x or z when that is its first digit, as
   // in $readmemh. has_xz says whether the text has an x or z digit, which a two-state simulator does not keep
   // in the value.
   local function bit parse_hex(string text, int unsigned width, output file_value_t value, output bit has_xz);
      int unsigned       digits = 0;
      logic        [3:0] nibble;
      logic              fill = 1'b0;
      value  = '0;
      has_xz = 0;
      for (int i = 0; i < text.len(); i++) begin
         byte c = text[i];
         if (c == "_") begin
            continue;
         end
         if (c >= "0" && c <= "9") begin
            nibble = 4'(c - "0");
         end else if (c >= "a" && c <= "f") begin
            nibble = 4'(c - "a") + 4'd10;
         end else if (c >= "A" && c <= "F") begin
            nibble = 4'(c - "A") + 4'd10;
         end else if (c == "x" || c == "X") begin
            nibble = 4'bxxxx;
            has_xz = 1;
         end else if (c == "z" || c == "Z" || c == "?") begin
            nibble = 4'bzzzz;
            has_xz = 1;
         end else begin
            return 0;
         end
         if (digits == 0 && $isunknown(nibble)) begin
            fill = nibble[3];
         end
         digits++;
         value = file_value_t'({value, nibble});
      end
      for (int unsigned i = digits * 4; i < width; i++) begin
         value[i] = fill;
      end
      return digits != 0 && digits * 4 <= width + 3;
   endfunction : parse_hex

endclass : hexk_mem_model

`endif  // HEXK_MEM_MODEL_SV
