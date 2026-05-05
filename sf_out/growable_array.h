#ifndef ZIG_MODULE_GROWABLE_ARRAY_H
#define ZIG_MODULE_GROWABLE_ARRAY_H

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

struct zS_26b5a9a4_43f95de6_Sand;
struct zS_16d7ab7a_ad5c2721_U64ArrayList;
struct zS_16d7ab7a_840ccd30_U32ArrayList;
struct zS_c313e0ed_42ae50fe_FnProto;
struct zS_16d7ab7a_35e082a4_FnProtoArrayList;
struct Arena;
struct zS_16d7ab7a_06dd9f8a_F64ArrayList;
struct zS_16d7ab7a_2bc6fbde_AstNodeArrayList;
struct zS_16d7ab7a_95cf740f_U8ArrayList;
struct zS_c313e0ed_f3385aec_AstNode;

#ifndef ZIG_STRUCT_zS_16d7ab7a_ad5c2721_U64ArrayList
#define ZIG_STRUCT_zS_16d7ab7a_ad5c2721_U64ArrayList
struct zS_16d7ab7a_ad5c2721_U64ArrayList {
    u64* items;
    usize len;
    usize capacity;
    struct zS_26b5a9a4_43f95de6_Sand* allocator;
};

#endif /* ZIG_STRUCT_zS_16d7ab7a_ad5c2721_U64ArrayList */

#ifndef ZIG_STRUCT_zS_16d7ab7a_840ccd30_U32ArrayList
#define ZIG_STRUCT_zS_16d7ab7a_840ccd30_U32ArrayList
struct zS_16d7ab7a_840ccd30_U32ArrayList {
    unsigned int* items;
    usize len;
    usize capacity;
    struct zS_26b5a9a4_43f95de6_Sand* allocator;
};

#endif /* ZIG_STRUCT_zS_16d7ab7a_840ccd30_U32ArrayList */

#ifndef ZIG_STRUCT_zS_16d7ab7a_35e082a4_FnProtoArrayList
#define ZIG_STRUCT_zS_16d7ab7a_35e082a4_FnProtoArrayList
struct zS_16d7ab7a_35e082a4_FnProtoArrayList {
    struct zS_c313e0ed_42ae50fe_FnProto* items;
    usize len;
    usize capacity;
    struct zS_26b5a9a4_43f95de6_Sand* allocator;
};

#endif /* ZIG_STRUCT_zS_16d7ab7a_35e082a4_FnProtoArrayList */

#ifndef ZIG_STRUCT_zS_16d7ab7a_06dd9f8a_F64ArrayList
#define ZIG_STRUCT_zS_16d7ab7a_06dd9f8a_F64ArrayList
struct zS_16d7ab7a_06dd9f8a_F64ArrayList {
    double* items;
    usize len;
    usize capacity;
    struct zS_26b5a9a4_43f95de6_Sand* allocator;
};

#endif /* ZIG_STRUCT_zS_16d7ab7a_06dd9f8a_F64ArrayList */

#ifndef ZIG_STRUCT_zS_16d7ab7a_2bc6fbde_AstNodeArrayList
#define ZIG_STRUCT_zS_16d7ab7a_2bc6fbde_AstNodeArrayList
struct zS_16d7ab7a_2bc6fbde_AstNodeArrayList {
    struct zS_c313e0ed_f3385aec_AstNode* items;
    usize len;
    usize capacity;
    struct zS_26b5a9a4_43f95de6_Sand* allocator;
};

#endif /* ZIG_STRUCT_zS_16d7ab7a_2bc6fbde_AstNodeArrayList */

#ifndef ZIG_STRUCT_zS_16d7ab7a_95cf740f_U8ArrayList
#define ZIG_STRUCT_zS_16d7ab7a_95cf740f_U8ArrayList
struct zS_16d7ab7a_95cf740f_U8ArrayList {
    unsigned char* items;
    usize len;
    usize capacity;
    struct zS_26b5a9a4_43f95de6_Sand* allocator;
};

#endif /* ZIG_STRUCT_zS_16d7ab7a_95cf740f_U8ArrayList */

#ifndef ZIG_OPTIONAL_Optional_u32
#define ZIG_OPTIONAL_Optional_u32
struct Optional_u32 {
    unsigned int value;
    int has_value;
};
typedef struct Optional_u32 Optional_u32;
#endif

#include "allocator.h"
#include "ast.h"


