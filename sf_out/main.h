#ifndef ZIG_MODULE_MAIN_H
#define ZIG_MODULE_MAIN_H

#include "zig_runtime.h"
#include "zig_special_types.h"

#ifndef ZIG_ENUM_zS_127049be_b8a04c98_ColorMode
#define ZIG_ENUM_zS_127049be_b8a04c98_ColorMode
enum zS_127049be_b8a04c98_ColorMode {
    zS_127049be_b8a04c98_ColorMode_auto = 0,
    zS_127049be_b8a04c98_ColorMode_always = 1,
    zS_127049be_b8a04c98_ColorMode_never = 2
};
typedef enum zS_127049be_b8a04c98_ColorMode zS_127049be_b8a04c98_ColorMode;

#endif /* ZIG_ENUM_zS_127049be_b8a04c98_ColorMode */

#ifndef ZIG_ENUM_zS_127049be_b6e8e37d_ErrorFormat
#define ZIG_ENUM_zS_127049be_b6e8e37d_ErrorFormat
enum zS_127049be_b6e8e37d_ErrorFormat {
    zS_127049be_b6e8e37d_ErrorFormat_human = 0,
    zS_127049be_b6e8e37d_ErrorFormat_json = 1,
    zS_127049be_b6e8e37d_ErrorFormat_sarif = 2
};
typedef enum zS_127049be_b6e8e37d_ErrorFormat zS_127049be_b6e8e37d_ErrorFormat;

#endif /* ZIG_ENUM_zS_127049be_b6e8e37d_ErrorFormat */

struct zS_26b5a9a4_43f95de6_Sand;
struct zS_16d7ab7a_840ccd30_U32ArrayList;
struct zS_4c1e99d4_face28fc_InternArrayList;
struct zS_4c1e99d4_67d40cc9_StringInterner;
struct zS_2b6fc0a6_c93555ae_SourceFileArrayList;
struct zS_2b6fc0a6_29be27be_SourceManager;
struct zS_9daadfc5_bac763ac_Diagnostic;
struct zS_9daadfc5_8924c34d_DiagnosticArrayList;
struct zS_9daadfc5_490018d3_DiagnosticCollector;
struct zS_ab5e085b_2cf354c9_NameMangler;
struct Arena;
struct zS_16d7ab7a_95cf740f_U8ArrayList;
struct zS_4c1e99d4_7c9905b1_InternEntry;
struct zS_2b6fc0a6_a270ac29_SourceFile;
struct zS_a012675f_c8a65756_Lexer;
struct zS_127049be_a3e1e511_CompilerCli;
struct zS_26b5a9a4_d34e314a_CompilerAlloc;
struct zS_127049be_ec2a6e74_CompilerContext;

#ifndef ZIG_STRUCT_zS_127049be_a3e1e511_CompilerCli
#define ZIG_STRUCT_zS_127049be_a3e1e511_CompilerCli
struct zS_127049be_a3e1e511_CompilerCli {
    Slice_u8 input_file;
    Slice_u8 output_dir;
    int dump_tokens;
    int dump_ast;
    int dump_types;
    int dump_lir;
    unsigned int max_mem;
    unsigned int max_errors;
    enum zS_127049be_b8a04c98_ColorMode color;
    enum zS_127049be_b6e8e37d_ErrorFormat error_format;
    int warnings_as_errors;
    int quiet;
    int test_mode;
    int sanity_test_mode;
    int track_memory;
    Slice_u8 include_dirs[16];
    unsigned int include_count;
};

#endif /* ZIG_STRUCT_zS_127049be_a3e1e511_CompilerCli */

#ifndef ZIG_STRUCT_zS_127049be_ec2a6e74_CompilerContext
#define ZIG_STRUCT_zS_127049be_ec2a6e74_CompilerContext
struct zS_127049be_ec2a6e74_CompilerContext {
    struct zS_127049be_a3e1e511_CompilerCli cli;
    struct zS_26b5a9a4_d34e314a_CompilerAlloc* alloc;
    struct zS_4c1e99d4_67d40cc9_StringInterner* interner;
    struct zS_9daadfc5_490018d3_DiagnosticCollector* diag;
    struct zS_2b6fc0a6_29be27be_SourceManager* source_man;
    struct zS_ab5e085b_2cf354c9_NameMangler* name_mangler;
};

#endif /* ZIG_STRUCT_zS_127049be_ec2a6e74_CompilerContext */

#include "allocator.h"
#include "string_interner.h"
#include "source_manager.h"
#include "diagnostics.h"
#include "name_mangler.h"
#include "token.h"
#include "dump.h"
#include "lexer.h"
#include "pal.h"
#include "parser.h"
#include "ast.h"


int main(int argc, char* argv[]);

#endif
