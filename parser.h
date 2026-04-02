#ifndef ZIG_MODULE_PARSER_H
#define ZIG_MODULE_PARSER_H

#include "zig_runtime.h"
#include "zig_special_types.h"

#ifndef ZIG_ENUM_zE_1a36c1_Value_Tag
#define ZIG_ENUM_zE_1a36c1_Value_Tag
enum zE_1a36c1_Value_Tag {
    zE_1a36c1_Value_Tag_Nil = 0,
    zE_1a36c1_Value_Tag_Int = 1,
    zE_1a36c1_Value_Tag_Bool = 2,
    zE_1a36c1_Value_Tag_Symbol = 3,
    zE_1a36c1_Value_Tag_Cons = 4,
    zE_1a36c1_Value_Tag_Builtin = 5
};
typedef enum zE_1a36c1_Value_Tag zE_1a36c1_Value_Tag;

#endif /* ZIG_ENUM_zE_1a36c1_Value_Tag */

#ifndef ZIG_ENUM_zE_1866e5_Token_Tag
#define ZIG_ENUM_zE_1866e5_Token_Tag
enum zE_1866e5_Token_Tag {
    zE_1866e5_Token_Tag_LParen = 0,
    zE_1866e5_Token_Tag_RParen = 1,
    zE_1866e5_Token_Tag_Int = 2,
    zE_1866e5_Token_Tag_Symbol = 3,
    zE_1866e5_Token_Tag_Eof = 4
};
typedef enum zE_1866e5_Token_Tag zE_1866e5_Token_Tag;

#endif /* ZIG_ENUM_zE_1866e5_Token_Tag */

struct Arena;
struct zS_148163_Sand;
struct zS_5ed3ca_ConsData;
struct zS_79ea32_Tokenizer;
struct zS_5ed3ca_Value;
struct zS_79ea32_Token;

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_zS_5ed3ca_Value
#define ZIG_ERRORUNION_ErrorUnion_Ptr_zS_5ed3ca_Value
struct ErrorUnion_Ptr_zS_5ed3ca_Value {
    union {
        struct zS_5ed3ca_Value* payload;
        int err;
    } data;
    int is_error;
};
typedef struct ErrorUnion_Ptr_zS_5ed3ca_Value ErrorUnion_Ptr_zS_5ed3ca_Value;
#endif

#include "value.h"
#include "token.h"
#include "sand.h"
#include "util.h"


ErrorUnion_Ptr_zS_5ed3ca_Value zF_49deba_parse_expr(struct zS_79ea32_Tokenizer*, struct zS_148163_Sand*, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_49deba_parse_list(struct zS_79ea32_Tokenizer*, struct zS_148163_Sand*, struct zS_148163_Sand*);

#endif
