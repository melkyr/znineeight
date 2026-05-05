#ifndef ZIG_MODULE_DIAGNOSTICS_H
#define ZIG_MODULE_DIAGNOSTICS_H

#include "zig_runtime.h"
#include "zig_special_types.h"

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

#ifndef ZIG_ENUM_zS_9daadfc5_0c80a972_DiagnosticLevel
#define ZIG_ENUM_zS_9daadfc5_0c80a972_DiagnosticLevel
enum zS_9daadfc5_0c80a972_DiagnosticLevel {
    zS_9daadfc5_0c80a972_DiagnosticLevel_err_lvl = 0,
    zS_9daadfc5_0c80a972_DiagnosticLevel_warning = 1,
    zS_9daadfc5_0c80a972_DiagnosticLevel_info = 2,
    zS_9daadfc5_0c80a972_DiagnosticLevel_note = 3
};
typedef enum zS_9daadfc5_0c80a972_DiagnosticLevel zS_9daadfc5_0c80a972_DiagnosticLevel;

#endif /* ZIG_ENUM_zS_9daadfc5_0c80a972_DiagnosticLevel */

struct zS_9daadfc5_bac763ac_Diagnostic;
struct zS_26b5a9a4_43f95de6_Sand;
struct zS_9daadfc5_8924c34d_DiagnosticArrayList;
struct zS_16d7ab7a_840ccd30_U32ArrayList;
struct zS_2b6fc0a6_c93555ae_SourceFileArrayList;
struct zS_2b6fc0a6_29be27be_SourceManager;
struct zS_4c1e99d4_face28fc_InternArrayList;
struct zS_4c1e99d4_67d40cc9_StringInterner;
struct zS_9daadfc5_490018d3_DiagnosticCollector;
struct Arena;
struct zS_2b6fc0a6_c7df22f9_Location;
struct zS_2b6fc0a6_a270ac29_SourceFile;
struct zS_4c1e99d4_7c9905b1_InternEntry;

#ifndef ZIG_STRUCT_zS_9daadfc5_bac763ac_Diagnostic
#define ZIG_STRUCT_zS_9daadfc5_bac763ac_Diagnostic
struct zS_9daadfc5_bac763ac_Diagnostic {
    unsigned char level;
    unsigned short code;
    unsigned int file_id;
    unsigned int span_start;
    unsigned int span_end;
    unsigned int message_id;
    unsigned char note_count;
    unsigned int note_ids[3];
};

#endif /* ZIG_STRUCT_zS_9daadfc5_bac763ac_Diagnostic */

#ifndef ZIG_STRUCT_zS_9daadfc5_8924c34d_DiagnosticArrayList
#define ZIG_STRUCT_zS_9daadfc5_8924c34d_DiagnosticArrayList
struct zS_9daadfc5_8924c34d_DiagnosticArrayList {
    struct zS_9daadfc5_bac763ac_Diagnostic* items;
    usize len;
    usize capacity;
    struct zS_26b5a9a4_43f95de6_Sand* allocator;
};

#endif /* ZIG_STRUCT_zS_9daadfc5_8924c34d_DiagnosticArrayList */

#ifndef ZIG_STRUCT_zS_9daadfc5_490018d3_DiagnosticCollector
#define ZIG_STRUCT_zS_9daadfc5_490018d3_DiagnosticCollector
struct zS_9daadfc5_490018d3_DiagnosticCollector {
    struct zS_9daadfc5_8924c34d_DiagnosticArrayList* diagnostics;
    struct zS_26b5a9a4_43f95de6_Sand* allocator;
    struct zS_2b6fc0a6_29be27be_SourceManager* source_manager;
    struct zS_4c1e99d4_67d40cc9_StringInterner* interner;
    usize error_count;
    usize warning_count;
    usize max_diagnostics;
};

#endif /* ZIG_STRUCT_zS_9daadfc5_490018d3_DiagnosticCollector */

#include "allocator.h"
#include "source_manager.h"
#include "mem.h"
#include "string_interner.h"
#include "pal.h"

extern const unsigned short zC_9daadfc5_88ccf5b7_ERR_1000_UNTERMINATED_STRING;
extern const unsigned short zC_9daadfc5_cfecd254_1001_UNTERMINATED_BLOCK_COMMENT;
extern const unsigned short zC_9daadfc5_eb956f85_ERR_1002_INVALID_CHAR_LITERAL;
extern const unsigned short zC_9daadfc5_e57f8393_ERR_1003_INVALID_ESCAPE;
extern const unsigned short zC_9daadfc5_ffecce4b_ERR_1004_BARE_AT_SIGN;
extern const unsigned short zC_9daadfc5_d74828fa_ERR_1005_UNRECOGNIZED_CHAR;
extern const unsigned short zC_9daadfc5_164aa48c_WARN_1010_UNRECOGNIZED_ESCAPE;
extern const unsigned short zC_9daadfc5_247cc8b1_WARN_1011_INTEGER_OVERFLOW;
extern const usize zC_9daadfc5_026c1e34_MAX_DIAGNOSTICS;

struct zS_9daadfc5_8924c34d_DiagnosticArrayList zF_9daadfc5_aa9157ce_diagnosticArrayListInit(struct zS_26b5a9a4_43f95de6_Sand*);
void zF_9daadfc5_0800ad7e_agnosticArrayListEnsureCapacity(struct zS_9daadfc5_8924c34d_DiagnosticArrayList*, usize);
void zF_9daadfc5_07a08eec_diagnosticArrayListAppend(struct zS_9daadfc5_8924c34d_DiagnosticArrayList*, struct zS_9daadfc5_bac763ac_Diagnostic);
Slice_zS_9daadfc5_bac763ac_Diagnostic zF_9daadfc5_3c86285a_diagnosticArrayListGetSlice(struct zS_9daadfc5_8924c34d_DiagnosticArrayList*);
struct zS_9daadfc5_490018d3_DiagnosticCollector zF_9daadfc5_178b11e8_diagnosticCollectorInit(struct zS_26b5a9a4_43f95de6_Sand*, struct zS_2b6fc0a6_29be27be_SourceManager*, struct zS_4c1e99d4_67d40cc9_StringInterner*);
unsigned int zF_9daadfc5_116b4422_diagnosticCollectorIntern(struct zS_9daadfc5_490018d3_DiagnosticCollector*, Slice_u8);
void zF_9daadfc5_b5a4ed39_diagnosticCollectorAdd(struct zS_9daadfc5_490018d3_DiagnosticCollector*, unsigned char, unsigned short, unsigned int, unsigned int, unsigned int, Slice_u8);
int zF_9daadfc5_b734257d_diagnosticCollectorHasErrors(struct zS_9daadfc5_490018d3_DiagnosticCollector*);
unsigned int zF_9daadfc5_736f6f1b_diagnosticCollectorErrorCount(struct zS_9daadfc5_490018d3_DiagnosticCollector*);
unsigned int zF_9daadfc5_3ff34e2d_diagnosticCollectorWarningCount(struct zS_9daadfc5_490018d3_DiagnosticCollector*);
void zF_9daadfc5_3ea45a74_diagnosticCollectorPrintAll(struct zS_9daadfc5_490018d3_DiagnosticCollector*);

#endif
