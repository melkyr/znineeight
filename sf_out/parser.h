#ifndef ZIG_MODULE_PARSER_H
#define ZIG_MODULE_PARSER_H

#include "zig_runtime.h"
#include "zig_special_types.h"

#ifndef ZIG_ENUM_zS_89baa7c0_facdb0ca_TokenKind
#define ZIG_ENUM_zS_89baa7c0_facdb0ca_TokenKind
enum zS_89baa7c0_facdb0ca_TokenKind {
    zS_89baa7c0_facdb0ca_TokenKind_integer_literal = 0,
    zS_89baa7c0_facdb0ca_TokenKind_float_literal = 1,
    zS_89baa7c0_facdb0ca_TokenKind_string_literal = 2,
    zS_89baa7c0_facdb0ca_TokenKind_char_literal = 3,
    zS_89baa7c0_facdb0ca_TokenKind_identifier = 4,
    zS_89baa7c0_facdb0ca_TokenKind_builtin_identifier = 5,
    zS_89baa7c0_facdb0ca_TokenKind_lparen = 6,
    zS_89baa7c0_facdb0ca_TokenKind_rparen = 7,
    zS_89baa7c0_facdb0ca_TokenKind_lbracket = 8,
    zS_89baa7c0_facdb0ca_TokenKind_rbracket = 9,
    zS_89baa7c0_facdb0ca_TokenKind_lbrace = 10,
    zS_89baa7c0_facdb0ca_TokenKind_rbrace = 11,
    zS_89baa7c0_facdb0ca_TokenKind_semicolon = 12,
    zS_89baa7c0_facdb0ca_TokenKind_colon = 13,
    zS_89baa7c0_facdb0ca_TokenKind_comma = 14,
    zS_89baa7c0_facdb0ca_TokenKind_dot = 15,
    zS_89baa7c0_facdb0ca_TokenKind_at_sign = 16,
    zS_89baa7c0_facdb0ca_TokenKind_underscore = 17,
    zS_89baa7c0_facdb0ca_TokenKind_question_mark = 18,
    zS_89baa7c0_facdb0ca_TokenKind_bang = 19,
    zS_89baa7c0_facdb0ca_TokenKind_plus = 20,
    zS_89baa7c0_facdb0ca_TokenKind_minus = 21,
    zS_89baa7c0_facdb0ca_TokenKind_star = 22,
    zS_89baa7c0_facdb0ca_TokenKind_slash = 23,
    zS_89baa7c0_facdb0ca_TokenKind_percent = 24,
    zS_89baa7c0_facdb0ca_TokenKind_ampersand = 25,
    zS_89baa7c0_facdb0ca_TokenKind_pipe = 26,
    zS_89baa7c0_facdb0ca_TokenKind_caret = 27,
    zS_89baa7c0_facdb0ca_TokenKind_tilde = 28,
    zS_89baa7c0_facdb0ca_TokenKind_shl = 29,
    zS_89baa7c0_facdb0ca_TokenKind_shr = 30,
    zS_89baa7c0_facdb0ca_TokenKind_eq_eq = 31,
    zS_89baa7c0_facdb0ca_TokenKind_bang_eq = 32,
    zS_89baa7c0_facdb0ca_TokenKind_less = 33,
    zS_89baa7c0_facdb0ca_TokenKind_less_eq = 34,
    zS_89baa7c0_facdb0ca_TokenKind_greater = 35,
    zS_89baa7c0_facdb0ca_TokenKind_greater_eq = 36,
    zS_89baa7c0_facdb0ca_TokenKind_eq = 37,
    zS_89baa7c0_facdb0ca_TokenKind_plus_eq = 38,
    zS_89baa7c0_facdb0ca_TokenKind_minus_eq = 39,
    zS_89baa7c0_facdb0ca_TokenKind_star_eq = 40,
    zS_89baa7c0_facdb0ca_TokenKind_slash_eq = 41,
    zS_89baa7c0_facdb0ca_TokenKind_percent_eq = 42,
    zS_89baa7c0_facdb0ca_TokenKind_ampersand_eq = 43,
    zS_89baa7c0_facdb0ca_TokenKind_pipe_eq = 44,
    zS_89baa7c0_facdb0ca_TokenKind_caret_eq = 45,
    zS_89baa7c0_facdb0ca_TokenKind_shl_eq = 46,
    zS_89baa7c0_facdb0ca_TokenKind_shr_eq = 47,
    zS_89baa7c0_facdb0ca_TokenKind_dot_dot = 48,
    zS_89baa7c0_facdb0ca_TokenKind_dot_dot_dot = 49,
    zS_89baa7c0_facdb0ca_TokenKind_dot_lbrace = 50,
    zS_89baa7c0_facdb0ca_TokenKind_dot_star = 51,
    zS_89baa7c0_facdb0ca_TokenKind_fat_arrow = 52,
    zS_89baa7c0_facdb0ca_TokenKind_kw_const = 53,
    zS_89baa7c0_facdb0ca_TokenKind_kw_var = 54,
    zS_89baa7c0_facdb0ca_TokenKind_kw_fn = 55,
    zS_89baa7c0_facdb0ca_TokenKind_kw_pub = 56,
    zS_89baa7c0_facdb0ca_TokenKind_kw_extern = 57,
    zS_89baa7c0_facdb0ca_TokenKind_kw_export = 58,
    zS_89baa7c0_facdb0ca_TokenKind_kw_test = 59,
    zS_89baa7c0_facdb0ca_TokenKind_kw_struct = 60,
    zS_89baa7c0_facdb0ca_TokenKind_kw_enum = 61,
    zS_89baa7c0_facdb0ca_TokenKind_kw_union = 62,
    zS_89baa7c0_facdb0ca_TokenKind_kw_if = 63,
    zS_89baa7c0_facdb0ca_TokenKind_kw_else = 64,
    zS_89baa7c0_facdb0ca_TokenKind_kw_while = 65,
    zS_89baa7c0_facdb0ca_TokenKind_kw_for = 66,
    zS_89baa7c0_facdb0ca_TokenKind_kw_switch = 67,
    zS_89baa7c0_facdb0ca_TokenKind_kw_return = 68,
    zS_89baa7c0_facdb0ca_TokenKind_kw_break = 69,
    zS_89baa7c0_facdb0ca_TokenKind_kw_continue = 70,
    zS_89baa7c0_facdb0ca_TokenKind_kw_defer = 71,
    zS_89baa7c0_facdb0ca_TokenKind_kw_errdefer = 72,
    zS_89baa7c0_facdb0ca_TokenKind_kw_try = 73,
    zS_89baa7c0_facdb0ca_TokenKind_kw_catch = 74,
    zS_89baa7c0_facdb0ca_TokenKind_kw_orelse = 75,
    zS_89baa7c0_facdb0ca_TokenKind_kw_error = 76,
    zS_89baa7c0_facdb0ca_TokenKind_kw_and = 77,
    zS_89baa7c0_facdb0ca_TokenKind_kw_or = 78,
    zS_89baa7c0_facdb0ca_TokenKind_kw_true = 79,
    zS_89baa7c0_facdb0ca_TokenKind_kw_false = 80,
    zS_89baa7c0_facdb0ca_TokenKind_kw_null = 81,
    zS_89baa7c0_facdb0ca_TokenKind_kw_undefined = 82,
    zS_89baa7c0_facdb0ca_TokenKind_kw_unreachable = 83,
    zS_89baa7c0_facdb0ca_TokenKind_kw_void = 84,
    zS_89baa7c0_facdb0ca_TokenKind_kw_bool = 85,
    zS_89baa7c0_facdb0ca_TokenKind_kw_noreturn = 86,
    zS_89baa7c0_facdb0ca_TokenKind_kw_c_char = 87,
    zS_89baa7c0_facdb0ca_TokenKind_eof = 88,
    zS_89baa7c0_facdb0ca_TokenKind_err_token = 89
};
typedef enum zS_89baa7c0_facdb0ca_TokenKind zS_89baa7c0_facdb0ca_TokenKind;

