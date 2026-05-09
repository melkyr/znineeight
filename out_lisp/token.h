#ifndef ZIG_MODULE_TOKEN_H
#define ZIG_MODULE_TOKEN_H

#include "zig_runtime.h"
#include "zig_special_types.h"

#ifndef ZIG_ENUM_zE_b6d8376e_e26bbaef_Token_Tag
#define ZIG_ENUM_zE_b6d8376e_e26bbaef_Token_Tag
enum zE_b6d8376e_e26bbaef_Token_Tag {
    zE_b6d8376e_e26bbaef_Token_Tag_LParen = 0,
    zE_b6d8376e_e26bbaef_Token_Tag_RParen = 1,
    zE_b6d8376e_e26bbaef_Token_Tag_Int = 2,
    zE_b6d8376e_e26bbaef_Token_Tag_Symbol = 3,
    zE_b6d8376e_e26bbaef_Token_Tag_Eof = 4
};
typedef enum zE_b6d8376e_e26bbaef_Token_Tag zE_b6d8376e_e26bbaef_Token_Tag;

#endif /* ZIG_ENUM_zE_b6d8376e_e26bbaef_Token_Tag */

struct Arena;
struct zS_b6d8376e_f312777a_Tokenizer;
struct zS_b6d8376e_a1be7292_Token;

#ifndef ZIG_STRUCT_zS_b6d8376e_f312777a_Tokenizer
#define ZIG_STRUCT_zS_b6d8376e_f312777a_Tokenizer
struct zS_b6d8376e_f312777a_Tokenizer {
    Slice_u8 input;
    usize pos;
};

#endif /* ZIG_STRUCT_zS_b6d8376e_f312777a_Tokenizer */

#ifndef ZIG_UNION_zS_b6d8376e_a1be7292_Token
#define ZIG_UNION_zS_b6d8376e_a1be7292_Token
struct zS_b6d8376e_a1be7292_Token {
    enum zE_b6d8376e_e26bbaef_Token_Tag tag;
    union {
        i64 Int;
        Slice_u8 Symbol;
    } data;
};

#endif /* ZIG_UNION_zS_b6d8376e_a1be7292_Token */

#ifndef ZIG_ERRORUNION_ErrorUnion_zS_b6d8376e_a1be7292_Token
#define ZIG_ERRORUNION_ErrorUnion_zS_b6d8376e_a1be7292_Token
struct ErrorUnion_zS_b6d8376e_a1be7292_Token {
    union __ErrorData_zS_b6d8376e_a1be7292_Token_LispError {
        int err;
        struct zS_b6d8376e_a1be7292_Token payload;
    } data;
    int is_error;
};
typedef struct ErrorUnion_zS_b6d8376e_a1be7292_Token ErrorUnion_zS_b6d8376e_a1be7292_Token;
#endif

#include "util.h"


ErrorUnion_zS_b6d8376e_a1be7292_Token zF_b6d8376e_9411dcb1_next_token(struct zS_b6d8376e_f312777a_Tokenizer*);
ErrorUnion_zS_b6d8376e_a1be7292_Token zF_b6d8376e_9c169757_peek_token(struct zS_b6d8376e_f312777a_Tokenizer*);

#endif
