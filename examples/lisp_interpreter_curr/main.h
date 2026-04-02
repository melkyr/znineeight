#ifndef ZIG_MODULE_MAIN_H
#define ZIG_MODULE_MAIN_H

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

struct Arena;
struct zS_4_ConsData;
struct zS_3_Sand;
struct zS_2_Tokenizer;
struct zS_5_Value;

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
