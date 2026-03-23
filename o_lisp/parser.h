#ifndef ZIG_MODULE_PARSER_H
#define ZIG_MODULE_PARSER_H

#include "zig_runtime.h"
#include "value.h"
#include "token.h"
#include "util.h"
#include "sand.h"


struct z_parser_SymbolNode;
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

#ifndef ZIG_OPTIONAL_Optional_Ptr_z_parser_SymbolNode
#define ZIG_OPTIONAL_Optional_Ptr_z_parser_SymbolNode
typedef struct {
    struct z_parser_SymbolNode* value;
    int has_value;
} Optional_Ptr_z_parser_SymbolNode;
#endif

struct z_parser_SymbolNode {
    Slice_u8 name;
    struct z_value_Value* value;
    Optional_Ptr_z_parser_SymbolNode next;
};


ErrorUnion_Ptr_z_value_Value z_parser_intern_symbol(Slice_u8, struct z_sand_LispSand*);
ErrorUnion_Ptr_z_value_Value z_parser_parse_expr(struct z_token_Tokenizer*, struct z_sand_LispSand*, struct z_sand_LispSand*);

#endif
