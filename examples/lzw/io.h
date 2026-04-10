#ifndef ZIG_MODULE_IO_H
#define ZIG_MODULE_IO_H

#include "zig_runtime.h"
#include "zig_special_types.h"

struct Arena;

#include "dict.h"


int zF_387c31_readByte(void);
void zF_387c31_writeByte(unsigned char);
void zF_387c31_writeCode(int);
int zF_387c31_readCode(void);
void zF_387c31_printStr(unsigned char const*);
void zF_387c31_printErr(unsigned char const*);

#endif
