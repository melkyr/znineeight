#ifndef ZIG_MODULE_TOKEN_H
#define ZIG_MODULE_TOKEN_H

#include "zig_runtime.h"
#include "util.h"


struct z_token_Tokenizer;
struct z_token_Token;
struct z_token_Tokenizer {
    Slice_u8 input;
    usize pos;
};

enum z_token_Token_Tag {
    z_token_Token_Tag_LParen = 0,
    z_token_Token_Tag_RParen = 1,
    z_token_Token_Tag_Int = 2,
    z_token_Token_Tag_Symbol = 3,
    z_token_Token_Tag_Eof = 4
};
typedef enum z_token_Token_Tag z_token_Token_Tag;

struct z_token_Token {
    enum z_token_Token_Tag tag;
    union {
        i64 Int;
        Slice_u8 Symbol;
    } data;
};

#ifndef ZIG_ERRORUNION_ErrorUnion_z_token_Token
#define ZIG_ERRORUNION_ErrorUnion_z_token_Token
typedef struct {
    union {
        struct z_token_Token payload;
        int err;
    } data;
    int is_error;
} ErrorUnion_z_token_Token;
#endif


ErrorUnion_z_token_Token z_token_next_token(struct z_token_Tokenizer*);
ErrorUnion_z_token_Token z_token_peek_token(struct z_token_Tokenizer*);

#endif
