// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_str.sv
//
// String utilities as static functions: split and join, strip, search, replace, pad,
// truncate, path and scope helpers, digit-run helpers, natural ordering and hex dumps.
// Call them as hexk_str::split(...); the class is abstract and never constructed. No DPI
// and no UVM, so everything also works in modules, interfaces and on Verilator.
// Characters are bytes: the functions are meant for ASCII text such as names, paths and
// messages. Positions are 0-based; a position of -1 means "not found".
//
//! @module    hexk_str
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_STR_SV
`define HEXK_STR_SV

virtual class hexk_str;

   // Default character set of strip, lstrip and rstrip: space, tab, newline, carriage return.
   localparam string WHITESPACE = " \t\n\x0d";

   // Base of the digit runs handled by get_numbers, denumber and natural_cmp.
   localparam int unsigned DECIMAL_BASE = 10;

   // Text that simplify_typename removes from the front of a type name.
   localparam string CLASS_KEYWORD = "class ";

   // Text from which simplify_typename cuts a type name.
   localparam string EXTENDS_KEYWORD = " extends ";

   // Number of blanks in the run that pad cuts its filling from.
   localparam int unsigned BLANK_RUN = 64;

   // A run of BLANK_RUN blanks: pad takes a slice of it, one operation instead of one concatenation per blank.
   local static string blanks = "                                                                ";

   // Splits s at every sep into parts (cleared first), keeping empty fields; max_parts 0 means no limit.
   static function void split(string s, ref string parts[$], input byte sep = " ", input int unsigned max_parts = 0);
      int start;
      parts.delete();
      if (s.len() == 0) begin
         return;
      end
      for (int i = 0; i < s.len(); i++) begin
         if (s[i] == sep && (max_parts == 0 || $unsigned(parts.size()) + 1 < max_parts)) begin
            parts.push_back(s.substr(start, i - 1));
            start = i + 1;
         end
      end
      parts.push_back(s.substr(start, s.len() - 1));
   endfunction : split

   // Returns the parts concatenated with sep between them.
   static function string join_str(const ref string parts[$], input string sep = " ");
      string result;
      foreach (parts[i]) begin
         if (i != 0) begin
            result = {result, sep};
         end
         result = {result, parts[i]};
      end
      return result;
   endfunction : join_str

   // Removes leading and trailing characters that are in chars.
   static function string strip(string s, string chars = WHITESPACE);
      return rstrip(lstrip(s, chars), chars);
   endfunction : strip

   // Removes leading characters that are in chars.
   static function string lstrip(string s, string chars = WHITESPACE);
      int first;
      while (first < s.len()) begin
         if (!has_char(chars, s[first])) begin
            break;
         end
         first++;
      end
      return s.substr(first, s.len() - 1);
   endfunction : lstrip

   // Removes trailing characters that are in chars.
   static function string rstrip(string s, string chars = WHITESPACE);
      int last = s.len() - 1;
      while (last >= 0) begin
         if (!has_char(chars, s[last])) begin
            break;
         end
         last--;
      end
      return s.substr(0, last);
   endfunction : rstrip

   // True when s begins with prefix; an empty prefix always matches.
   static function bit starts_with(string s, string prefix);
      return prefix.len() <= s.len() && s.substr(0, prefix.len() - 1) == prefix;
   endfunction : starts_with

   // True when s ends with suffix; an empty suffix always matches.
   static function bit ends_with(string s, string suffix);
      return suffix.len() <= s.len() && s.substr(s.len() - suffix.len(), s.len() - 1) == suffix;
   endfunction : ends_with

   // True when sub occurs in s; an empty sub always does.
   static function bit contains(string s, string sub);
      return find(s, sub) >= 0;
   endfunction : contains

   // Position of the first occurrence of sub in s at or after start, or -1.
   static function int find(string s, string sub, int unsigned start = 0);
      int sub_len = sub.len();
      // Compared before any signed conversion: a start above the largest int would turn negative.
      if (start > $unsigned(s.len())) begin
         return -1;
      end
      if (sub_len == 0) begin
         return int'(start);
      end
      for (int i = int'(start); i + sub_len <= s.len(); i++) begin
         // The first character is compared alone, so a substring is made only where sub can begin.
         if (s[i] == sub[0] && s.substr(i, i + sub_len - 1) == sub) begin
            return i;
         end
      end
      return -1;
   endfunction : find

   // Position of the last occurrence of sub in s, or -1.
   static function int rfind(string s, string sub);
      int sub_len = sub.len();
      if (sub_len == 0) begin
         return s.len();
      end
      for (int i = s.len() - sub_len; i >= 0; i--) begin
         if (s[i] == sub[0] && s.substr(i, i + sub_len - 1) == sub) begin
            return i;
         end
      end
      return -1;
   endfunction : rfind

   // Replaces from by to, left to right without overlap; only the first occurrence when all is 0.
   static function string replace(string s, string from, string to, bit all = 1);
      string result;
      int rest;
      int hit;
      if (from.len() == 0) begin
         return s;
      end
      forever begin
         hit = find(s, from, $unsigned(rest));
         if (hit < 0) begin
            break;
         end
         result = {result, s.substr(rest, hit - 1), to};
         rest   = hit + from.len();
         if (!all) begin
            break;
         end
      end
      return {result, s.substr(rest, s.len() - 1)};
   endfunction : replace

   // Pads s with fill to width characters, on the left unless left_align is set; never shortens s.
   static function string pad(string s, int unsigned width, bit left_align = 0, byte fill = " ");
      string       filler;
      int unsigned missing;
      if ($unsigned(s.len()) >= width) begin
         return s;
      end
      missing = width - $unsigned(s.len());
      if (fill == " " && missing <= BLANK_RUN) begin
         filler = blanks.substr(0, int'(missing) - 1);
      end else begin
         filler = repeat_str(string'(fill), missing);
      end
      return left_align ? {s, filler} : {filler, s};
   endfunction : pad

   // Shortens s to max_len characters, marking the cut with ellipsis; keeps the right end if keep_right.
   static function string truncate(string s, int unsigned max_len, bit keep_right = 0, string ellipsis = "..");
      int length = s.len();
      int limit;
      int kept;
      // Compared before any signed conversion: a max_len above the largest int would turn negative.
      if ($unsigned(length) <= max_len) begin
         return s;
      end
      limit = int'(max_len);
      kept  = limit - ellipsis.len();
      if (kept <= 0) begin
         return keep_right ? s.substr(length - limit, length - 1) : s.substr(0, limit - 1);
      end
      return keep_right ? {ellipsis, s.substr(length - kept, length - 1)} : {s.substr(0, kept - 1), ellipsis};
   endfunction : truncate

   // Returns s repeated n times.
   static function string repeat_str(string s, int unsigned n);
      string       result;
      string       piece = s;
      int unsigned left = n;
      // The piece doubles at every step: about log2(n) concatenations instead of n.
      while (left != 0) begin
         if (left[0]) begin
            result = {result, piece};
         end
         left = left >> 1;
         if (left != 0) begin
            piece = {piece, piece};
         end
      end
      return result;
   endfunction : repeat_str

   // Last component of a "/"-separated path, as POSIX basename: "a/b/c.sv" gives "c.sv".
   static function string basename(string path);
      string trimmed = rstrip(path, "/");
      if (trimmed.len() == 0) begin
         return (path.len() == 0) ? "" : "/";
      end
      return trimmed.substr(rfind(trimmed, "/") + 1, trimmed.len() - 1);
   endfunction : basename

   // Path without its last component, as POSIX dirname: "a/b/c.sv" gives "a/b", "c.sv" gives ".".
   static function string dirname(string path);
      string trimmed = rstrip(path, "/");
      int slash = rfind(trimmed, "/");
      string dir;
      if (trimmed.len() == 0) begin
         return (path.len() == 0) ? "." : "/";
      end
      if (slash < 0) begin
         return ".";
      end
      dir = rstrip(trimmed.substr(0, slash - 1), "/");
      return (dir.len() == 0) ? "/" : dir;
   endfunction : dirname

   // Elements first to last (inclusive, 0-based, negative counts from the end) of a sep-separated scope.
   static function string scope_slice(string scope, int first, int last, byte sep = ".");
      string parts[$];
      string picked[$];
      int lo = first;
      int hi = last;
      split(scope, parts, sep);
      if (lo < 0) begin
         lo += parts.size();
      end
      if (hi < 0) begin
         hi += parts.size();
      end
      if (lo < 0) begin
         lo = 0;
      end
      if (hi >= parts.size()) begin
         hi = parts.size() - 1;
      end
      for (int i = lo; i <= hi; i++) begin
         picked.push_back(parts[i]);
      end
      return join_str(picked, string'(sep));
   endfunction : scope_slice

   // Collects every run of decimal digits in s as a number into nums (cleared first).
   static function void get_numbers(string s, ref longint unsigned nums[$]);
      longint unsigned value;
      bit in_run;
      nums.delete();
      foreach (s[i]) begin
         if (is_digit(s[i])) begin
            value  = (in_run ? value * DECIMAL_BASE : 0) + digit_value(s[i]);
            in_run = 1;
         end else if (in_run) begin
            nums.push_back(value);
            in_run = 0;
         end
      end
      if (in_run) begin
         nums.push_back(value);
      end
   endfunction : get_numbers

   // Replaces every run of decimal digits by placeholder: "agent_12.drv" gives "agent_#.drv".
   static function string denumber(string s, string placeholder = "#");
      string result;
      int copy_from;
      bit in_run;
      bit digit;
      foreach (s[i]) begin
         digit = is_digit(s[i]);
         if (digit && !in_run) begin
            result = {result, s.substr(copy_from, i - 1), placeholder};
         end
         if (!digit && in_run) begin
            copy_from = i;
         end
         in_run = digit;
      end
      if (!in_run) begin
         result = {result, s.substr(copy_from, s.len() - 1)};
      end
      return result;
   endfunction : denumber

   // Orders a before b (-1), after b (1) or equal (0), comparing digit runs as numbers: "a2" < "a10".
   static function int natural_cmp(string a, string b);
      int i;
      int j;
      int i_end;
      int j_end;
      int order;
      while (i < a.len() && j < b.len()) begin
         if (is_digit(a[i]) && is_digit(b[j])) begin
            i_end = digit_run_end(a, i);
            j_end = digit_run_end(b, j);
            order = compare_digit_runs(a.substr(i, i_end - 1), b.substr(j, j_end - 1));
            if (order != 0) begin
               return order;
            end
            i = i_end;
            j = j_end;
         end else begin
            if (a[i] != b[j]) begin
               return (a[i] < b[j]) ? -1 : 1;
            end
            i++;
            j++;
         end
      end
      if (i < a.len()) begin
         return 1;
      end
      if (j < b.len()) begin
         return -1;
      end
      // Same up to leading zeros ("a01" and "a1"): fall back to plain order so that only
      // identical strings compare equal.
      return sign_of(a.compare(b));
   endfunction : natural_cmp

   // Sorts list in natural order (see natural_cmp), descending when reverse is set; stable.
   static function void natural_sort(ref string list[$], input bit reverse = 0);
      string item;
      int slot;
      int direction = reverse ? -1 : 1;
      for (int i = 1; i < list.size(); i++) begin
         item = list[i];
         slot = i - 1;
         while (slot >= 0) begin
            if (natural_cmp(list[slot], item) * direction <= 0) begin
               break;
            end
            list[slot+1] = list[slot];
            slot--;
         end
         list[slot+1] = item;
      end
   endfunction : natural_sort

   // Hex dump of data: two lower-case digits per byte, space-separated, per_line bytes per line (0: one line).
   static function string bytes_to_hex(const ref byte unsigned data[$], input int unsigned per_line = 16);
      string result;
      foreach (data[i]) begin
         if (i != 0) begin
            result = {result, (per_line != 0 && ($unsigned(i) % per_line) == 0) ? "\n" : " "};
         end
         result = {result, $sformatf("%02h", data[i])};
      end
      return result;
   endfunction : bytes_to_hex

   // Shortens a $typename() result: drops a leading "class " and everything from " extends " on.
   static function string simplify_typename(string type_name);
      string result = strip(type_name);
      // A variable, because VCS does not support a string method on a class parameter.
      string keyword = CLASS_KEYWORD;
      int cut;
      if (starts_with(result, keyword)) begin
         result = lstrip(result.substr(keyword.len(), result.len() - 1));
      end
      cut = find(result, EXTENDS_KEYWORD);
      if (cut >= 0) begin
         result = rstrip(result.substr(0, cut - 1));
      end
      return result;
   endfunction : simplify_typename

   // True when c is one of the characters of chars.
   local static function bit has_char(string chars, byte c);
      foreach (chars[i]) begin
         if (chars[i] == c) begin
            return 1;
         end
      end
      return 0;
   endfunction : has_char

   // True when c is a decimal digit.
   local static function bit is_digit(byte c);
      return c >= "0" && c <= "9";
   endfunction : is_digit

   // Numeric value of the decimal digit c.
   local static function longint unsigned digit_value(byte c);
      byte unsigned offset = c - "0";
      return longint'(offset);
   endfunction : digit_value

   // Position just after the digit run of s that starts at position start.
   local static function int digit_run_end(string s, int start);
      int position = start;
      while (position < s.len()) begin
         if (!is_digit(s[position])) begin
            break;
         end
         position++;
      end
      return position;
   endfunction : digit_run_end

   // Compares two digit runs as numbers of any length: -1, 0 or 1.
   local static function int compare_digit_runs(string a, string b);
      string a_digits = lstrip(a, "0");
      string b_digits = lstrip(b, "0");
      if (a_digits.len() != b_digits.len()) begin
         return (a_digits.len() < b_digits.len()) ? -1 : 1;
      end
      return sign_of(a_digits.compare(b_digits));
   endfunction : compare_digit_runs

   // Sign of value: -1, 0 or 1.
   local static function int sign_of(int value);
      if (value == 0) begin
         return 0;
      end
      return (value < 0) ? -1 : 1;
   endfunction : sign_of

endclass : hexk_str

`endif  // HEXK_STR_SV