#endif /* ZIG_ENUM_zS_89baa7c0_facdb0ca_TokenKind */

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

#ifndef ZIG_ENUM_zS_a8a3052c_4258ebb9_Prec
#define ZIG_ENUM_zS_a8a3052c_4258ebb9_Prec
enum zS_a8a3052c_4258ebb9_Prec {
    zS_a8a3052c_4258ebb9_Prec_none = 0,
    zS_a8a3052c_4258ebb9_Prec_assignment = 1,
    zS_a8a3052c_4258ebb9_Prec_prec_orelse = 2,
    zS_a8a3052c_4258ebb9_Prec_prec_catch = 3,
    zS_a8a3052c_4258ebb9_Prec_bool_or = 4,
    zS_a8a3052c_4258ebb9_Prec_bool_and = 5,
    zS_a8a3052c_4258ebb9_Prec_comparison = 6,
    zS_a8a3052c_4258ebb9_Prec_bit_or = 7,
    zS_a8a3052c_4258ebb9_Prec_bit_xor = 8,
    zS_a8a3052c_4258ebb9_Prec_bit_and = 9,
    zS_a8a3052c_4258ebb9_Prec_shift = 10,
    zS_a8a3052c_4258ebb9_Prec_additive = 11,
    zS_a8a3052c_4258ebb9_Prec_multiply = 12,
    zS_a8a3052c_4258ebb9_Prec_prefix = 13,
    zS_a8a3052c_4258ebb9_Prec_postfix = 14
};
typedef enum zS_a8a3052c_4258ebb9_Prec zS_a8a3052c_4258ebb9_Prec;

