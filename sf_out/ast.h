#ifndef ZIG_MODULE_AST_H
#define ZIG_MODULE_AST_H

#include "zig_runtime.h"
#include "zig_special_types.h"

#ifndef ZIG_ENUM_zS_c313e0ed_906c25e2_AstKind
#define ZIG_ENUM_zS_c313e0ed_906c25e2_AstKind
enum zS_c313e0ed_906c25e2_AstKind {
    zS_c313e0ed_906c25e2_AstKind_err = 0,
    zS_c313e0ed_906c25e2_AstKind_var_decl = 1,
    zS_c313e0ed_906c25e2_AstKind_fn_decl = 2,
    zS_c313e0ed_906c25e2_AstKind_struct_decl = 3,
    zS_c313e0ed_906c25e2_AstKind_enum_decl = 4,
    zS_c313e0ed_906c25e2_AstKind_union_decl = 5,
    zS_c313e0ed_906c25e2_AstKind_field_decl = 6,
    zS_c313e0ed_906c25e2_AstKind_param_decl = 7,
    zS_c313e0ed_906c25e2_AstKind_test_decl = 8,
    zS_c313e0ed_906c25e2_AstKind_error_set_decl = 9,
    zS_c313e0ed_906c25e2_AstKind_int_literal = 10,
    zS_c313e0ed_906c25e2_AstKind_float_literal = 11,
    zS_c313e0ed_906c25e2_AstKind_string_literal = 12,
    zS_c313e0ed_906c25e2_AstKind_char_literal = 13,
    zS_c313e0ed_906c25e2_AstKind_bool_literal = 14,
    zS_c313e0ed_906c25e2_AstKind_null_literal = 15,
    zS_c313e0ed_906c25e2_AstKind_undefined_literal = 16,
    zS_c313e0ed_906c25e2_AstKind_unreachable_expr = 17,
    zS_c313e0ed_906c25e2_AstKind_enum_literal = 18,
    zS_c313e0ed_906c25e2_AstKind_error_literal = 19,
    zS_c313e0ed_906c25e2_AstKind_tuple_literal = 20,
    zS_c313e0ed_906c25e2_AstKind_struct_init = 21,
    zS_c313e0ed_906c25e2_AstKind_field_init = 22,
    zS_c313e0ed_906c25e2_AstKind_ident_expr = 23,
    zS_c313e0ed_906c25e2_AstKind_field_access = 24,
    zS_c313e0ed_906c25e2_AstKind_index_access = 25,
    zS_c313e0ed_906c25e2_AstKind_slice_expr = 26,
    zS_c313e0ed_906c25e2_AstKind_deref = 27,
    zS_c313e0ed_906c25e2_AstKind_address_of = 28,
    zS_c313e0ed_906c25e2_AstKind_fn_call = 29,
    zS_c313e0ed_906c25e2_AstKind_builtin_call = 30,
    zS_c313e0ed_906c25e2_AstKind_paren_expr = 31,
    zS_c313e0ed_906c25e2_AstKind_add = 32,
    zS_c313e0ed_906c25e2_AstKind_sub = 33,
    zS_c313e0ed_906c25e2_AstKind_mul = 34,
    zS_c313e0ed_906c25e2_AstKind_div = 35,
    zS_c313e0ed_906c25e2_AstKind_mod_op = 36,
    zS_c313e0ed_906c25e2_AstKind_bit_and = 37,
    zS_c313e0ed_906c25e2_AstKind_bit_or = 38,
    zS_c313e0ed_906c25e2_AstKind_bit_xor = 39,
    zS_c313e0ed_906c25e2_AstKind_shl = 40,
    zS_c313e0ed_906c25e2_AstKind_shr = 41,
    zS_c313e0ed_906c25e2_AstKind_bool_and = 42,
    zS_c313e0ed_906c25e2_AstKind_bool_or = 43,
    zS_c313e0ed_906c25e2_AstKind_cmp_eq = 44,
    zS_c313e0ed_906c25e2_AstKind_cmp_ne = 45,
    zS_c313e0ed_906c25e2_AstKind_cmp_lt = 46,
    zS_c313e0ed_906c25e2_AstKind_cmp_le = 47,
    zS_c313e0ed_906c25e2_AstKind_cmp_gt = 48,
    zS_c313e0ed_906c25e2_AstKind_cmp_ge = 49,
    zS_c313e0ed_906c25e2_AstKind_assign = 50,
    zS_c313e0ed_906c25e2_AstKind_add_assign = 51,
    zS_c313e0ed_906c25e2_AstKind_sub_assign = 52,
    zS_c313e0ed_906c25e2_AstKind_mul_assign = 53,
    zS_c313e0ed_906c25e2_AstKind_div_assign = 54,
    zS_c313e0ed_906c25e2_AstKind_mod_assign = 55,
    zS_c313e0ed_906c25e2_AstKind_shl_assign = 56,
    zS_c313e0ed_906c25e2_AstKind_shr_assign = 57,
    zS_c313e0ed_906c25e2_AstKind_and_assign = 58,
    zS_c313e0ed_906c25e2_AstKind_xor_assign = 59,
    zS_c313e0ed_906c25e2_AstKind_or_assign = 60,
    zS_c313e0ed_906c25e2_AstKind_negate = 61,
    zS_c313e0ed_906c25e2_AstKind_bool_not = 62,
    zS_c313e0ed_906c25e2_AstKind_bit_not = 63,
    zS_c313e0ed_906c25e2_AstKind_try_expr = 64,
    zS_c313e0ed_906c25e2_AstKind_catch_expr = 65,
    zS_c313e0ed_906c25e2_AstKind_orelse_expr = 66,
    zS_c313e0ed_906c25e2_AstKind_if_stmt = 67,
    zS_c313e0ed_906c25e2_AstKind_if_expr = 68,
    zS_c313e0ed_906c25e2_AstKind_if_capture = 69,
    zS_c313e0ed_906c25e2_AstKind_while_stmt = 70,
    zS_c313e0ed_906c25e2_AstKind_while_capture = 71,
    zS_c313e0ed_906c25e2_AstKind_for_stmt = 72,
    zS_c313e0ed_906c25e2_AstKind_switch_expr = 73,
    zS_c313e0ed_906c25e2_AstKind_switch_prong = 74,
    zS_c313e0ed_906c25e2_AstKind_block = 75,
    zS_c313e0ed_906c25e2_AstKind_return_stmt = 76,
    zS_c313e0ed_906c25e2_AstKind_break_stmt = 77,
    zS_c313e0ed_906c25e2_AstKind_continue_stmt = 78,
    zS_c313e0ed_906c25e2_AstKind_defer_stmt = 79,
    zS_c313e0ed_906c25e2_AstKind_errdefer_stmt = 80,
    zS_c313e0ed_906c25e2_AstKind_labeled_stmt = 81,
    zS_c313e0ed_906c25e2_AstKind_expr_stmt = 82,
    zS_c313e0ed_906c25e2_AstKind_ptr_type = 83,
    zS_c313e0ed_906c25e2_AstKind_many_ptr_type = 84,
    zS_c313e0ed_906c25e2_AstKind_array_type = 85,
    zS_c313e0ed_906c25e2_AstKind_slice_type = 86,
    zS_c313e0ed_906c25e2_AstKind_optional_type = 87,
    zS_c313e0ed_906c25e2_AstKind_error_union_type = 88,
    zS_c313e0ed_906c25e2_AstKind_fn_type = 89,
    zS_c313e0ed_906c25e2_AstKind_import_expr = 90,
    zS_c313e0ed_906c25e2_AstKind_module_root = 91,
    zS_c313e0ed_906c25e2_AstKind_payload_capture = 92,
    zS_c313e0ed_906c25e2_AstKind_range_exclusive = 93,
    zS_c313e0ed_906c25e2_AstKind_range_inclusive = 94
};
typedef enum zS_c313e0ed_906c25e2_AstKind zS_c313e0ed_906c25e2_AstKind;

