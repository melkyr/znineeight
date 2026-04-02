#ifndef ZIG_MODULE_REPRO_H
#define ZIG_MODULE_REPRO_H

#include "zig_runtime.h"
#include "zig_special_types.h"

#ifndef ZIG_ENUM_zE_f4f14f_Token_Tag
#define ZIG_ENUM_zE_f4f14f_Token_Tag
enum zE_f4f14f_Token_Tag {
    zE_f4f14f_Token_Tag_LParen = 0,
    zE_f4f14f_Token_Tag_RParen = 1,
    zE_f4f14f_Token_Tag_Int = 2,
    zE_f4f14f_Token_Tag_Symbol = 3,
    zE_f4f14f_Token_Tag_Eof = 4
};
typedef enum zE_f4f14f_Token_Tag zE_f4f14f_Token_Tag;

#endif /* ZIG_ENUM_zE_f4f14f_Token_Tag */

struct Arena;
struct zS_a236bb_Token;

#ifndef ZIG_UNION_zS_a236bb_Token
#define ZIG_UNION_zS_a236bb_Token
struct zS_a236bb_Token {
    enum zE_f4f14f_Token_Tag tag;
    union {
        i64 Int;
        Slice_u8 Symbol;
    } data;
};

#endif /* ZIG_UNION_zS_a236bb_Token */



int main(void);

#endif