#endif /* ZIG_ENUM_zS_a8a3052c_4258ebb9_Prec */

union zS_89baa7c0_39b0b709_TokenValue;
struct zS_c313e0ed_42ae50fe_FnProto;
struct zS_26b5a9a4_43f95de6_Sand;
struct zS_c313e0ed_6592c721_AstStore;
struct zS_16d7ab7a_840ccd30_U32ArrayList;
struct zS_4c1e99d4_face28fc_InternArrayList;
struct zS_4c1e99d4_67d40cc9_StringInterner;
struct zS_9daadfc5_bac763ac_Diagnostic;
struct zS_9daadfc5_8924c34d_DiagnosticArrayList;
struct zS_2b6fc0a6_c93555ae_SourceFileArrayList;
struct zS_2b6fc0a6_29be27be_SourceManager;
struct zS_9daadfc5_490018d3_DiagnosticCollector;
struct zS_a8a3052c_21144d98_Parser;
struct Arena;
struct zS_89baa7c0_7a3512d8_Token;
struct zS_c313e0ed_f3385aec_AstNode;
struct zS_4c1e99d4_7c9905b1_InternEntry;
struct zS_2b6fc0a6_a270ac29_SourceFile;
struct zS_a8a3052c_244bd7c4_OpInfo;
struct zS_a8a3052c_39daa34f_ParseToken;

#ifndef ZIG_STRUCT_zS_a8a3052c_21144d98_Parser
#define ZIG_STRUCT_zS_a8a3052c_21144d98_Parser
struct zS_a8a3052c_21144d98_Parser {
    struct zS_89baa7c0_7a3512d8_Token* tokens_ptr;
    usize tokens_len;
    unsigned char* source_ptr;
    usize source_len;
    usize pos;
    struct zS_c313e0ed_6592c721_AstStore* store;
    struct zS_4c1e99d4_67d40cc9_StringInterner* interner;
    struct zS_9daadfc5_490018d3_DiagnosticCollector* diag;
    struct zS_26b5a9a4_43f95de6_Sand* allocator;
    unsigned int* child_buf_items;
    usize child_buf_len;
    usize child_buf_capacity;
};

#endif /* ZIG_STRUCT_zS_a8a3052c_21144d98_Parser */

#ifndef ZIG_ERRORUNION_ErrorUnion_u32
#define ZIG_ERRORUNION_ErrorUnion_u32
struct ErrorUnion_u32 {
    union __ErrorData_u32_ParserError {
        int err;
        unsigned int payload;
    } data;
    int is_error;
};
typedef struct ErrorUnion_u32 ErrorUnion_u32;
#endif

#ifndef ZIG_STRUCT_zS_a8a3052c_244bd7c4_OpInfo
#define ZIG_STRUCT_zS_a8a3052c_244bd7c4_OpInfo
struct zS_a8a3052c_244bd7c4_OpInfo {
    enum zS_a8a3052c_4258ebb9_Prec prec;
    int right_assoc;
};

#endif /* ZIG_STRUCT_zS_a8a3052c_244bd7c4_OpInfo */

