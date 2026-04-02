#ifndef ZIG_MODULE_TOKEN_H
#define ZIG_MODULE_TOKEN_H

#include "zig_runtime.h"
#include "zig_special_types.h"

#ifndef ZIG_ENUM_zE_7_Token_Tag
#define ZIG_ENUM_zE_7_Token_Tag
enum zE_7_Token_Tag {
    zE_7_Token_Tag_LParen = 0,
    zE_7_Token_Tag_RParen = 1,
    zE_7_Token_Tag_Int = 2,
    zE_7_Token_Tag_Symbol = 3,
    zE_7_Token_Tag_Eof = 4
};
typedef enum zE_7_Token_Tag zE_7_Token_Tag;

#endif /* ZIG_ENUM_zE_7_Token_Tag */

struct Arena;
struct zS_2_Tokenizer;
struct zS_1_Token;

#ifndef ZIG_STRUCT_zS_2_Tokenizer
#define ZIG_STRUCT_zS_2_Tokenizer
struct zS_2_Tokenizer {
    Slice_u8 input;
    usize pos;
};

#endif /* ZIG_STRUCT_zS_2_Tokenizer */

#ifndef ZIG_UNION_zS_1_Token
#define ZIG_UNION_zS_1_Token
struct zS_1_Token {
    enum zE_7_Token_Tag tag;
    union {
        i64 Int;
        Slice_u8 Symbol;
    } data;
};

#endif /* ZIG_UNION_zS_1_Token */

#ifndef ZIG_ERRORUNION_ErrorUnion_zS_1_Token
#define ZIG_ERRORUNION_ErrorUnion_zS_1_Token
struct ErrorUnion_zS_1_Token {
    union {
        struct zS_1_Token payload;
        int err;
    } data;
    int is_error;
};
typedef struct ErrorUnion_zS_1_Token ErrorUnion_zS_1_Token;
#endif

#include "util.h"


ErrorUnion_zS_1_Token zF_19_next_token(struct zS_2_Tokenizer*);
ErrorUnion_zS_1_Token zF_21_peek_token(struct zS_2_Tokenizer*);

#endif