#endif /* ZIG_ENUM_zS_c313e0ed_906c25e2_AstKind */

struct zS_c313e0ed_42ae50fe_FnProto;
struct zS_26b5a9a4_43f95de6_Sand;
struct Arena;
struct zS_c313e0ed_6592c721_AstStore;
struct zS_c313e0ed_f3385aec_AstNode;

#ifndef ZIG_STRUCT_zS_c313e0ed_42ae50fe_FnProto
#define ZIG_STRUCT_zS_c313e0ed_42ae50fe_FnProto
struct zS_c313e0ed_42ae50fe_FnProto {
    unsigned int name_id;
    unsigned short params_start;
    unsigned short params_count;
    unsigned int return_type_node;
};

#endif /* ZIG_STRUCT_zS_c313e0ed_42ae50fe_FnProto */

#ifndef ZIG_STRUCT_zS_c313e0ed_6592c721_AstStore
#define ZIG_STRUCT_zS_c313e0ed_6592c721_AstStore
#ifndef ZIG_STRUCT_zS_c313e0ed_1adfeb96_anon_1
#define ZIG_STRUCT_zS_c313e0ed_1adfeb96_anon_1
struct zS_c313e0ed_1adfeb96_anon_1 {
    struct zS_c313e0ed_f3385aec_AstNode* items;
    usize len;
    usize capacity;
};

#endif /* ZIG_STRUCT_zS_c313e0ed_1adfeb96_anon_1 */

#ifndef ZIG_STRUCT_zS_c313e0ed_19dfea03_anon_2
#define ZIG_STRUCT_zS_c313e0ed_19dfea03_anon_2
struct zS_c313e0ed_19dfea03_anon_2 {
    unsigned int* items;
    usize len;
    usize capacity;
};

#endif /* ZIG_STRUCT_zS_c313e0ed_19dfea03_anon_2 */

#ifndef ZIG_STRUCT_zS_c313e0ed_18dfe870_anon_3
#define ZIG_STRUCT_zS_c313e0ed_18dfe870_anon_3
struct zS_c313e0ed_18dfe870_anon_3 {
    unsigned int* items;
    usize len;
    usize capacity;
};

#endif /* ZIG_STRUCT_zS_c313e0ed_18dfe870_anon_3 */