#ifndef ZIG_STRUCT_zS_a8a3052c_39daa34f_ParseToken
#define ZIG_STRUCT_zS_a8a3052c_39daa34f_ParseToken
struct zS_a8a3052c_39daa34f_ParseToken {
    enum zS_89baa7c0_facdb0ca_TokenKind kind;
    unsigned int span_start;
    unsigned short span_len;
};

#endif /* ZIG_STRUCT_zS_a8a3052c_39daa34f_ParseToken */

#ifndef ZIG_OPTIONAL_Optional_zS_a8a3052c_244bd7c4_OpInfo
#define ZIG_OPTIONAL_Optional_zS_a8a3052c_244bd7c4_OpInfo
struct Optional_zS_a8a3052c_244bd7c4_OpInfo {
    struct zS_a8a3052c_244bd7c4_OpInfo value;
    int has_value;
};
typedef struct Optional_zS_a8a3052c_244bd7c4_OpInfo Optional_zS_a8a3052c_244bd7c4_OpInfo;
#endif

#ifndef ZIG_ERRORUNION_ErrorUnion_zS_a8a3052c_39daa34f_ParseToken
#define ZIG_ERRORUNION_ErrorUnion_zS_a8a3052c_39daa34f_ParseToken
struct ErrorUnion_zS_a8a3052c_39daa34f_ParseToken {
    union __ErrorData_zS_a8a3052c_39daa34f_ParseToken_ParserError {
        int err;
        struct zS_a8a3052c_39daa34f_ParseToken payload;
    } data;
    int is_error;
};
typedef struct ErrorUnion_zS_a8a3052c_39daa34f_ParseToken ErrorUnion_zS_a8a3052c_39daa34f_ParseToken;
#endif

#include "token.h"
#include "ast.h"
#include "allocator.h"
#include "diagnostics.h"
#include "string_interner.h"
#include "growable_array.h"


struct zS_a8a3052c_21144d98_Parser zF_a8a3052c_ce1bae95_parserInit(Slice_zS_89baa7c0_7a3512d8_Token, Slice_u8, struct zS_c313e0ed_6592c721_AstStore*, struct zS_4c1e99d4_67d40cc9_StringInterner*, struct zS_9daadfc5_490018d3_DiagnosticCollector*, struct zS_26b5a9a4_43f95de6_Sand*);
Slice_u8 zF_a8a3052c_ea3de80f_parserTokenText(struct zS_a8a3052c_21144d98_Parser*, struct zS_a8a3052c_39daa34f_ParseToken);
struct zS_89baa7c0_7a3512d8_Token zF_a8a3052c_95e6e4e0_parserPeek(struct zS_a8a3052c_21144d98_Parser*);
struct zS_89baa7c0_7a3512d8_Token zF_a8a3052c_a879fdea_parserPeekN(struct zS_a8a3052c_21144d98_Parser*, usize);
struct zS_89baa7c0_7a3512d8_Token zF_a8a3052c_33256f43_parserAdvance(struct zS_a8a3052c_21144d98_Parser*);
ErrorUnion_zS_a8a3052c_39daa34f_ParseToken zF_a8a3052c_48a6f942_parserExpect(struct zS_a8a3052c_21144d98_Parser*, enum zS_89baa7c0_facdb0ca_TokenKind);
void zF_a8a3052c_3ad126e8_parserAddError(struct zS_a8a3052c_21144d98_Parser*, struct zS_89baa7c0_7a3512d8_Token, Slice_u8);
void zF_a8a3052c_0cd6998b_parserSynchronize(struct zS_a8a3052c_21144d98_Parser*);
ErrorUnion_u32 zF_a8a3052c_c7ea9b4b_parserParseExprPrec(struct zS_a8a3052c_21144d98_Parser*, enum zS_a8a3052c_4258ebb9_Prec);
ErrorUnion_u32 zF_a8a3052c_b05fc3c0_parserParsePrimary(struct zS_a8a3052c_21144d98_Parser*);
unsigned char zF_a8a3052c_f4dd8358_precToInt(enum zS_a8a3052c_4258ebb9_Prec);
enum zS_a8a3052c_4258ebb9_Prec zF_a8a3052c_e02cae07_precFromInt(unsigned char);
Optional_zS_a8a3052c_244bd7c4_OpInfo zF_a8a3052c_f55b638a_getInfixInfo(enum zS_89baa7c0_facdb0ca_TokenKind);

#endif
