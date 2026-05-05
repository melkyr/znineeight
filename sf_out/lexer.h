#ifndef ZIG_MODULE_LEXER_H
#define ZIG_MODULE_LEXER_H

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

#ifndef ZIG_ENUM_zS_9daadfc5_040cd516_ErrorCode
#define ZIG_ENUM_zS_9daadfc5_040cd516_ErrorCode
enum zS_9daadfc5_040cd516_ErrorCode {
    zS_9daadfc5_040cd516_ErrorCode_ERR_1000_UNTERMINATED_STRING = 0,
    zS_9daadfc5_040cd516_ErrorCode_ERR_1001_UNTERMINATED_BLOCK_COMMENT = 1,
    zS_9daadfc5_040cd516_ErrorCode_ERR_1002_INVALID_CHAR_LITERAL = 2,
    zS_9daadfc5_040cd516_ErrorCode_ERR_1003_INVALID_ESCAPE = 3,
    zS_9daadfc5_040cd516_ErrorCode_ERR_1004_BARE_AT_SIGN = 4,
    zS_9daadfc5_040cd516_ErrorCode_ERR_1005_UNRECOGNIZED_CHAR = 5,
    zS_9daadfc5_040cd516_ErrorCode_WARN_1010_UNRECOGNIZED_ESCAPE = 6,
    zS_9daadfc5_040cd516_ErrorCode_WARN_1011_INTEGER_OVERFLOW = 7,
    zS_9daadfc5_040cd516_ErrorCode_ERR_2000_UNEXPECTED_TOKEN = 8,
    zS_9daadfc5_040cd516_ErrorCode_ERR_2001_MISSING_SEMICOLON = 9,
    zS_9daadfc5_040cd516_ErrorCode_ERR_2002_UNCLOSED_BRACE = 10,
    zS_9daadfc5_040cd516_ErrorCode_ERR_2003_EXPECTED_EXPRESSION = 11,
    zS_9daadfc5_040cd516_ErrorCode_ERR_2004_EXPECTED_TYPE = 12,
    zS_9daadfc5_040cd516_ErrorCode_WARN_2010_DEPRECATED_SYNTAX = 13,
    zS_9daadfc5_040cd516_ErrorCode_ERR_3000_TYPE_MISMATCH = 14,
    zS_9daadfc5_040cd516_ErrorCode_ERR_3001_UNDEFINED_SYMBOL = 15,
    zS_9daadfc5_040cd516_ErrorCode_ERR_3002_INVALID_ASSIGNMENT = 16,
    zS_9daadfc5_040cd516_ErrorCode_ERR_3003_MISSING_RETURN = 17,
    zS_9daadfc5_040cd516_ErrorCode_ERR_3004_SWITCH_NOT_EXHAUSTIVE = 18,
    zS_9daadfc5_040cd516_ErrorCode_ERR_3005_CIRCULAR_TYPE_DEPENDENCY = 19,
    zS_9daadfc5_040cd516_ErrorCode_ERR_3006_INVALID_COERCION = 20,
    zS_9daadfc5_040cd516_ErrorCode_WARN_3010_UNUSED_VARIABLE = 21,
    zS_9daadfc5_040cd516_ErrorCode_WARN_3011_UNREACHABLE_CODE = 22,
    zS_9daadfc5_040cd516_ErrorCode_ERR_4000_INVALID_CONTROL_FLOW = 23,
    zS_9daadfc5_040cd516_ErrorCode_ERR_4001_UNRESOLVED_TYPE_IN_LOWER = 24,
    zS_9daadfc5_040cd516_ErrorCode_ERR_4002_DEFER_IN_INVALID_SCOPE = 25,
    zS_9daadfc5_040cd516_ErrorCode_ERR_5000_C89_UNSUPPORTED_FEATURE = 26,
    zS_9daadfc5_040cd516_ErrorCode_ERR_5001_MANGLE_OVERFLOW = 27,
    zS_9daadfc5_040cd516_ErrorCode_ERR_5002_EMPTY_AGGREGATE = 28,
    zS_9daadfc5_040cd516_ErrorCode_ERR_9000_OOM = 29,
    zS_9daadfc5_040cd516_ErrorCode_ERR_9001_ICE = 30,
    zS_9daadfc5_040cd516_ErrorCode_ERR_9999_TOO_MANY_ERRORS = 31
};
typedef enum zS_9daadfc5_040cd516_ErrorCode zS_9daadfc5_040cd516_ErrorCode;

#endif /* ZIG_ENUM_zS_9daadfc5_040cd516_ErrorCode */

struct zS_26b5a9a4_43f95de6_Sand;
struct zS_16d7ab7a_840ccd30_U32ArrayList;
struct zS_4c1e99d4_face28fc_InternArrayList;
struct zS_4c1e99d4_67d40cc9_StringInterner;
struct Arena;
struct zS_9daadfc5_bac763ac_Diagnostic;
struct zS_9daadfc5_8924c34d_DiagnosticArrayList;
struct zS_2b6fc0a6_c93555ae_SourceFileArrayList;
struct zS_2b6fc0a6_29be27be_SourceManager;
struct zS_9daadfc5_490018d3_DiagnosticCollector;
struct zS_16d7ab7a_95cf740f_U8ArrayList;
union zS_89baa7c0_39b0b709_TokenValue;
struct zS_4c1e99d4_7c9905b1_InternEntry;
struct zS_2b6fc0a6_a270ac29_SourceFile;
struct zS_a012675f_c8a65756_Lexer;
struct zS_89baa7c0_7a3512d8_Token;

#ifndef ZIG_STRUCT_zS_a012675f_c8a65756_Lexer
#define ZIG_STRUCT_zS_a012675f_c8a65756_Lexer
struct zS_a012675f_c8a65756_Lexer {
    Slice_u8 source;
    usize pos;
    unsigned int line;
    unsigned int col;
    unsigned int file_id;
    struct zS_4c1e99d4_67d40cc9_StringInterner* interner;
    struct zS_9daadfc5_490018d3_DiagnosticCollector* diag;
    struct zS_16d7ab7a_95cf740f_U8ArrayList* string_buf;
};

#endif /* ZIG_STRUCT_zS_a012675f_c8a65756_Lexer */

#include "token.h"
#include "string_interner.h"
#include "diagnostics.h"
#include "allocator.h"
#include "growable_array.h"
#include "pal.h"
#include "source_manager.h"
#include "lexer_tests.h"


struct zS_a012675f_c8a65756_Lexer zF_a012675f_e7d69f49_lexerInit(Slice_u8, unsigned int, struct zS_4c1e99d4_67d40cc9_StringInterner*, struct zS_9daadfc5_490018d3_DiagnosticCollector*, struct zS_26b5a9a4_43f95de6_Sand*);
struct zS_89baa7c0_7a3512d8_Token zF_a012675f_2bdcba5b_lexerNextToken(struct zS_a012675f_c8a65756_Lexer*);
void zF_a012675f_b7310084_lexerRunAllTests(void);
void zF_a012675f_448880f3_lexerTestSanityCheck(void);

#endif