struct zS_16d7ab7a_840ccd30_U32ArrayList zF_16d7ab7a_9eafada9_u32ArrayListInit(struct zS_26b5a9a4_43f95de6_Sand*);
void zF_16d7ab7a_a304de89_u32ArrayListEnsureCapacity(struct zS_16d7ab7a_840ccd30_U32ArrayList*, usize);
void zF_16d7ab7a_42a80787_u32ArrayListAppend(struct zS_16d7ab7a_840ccd30_U32ArrayList*, unsigned int);
Optional_u32 zF_16d7ab7a_89114f92_u32ArrayListPopOrNull(struct zS_16d7ab7a_840ccd30_U32ArrayList*);
Slice_u32 zF_16d7ab7a_163e748d_u32ArrayListGetSlice(struct zS_16d7ab7a_840ccd30_U32ArrayList*);
struct zS_16d7ab7a_95cf740f_U8ArrayList zF_16d7ab7a_757eb041_byteArrayListInit(struct zS_26b5a9a4_43f95de6_Sand*);
void zF_16d7ab7a_dbb9a334_byteArrayListGrow(struct zS_16d7ab7a_95cf740f_U8ArrayList*, usize);
void zF_16d7ab7a_311f9e3f_byteArrayListAppend(struct zS_16d7ab7a_95cf740f_U8ArrayList*, unsigned char);
Slice_u8 zF_16d7ab7a_71d232b5_byteArrayListGetSlice(struct zS_16d7ab7a_95cf740f_U8ArrayList*);
struct zS_16d7ab7a_2bc6fbde_AstNodeArrayList zF_16d7ab7a_612498a3_astNodeArrayListInit(struct zS_26b5a9a4_43f95de6_Sand*, usize);
void zF_16d7ab7a_dd2bbd13_astNodeArrayListEnsureCapacity(struct zS_16d7ab7a_2bc6fbde_AstNodeArrayList*, usize);
void zF_16d7ab7a_9aaaacf1_astNodeArrayListAppend(struct zS_16d7ab7a_2bc6fbde_AstNodeArrayList*, struct zS_c313e0ed_f3385aec_AstNode);
Slice_zS_c313e0ed_f3385aec_AstNode zF_16d7ab7a_8c103497_astNodeArrayListGetSlice(struct zS_16d7ab7a_2bc6fbde_AstNodeArrayList*);
struct zS_16d7ab7a_ad5c2721_U64ArrayList zF_16d7ab7a_46450984_u64ArrayListInit(struct zS_26b5a9a4_43f95de6_Sand*, usize);
void zF_16d7ab7a_412e9c1c_u64ArrayListEnsureCapacity(struct zS_16d7ab7a_ad5c2721_U64ArrayList*, usize);
void zF_16d7ab7a_4ab008ba_u64ArrayListAppend(struct zS_16d7ab7a_ad5c2721_U64ArrayList*, u64);
Slice_u64 zF_16d7ab7a_24aa3530_u64ArrayListGetSlice(struct zS_16d7ab7a_ad5c2721_U64ArrayList*);
struct zS_16d7ab7a_06dd9f8a_F64ArrayList zF_16d7ab7a_dc157e53_f64ArrayListInit(struct zS_26b5a9a4_43f95de6_Sand*, usize);
void zF_16d7ab7a_0e9bd563_f64ArrayListEnsureCapacity(struct zS_16d7ab7a_06dd9f8a_F64ArrayList*, usize);
void zF_16d7ab7a_fe8768c1_f64ArrayListAppend(struct zS_16d7ab7a_06dd9f8a_F64ArrayList*, double);
Slice_f64 zF_16d7ab7a_abc75ea7_f64ArrayListGetSlice(struct zS_16d7ab7a_06dd9f8a_F64ArrayList*);
struct zS_16d7ab7a_35e082a4_FnProtoArrayList zF_16d7ab7a_bd2cf011_fnProtoArrayListInit(struct zS_26b5a9a4_43f95de6_Sand*, usize);
void zF_16d7ab7a_a61c8131_fnProtoArrayListEnsureCapacity(struct zS_16d7ab7a_35e082a4_FnProtoArrayList*, usize);
void zF_16d7ab7a_a8a6a1ef_fnProtoArrayListAppend(struct zS_16d7ab7a_35e082a4_FnProtoArrayList*, struct zS_c313e0ed_42ae50fe_FnProto);
Slice_zS_c313e0ed_42ae50fe_FnProto zF_16d7ab7a_a034ee25_fnProtoArrayListGetSlice(struct zS_16d7ab7a_35e082a4_FnProtoArrayList*);

#endif