#ifndef ZIG_STRUCT_zS_c313e0ed_1fdff375_anon_4
#define ZIG_STRUCT_zS_c313e0ed_1fdff375_anon_4
struct zS_c313e0ed_1fdff375_anon_4 {
    u64* items;
    usize len;
    usize capacity;
};

#endif /* ZIG_STRUCT_zS_c313e0ed_1fdff375_anon_4 */

#ifndef ZIG_STRUCT_zS_c313e0ed_1edff1e2_anon_5
#define ZIG_STRUCT_zS_c313e0ed_1edff1e2_anon_5
struct zS_c313e0ed_1edff1e2_anon_5 {
    double* items;
    usize len;
    usize capacity;
};

#endif /* ZIG_STRUCT_zS_c313e0ed_1edff1e2_anon_5 */

#ifndef ZIG_STRUCT_zS_c313e0ed_1ddff04f_anon_6
#define ZIG_STRUCT_zS_c313e0ed_1ddff04f_anon_6
struct zS_c313e0ed_1ddff04f_anon_6 {
    unsigned int* items;
    usize len;
    usize capacity;
};

#endif /* ZIG_STRUCT_zS_c313e0ed_1ddff04f_anon_6 */

#ifndef ZIG_STRUCT_zS_c313e0ed_1cdfeebc_anon_7
#define ZIG_STRUCT_zS_c313e0ed_1cdfeebc_anon_7
struct zS_c313e0ed_1cdfeebc_anon_7 {
    struct zS_c313e0ed_42ae50fe_FnProto* items;
    usize len;
    usize capacity;
};

#endif /* ZIG_STRUCT_zS_c313e0ed_1cdfeebc_anon_7 */

struct zS_c313e0ed_6592c721_AstStore {
    struct zS_c313e0ed_1adfeb96_anon_1 nodes;
    struct zS_c313e0ed_19dfea03_anon_2 extra_children;
    struct zS_c313e0ed_18dfe870_anon_3 identifiers;
    struct zS_c313e0ed_1fdff375_anon_4 int_values;
    struct zS_c313e0ed_1edff1e2_anon_5 float_values;
    struct zS_c313e0ed_1ddff04f_anon_6 string_values;
    struct zS_c313e0ed_1cdfeebc_anon_7 fn_protos;
    struct zS_26b5a9a4_43f95de6_Sand* allocator;
};

#endif /* ZIG_STRUCT_zS_c313e0ed_6592c721_AstStore */

struct zS_c313e0ed_1adfeb96_anon_1;
struct zS_c313e0ed_19dfea03_anon_2;
struct zS_c313e0ed_18dfe870_anon_3;
struct zS_c313e0ed_1fdff375_anon_4;
struct zS_c313e0ed_1edff1e2_anon_5;
struct zS_c313e0ed_1ddff04f_anon_6;
struct zS_c313e0ed_1cdfeebc_anon_7;
#ifndef ZIG_STRUCT_zS_c313e0ed_f3385aec_AstNode
#define ZIG_STRUCT_zS_c313e0ed_f3385aec_AstNode
struct zS_c313e0ed_f3385aec_AstNode {
    enum zS_c313e0ed_906c25e2_AstKind kind;
    unsigned char flags;
    unsigned short span_len;
    unsigned int span_start;
    unsigned int child_0;
    unsigned int child_1;
    unsigned int child_2;
    unsigned int payload;
};

#endif /* ZIG_STRUCT_zS_c313e0ed_f3385aec_AstNode */

#include "allocator.h"


struct zS_c313e0ed_6592c721_AstStore zF_c313e0ed_da3213b4_astStoreInit(struct zS_26b5a9a4_43f95de6_Sand*);
unsigned int zF_c313e0ed_eeeed775_astStoreAddNode(struct zS_c313e0ed_6592c721_AstStore*, enum zS_c313e0ed_906c25e2_AstKind, unsigned char, unsigned int, unsigned int, unsigned int, unsigned int, unsigned int, unsigned int);
unsigned int zF_c313e0ed_8a6ff23e_astStoreAddExtraChildren(struct zS_c313e0ed_6592c721_AstStore*, Slice_u32);
Slice_u32 zF_c313e0ed_cede0377_astStoreGetExtraChildren(struct zS_c313e0ed_6592c721_AstStore*, unsigned int);
unsigned int zF_c313e0ed_b98b4cad_astStoreAddIntLiteral(struct zS_c313e0ed_6592c721_AstStore*, u64, unsigned int, unsigned int);
unsigned int zF_c313e0ed_94cb00fc_astStoreAddFloatLiteral(struct zS_c313e0ed_6592c721_AstStore*, double, unsigned int, unsigned int);
unsigned int zF_c313e0ed_9743289f_astStoreAddStringLiteral(struct zS_c313e0ed_6592c721_AstStore*, unsigned int, unsigned int, unsigned int);
unsigned int zF_c313e0ed_1c79e2e6_astStoreAddIdentifier(struct zS_c313e0ed_6592c721_AstStore*, enum zS_c313e0ed_906c25e2_AstKind, unsigned int, unsigned int, unsigned int);

#endif
