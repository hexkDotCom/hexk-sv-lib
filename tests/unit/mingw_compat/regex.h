// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// regex.h
//
// Test infrastructure, not part of the library: the part of POSIX <regex.h> that the DPI
// code of UVM uses (regcomp, regexec, regerror, regfree), built on std::regex. MinGW-w64, the
// C compiler for Questa on Windows, has no POSIX regular expression library, so 'make test
// SIM=questa' puts this directory on the include path there. Patterns are compiled with the
// POSIX extended grammar of std::regex; on Linux the simulators use the C library instead.

#ifndef HEXK_MINGW_COMPAT_REGEX_H
#define HEXK_MINGW_COMPAT_REGEX_H

#ifdef __cplusplus
// The UVM code includes this header inside an extern "C" block.
extern "C++" {
#include <cstddef>
#include <cstring>
#include <regex>

typedef struct {
   std::regex* compiled;
   size_t      re_nsub;
} regex_t;

typedef int regoff_t;

typedef struct {
   regoff_t rm_so;
   regoff_t rm_eo;
} regmatch_t;

#define REG_EXTENDED 1
#define REG_ICASE 2
#define REG_NOSUB 4
#define REG_NEWLINE 8

#define REG_NOMATCH 1
#define REG_BADPAT 2

// Compiles pattern into preg; returns 0, or REG_BADPAT for a pattern that is not valid.
static inline int regcomp(regex_t* preg, const char* pattern, int cflags) {
   std::regex::flag_type flags = (cflags & REG_EXTENDED) ? std::regex::extended : std::regex::basic;
   if (cflags & REG_ICASE) flags |= std::regex::icase;
   if (cflags & REG_NOSUB) flags |= std::regex::nosubs;
   preg->compiled = NULL;
   preg->re_nsub  = 0;
   try {
      preg->compiled = new std::regex(pattern, flags);
      preg->re_nsub  = preg->compiled->mark_count();
   } catch (const std::regex_error&) {
      return REG_BADPAT;
   }
   return 0;
}

// Searches text for the compiled pattern; returns 0 on a match, REG_NOMATCH otherwise.
static inline int regexec(const regex_t* preg, const char* text, size_t nmatch, regmatch_t pmatch[], int) {
   std::cmatch found;
   if (preg->compiled == NULL || !std::regex_search(text, found, *preg->compiled)) return REG_NOMATCH;
   for (size_t i = 0; i < nmatch; i++) {
      bool have       = i < found.size() && found[i].matched;
      pmatch[i].rm_so = have ? static_cast<regoff_t>(found.position(i)) : -1;
      pmatch[i].rm_eo = have ? static_cast<regoff_t>(found.position(i) + found.length(i)) : -1;
   }
   return 0;
}

// Writes a text for errcode into errbuf; returns the size the full text needs.
static inline size_t regerror(int errcode, const regex_t*, char* errbuf, size_t errbuf_size) {
   const char* text = (errcode == 0) ? "success" : (errcode == REG_NOMATCH) ? "no match" : "invalid regular expression";
   if (errbuf != NULL && errbuf_size > 0) {
      strncpy(errbuf, text, errbuf_size - 1);
      errbuf[errbuf_size - 1] = 0;
   }
   return strlen(text) + 1;
}

// Frees what regcomp allocated.
static inline void regfree(regex_t* preg) {
   delete preg->compiled;
   preg->compiled = NULL;
}
}
#endif

#endif  // HEXK_MINGW_COMPAT_REGEX_H
