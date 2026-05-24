#ifndef ZIG_RUNTIME_H
#define ZIG_RUNTIME_H

#include "zig_compat.h"

extern void pal_print_stderr(const char* s, unsigned int len);
extern void pal_abort(void);
extern int pal_i64_to_str(long long val, char* buf, int bufsize);
extern int pal_u64_to_str(unsigned long long val, char* buf, int bufsize);
extern int pal_f64_to_str(double val, char* buf, int bufsize);

void __bootstrap_panic(const char* msg);
void __bootstrap_print(const char* s);
void __bootstrap_print_len(const char* s, unsigned int len);
void __bootstrap_print_i32(int val);
void __bootstrap_print_u32(unsigned int val);
void __bootstrap_print_i64(long long val);
void __bootstrap_print_u64(unsigned long long val);
void __bootstrap_print_f64(double val);
void __bootstrap_print_bool(int val);
void __bootstrap_print_char(unsigned char val);
void __bootstrap_print_str(const unsigned char* ptr, unsigned int len);
signed char __bootstrap_checked_cast_i8(unsigned long long val);
unsigned char __bootstrap_checked_cast_u8(unsigned long long val);
short __bootstrap_checked_cast_i16(unsigned long long val);
unsigned short __bootstrap_checked_cast_u16(unsigned long long val);
int __bootstrap_checked_cast_i32(unsigned long long val);
unsigned int __bootstrap_checked_cast_u32(unsigned long long val);
long long __bootstrap_checked_cast_i64(unsigned long long val);
unsigned long long __bootstrap_checked_cast_u64(unsigned long long val);

#endif
