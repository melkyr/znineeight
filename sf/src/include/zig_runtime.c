/* zig_runtime.c - Z98 Runtime Library (generated) */
#include "zig_compat.h"
#include <string.h>

/* Forward declarations for PAL functions */
extern void pal_print_stderr(const char* s, unsigned int len);
extern void pal_abort(void);
extern int pal_i64_to_str(long long val, char* buf, int bufsize);
extern int pal_u64_to_str(unsigned long long val, char* buf, int bufsize);
extern int pal_f64_to_str(double val, char* buf, int bufsize);

/* Panic handler */
void __bootstrap_panic(const char* msg) {
    pal_print_stderr("panic: ", 7);
    pal_print_stderr(msg, strlen(msg));
    pal_print_stderr("\n", 1);
    pal_abort();
}

/* Print helpers */
void __bootstrap_print(const char* s) { if (s) pal_print_stderr(s, strlen(s)); }
void __bootstrap_print_len(const char* s, unsigned int len) { if (s && len) pal_print_stderr(s, len); }

void __bootstrap_print_i32(int val) {
    char buf[16];
    pal_i64_to_str((long long)val, buf, sizeof(buf));
    __bootstrap_print(buf);
}

void __bootstrap_print_u32(unsigned int val) {
    char buf[16];
    pal_u64_to_str((unsigned long long)val, buf, sizeof(buf));
    __bootstrap_print(buf);
}

void __bootstrap_print_i64(long long val) {
    char buf[24];
    pal_i64_to_str(val, buf, sizeof(buf));
    __bootstrap_print(buf);
}

void __bootstrap_print_u64(unsigned long long val) {
    char buf[24];
    pal_u64_to_str(val, buf, sizeof(buf));
    __bootstrap_print(buf);
}

void __bootstrap_print_f64(double val) {
    char buf[32];
    pal_f64_to_str(val, buf, sizeof(buf));
    __bootstrap_print(buf);
}

void __bootstrap_print_bool(int val) {
    if (val) __bootstrap_print("true");
    else __bootstrap_print("false");
}

void __bootstrap_print_char(unsigned char val) { char c = (char)val; pal_print_stderr(&c, 1); }

void __bootstrap_print_str(const unsigned char* ptr, unsigned int len) {
    if (ptr && len) pal_print_stderr((const char*)ptr, len);
}

/* Checked conversions (u64 -> target type) */

signed char __bootstrap_checked_cast_i8(unsigned long long val) {
    if (val > 127ULL) __bootstrap_panic("int cast overflow for i8");
    return (signed char)val;
}

unsigned char __bootstrap_checked_cast_u8(unsigned long long val) {
    if (val > 255ULL) __bootstrap_panic("int cast overflow for u8");
    return (unsigned char)val;
}

short __bootstrap_checked_cast_i16(unsigned long long val) {
    if (val > 32767ULL) __bootstrap_panic("int cast overflow for i16");
    return (short)val;
}

unsigned short __bootstrap_checked_cast_u16(unsigned long long val) {
    if (val > 65535ULL) __bootstrap_panic("int cast overflow for u16");
    return (unsigned short)val;
}

int __bootstrap_checked_cast_i32(unsigned long long val) {
    if (val > 2147483647ULL) __bootstrap_panic("int cast overflow for i32");
    return (int)val;
}

unsigned int __bootstrap_checked_cast_u32(unsigned long long val) {
    if (val > 4294967295ULL) __bootstrap_panic("int cast overflow for u32");
    return (unsigned int)val;
}

long long __bootstrap_checked_cast_i64(unsigned long long val) {
    if (val > 9223372036854775807ULL) __bootstrap_panic("int cast overflow for i64");
    return (long long)val;
}

unsigned long long __bootstrap_checked_cast_u64(unsigned long long val) {
    return val;
}
