#ifndef ZIG_MODULE_PARSER_H
#define ZIG_MODULE_PARSER_H

#include "zig_runtime.h"
#include "zig_special_types.h"

#ifndef ZIG_ENUM_zE_067843b6_ad7213d2_Value_Tag
#define ZIG_ENUM_zE_067843b6_ad7213d2_Value_Tag
enum zE_067843b6_ad7213d2_Value_Tag {
    zE_067843b6_ad7213d2_Value_Tag_Nil = 0,
    zE_067843b6_ad7213d2_Value_Tag_Int = 1,
    zE_067843b6_ad7213d2_Value_Tag_Bool = 2,
    zE_067843b6_ad7213d2_Value_Tag_Symbol = 3,
    zE_067843b6_ad7213d2_Value_Tag_Cons = 4,
    zE_067843b6_ad7213d2_Value_Tag_Builtin = 5
};
typedef enum zE_067843b6_ad7213d2_Value_Tag zE_067843b6_ad7213d2_Value_Tag;

#endif /* ZIG_ENUM_zE_067843b6_ad7213d2_Value_Tag */

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
struct zS_20f4e1b3_d1871551_Sand;
struct zS_b6d8376e_f312777a_Tokenizer;
struct zS_067843b6_fcf51447_Value;
struct zS_b6d8376e_a1be7292_Token;

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_zS_067843b6_fcf51447_Value
#define ZIG_ERRORUNION_ErrorUnion_Ptr_zS_067843b6_fcf51447_Value
struct ErrorUnion_Ptr_zS_067843b6_fcf51447_Value {
    union __ErrorData_Ptr_zS_067843b6_fcf51447_Value_LispError {
        int err;
        struct zS_067843b6_fcf51447_Value* payload;
    } data;
    int is_error;
};
typedef struct ErrorUnion_Ptr_zS_067843b6_fcf51447_Value ErrorUnion_Ptr_zS_067843b6_fcf51447_Value;
#endif

#include "value.h"
#include "token.h"
#include "sand.h"
#include "util.h"


ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_79f20056_3b791299_parse_expr(struct zS_b6d8376e_f312777a_Tokenizer*, struct zS_20f4e1b3_d1871551_Sand*, struct zS_20f4e1b3_d1871551_Sand*);
ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_79f20056_f09b4e8a_parse_list(struct zS_b6d8376e_f312777a_Tokenizer*, struct zS_20f4e1b3_d1871551_Sand*, struct zS_20f4e1b3_d1871551_Sand*);

#endif
