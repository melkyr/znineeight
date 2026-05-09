#ifndef ZIG_MODULE_MAIN_H
#define ZIG_MODULE_MAIN_H

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

struct Arena;
struct zS_20f4e1b3_d1871551_Sand;
struct zS_067843b6_fcf51447_Value;
struct zS_b6d8376e_f312777a_Tokenizer;

#include "sand.h"
#include "value.h"
#include "token.h"
#include "parser.h"
#include "env.h"
#include "eval.h"
#include "builtins.h"
#include "util.h"
#include "deep_copy.h"


int main(void);

#endif
