#ifndef ZIG_MODULE_PARSER_H
#define ZIG_MODULE_PARSER_H

#include "zig_runtime.h"
#include "value.h"
#include "token.h"
#include "sand.h"
#include "util.h"


#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_z_value_Value
#define ZIG_ERRORUNION_ErrorUnion_Ptr_z_value_Value
typedef struct {
    union {
        struct z_value_Value* payload;
        int err;
    } data;
    int is_error;
} ErrorUnion_Ptr_z_value_Value;
#endif


ErrorUnion_Ptr_z_value_Value z_parser_parse_expr(struct z_token_Tokenizer*, struct z_sand_Sand*, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_parser_parse_list(struct z_token_Tokenizer*, struct z_sand_Sand*, struct z_sand_Sand*);

#endif
