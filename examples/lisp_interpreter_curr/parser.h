#ifndef ZIG_MODULE_PARSER_H
#define ZIG_MODULE_PARSER_H

#include "zig_runtime.h"
#include "zig_special_types.h"

#ifndef ZIG_ENUM_zE_8_Value_Tag
#define ZIG_ENUM_zE_8_Value_Tag
enum zE_8_Value_Tag {
    zE_8_Value_Tag_Nil = 0,
    zE_8_Value_Tag_Int = 1,
    zE_8_Value_Tag_Bool = 2,
    zE_8_Value_Tag_Symbol = 3,
    zE_8_Value_Tag_Cons = 4,
    zE_8_Value_Tag_Builtin = 5
};
typedef enum zE_8_Value_Tag zE_8_Value_Tag;

#endif /* ZIG_ENUM_zE_8_Value_Tag */

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
struct zS_3_Sand;
struct zS_4_ConsData;
struct zS_2_Tokenizer;
struct zS_5_Value;
struct zS_1_Token;

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_zS_5_Value
#define ZIG_ERRORUNION_ErrorUnion_Ptr_zS_5_Value
struct ErrorUnion_Ptr_zS_5_Value {
    union {
        struct zS_5_Value* payload;
        int err;
    } data;
    int is_error;
};
typedef struct ErrorUnion_Ptr_zS_5_Value ErrorUnion_Ptr_zS_5_Value;
#endif

#include "value.h"
#include "token.h"
#include "sand.h"
#include "util.h"


ErrorUnion_Ptr_zS_5_Value zF_68_parse_expr(struct zS_2_Tokenizer*, struct zS_3_Sand*, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_69_parse_list(struct zS_2_Tokenizer*, struct zS_3_Sand*, struct zS_3_Sand*);

#endif
