#include "compilation_unit.hpp"
#include "parser.hpp"
#include "c89_feature_validator.hpp"
#include "type_checker.hpp"
#include "lifetime_analyzer.hpp"
#include "null_pointer_analyzer.hpp"
#include "double_free_analyzer.hpp"
#include "type_system.hpp"
#include "symbol_table.hpp"
#include "utils.hpp"
#include "platform.hpp"
#include <new>

// Default arena size for the bootstrap compiler: 16MB
static const size_t DEFAULT_ARENA_SIZE = 16 * 1024 * 1024;

/**
 * @brief Executes the full compilation pipeline for a single file.
 */
RETR_UNUSED_FUNC static bool runCompilationPipeline(CompilationUnit& unit, u32 file_id) {
    bool pipeline_success = unit.performFullPipeline(file_id);

    if (unit.getErrorHandler().hasErrors()) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!pipeline_success) {
        return false;
    }

    if (!unit.areErrorTypesEliminated()) {
        unit.getErrorHandler().report(ERR_INTERNAL_ERROR, SourceLocation(), ErrorHandler::getMessage(ERR_INTERNAL_ERROR), "Error types were not effectively eliminated during validation.");
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (unit.getErrorHandler().hasWarnings()) {
        unit.getErrorHandler().printWarnings();
    }

    return true;
}

#ifndef Z98_TEST
int main(int argc, char* argv[]) {
    bool debug_lifter = false;
    bool debug_codegen = false;
    bool no_logs = false;
    bool verbose = false;
    bool warn_arena_leaks = false;
    bool header_priority_include = false;
    const char* log_file_path = NULL;

    for (int i = 1; i < argc; ++i) {
        if (plat_strcmp(argv[i], "--no-logs") == 0) {
            no_logs = true;
        } else if (plat_strcmp(argv[i], "--header-priority-include") == 0) {
            header_priority_include = true;
        } else if (plat_strcmp(argv[i], "--verbose") == 0 || plat_strcmp(argv[i], "-v") == 0) {
            verbose = true;
        } else if (plat_strcmp(argv[i], "-Warena-leak") == 0) {
            warn_arena_leaks = true;
        } else if (plat_strncmp(argv[i], "--log-file=", 11) == 0) {
            log_file_path = argv[i] + 11;
        }
    }

    if (argc >= 2 && plat_strcmp(argv[1], "--self-test") == 0) {
        ArenaAllocator logger_arena(1024 * 1024);
        Logger* logger = new (logger_arena.alloc(sizeof(Logger))) Logger(logger_arena, !no_logs, log_file_path);
        logger->setSuppressAll(no_logs);
        logger->setVerbose(verbose);
        plat_set_logger(logger);

        plat_print_info("Executing self-test...\n");

        const char* source =
            "fn my_func() -> void {\n"
            "    var p: *u8 = arena_alloc_default(100u);\n"
            "    arena_free(p);\n"
            "    arena_free(p); // Double free\n"
            "}\n"
            "fn null_test() -> void {\n"
            "    var p: *i32 = null;\n"
            "    p.* = 10; // Null dereference\n"
            "}\n"
            "fn lifetime_test() -> *i32 {\n"
            "    var x: i32 = 10;\n"
            "    return &x; // Lifetime violation\n"
            "}\n";

        ArenaAllocator arena(1024 * 1024); // 1MB for self-test
        StringInterner interner(arena);
        CompilationUnit unit(arena, interner);

        CompilationOptions opts;
        opts.enable_double_free_analysis = true;
        opts.enable_null_pointer_analysis = true;
        opts.enable_lifetime_analysis = true;
        opts.debug_lifter = debug_lifter;
        opts.debug_codegen = debug_codegen;
        unit.setOptions(opts);

        u32 file_id = unit.addSource("self_test.zig", source);

        if (runCompilationPipeline(unit, file_id)) {
            // We expect an error in this self-test because of the double free
            plat_print_error("Self-test failed: expected double free error not detected.\n");
            Logger* logger = plat_get_logger();
            if (logger) logger->flush();
            return 1;
        }

        bool has_double_free = false;
        bool has_null_deref = false;
        bool has_lifetime_violation = false;
        const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
        for (size_t i = 0; i < errors.length(); ++i) {
            if (errors[i].code == ERR_DOUBLE_FREE) has_double_free = true;
            if (errors[i].code == ERR_NULL_POINTER_DEREFERENCE) has_null_deref = true;
            if (errors[i].code == ERR_LIFETIME_VIOLATION) has_lifetime_violation = true;
        }

        if (has_double_free && has_null_deref && has_lifetime_violation) {
            plat_print_info("Self-test passed: All memory safety violations correctly detected.\n");
            Logger* logger = plat_get_logger();
            if (logger) logger->flush();
            return 0;
        } else {
            if (!has_double_free) plat_print_error("Self-test failed: ERR_DOUBLE_FREE not detected.\n");
            if (!has_null_deref) plat_print_error("Self-test failed: ERR_NULL_POINTER_DEREFERENCE not detected.\n");
            if (!has_lifetime_violation) plat_print_error("Self-test failed: ERR_LIFETIME_VIOLATION not detected.\n");
            Logger* logger = plat_get_logger();
            if (logger) logger->flush();
            return 1;
        }
    }

    const char* input_file = NULL;
    const char* output_file = NULL;
    bool parse_only = false;
    bool full_pipeline = false;
    bool test_mode = false;
    bool win_line_endings = false;
    RETR_UNUSED(full_pipeline);

    // We'll use a simple fixed-size array for temporary include path storage
    // before the CompilationUnit is created.
    const char* temp_include_paths[64];
    int include_path_count = 0;

    for (int i = 1; i < argc; ++i) {
        if (plat_strcmp(argv[i], "-o") == 0) {
            if (i + 1 < argc) output_file = argv[++i];
        } else if (plat_strcmp(argv[i], "--debug-lifter") == 0) {
            debug_lifter = true;
        } else if (plat_strcmp(argv[i], "--debug-codegen") == 0) {
            debug_codegen = true;
        } else if (plat_strcmp(argv[i], "-I") == 0) {
            if (i + 1 < argc && include_path_count < 64) {
                temp_include_paths[include_path_count++] = argv[++i];
            }
        } else if (plat_strcmp(argv[i], "--test-mode") == 0) {
            test_mode = true;
        } else if (plat_strcmp(argv[i], "--win-line-endings") == 0) {
            win_line_endings = true;
        } else if (plat_strcmp(argv[i], "parse") == 0) {
            parse_only = true;
            if (i + 1 < argc) input_file = argv[++i];
        } else if (plat_strcmp(argv[i], "--compile") == 0 || plat_strcmp(argv[i], "full_pipeline") == 0) {
            full_pipeline = true;
            if (i + 1 < argc) input_file = argv[++i];
        } else if (plat_strncmp(argv[i], "--log-file=", 11) == 0 ||
                   plat_strcmp(argv[i], "--no-logs") == 0 ||
                   plat_strcmp(argv[i], "--header-priority-include") == 0 ||
                   plat_strcmp(argv[i], "--verbose") == 0 ||
                   plat_strcmp(argv[i], "-v") == 0) {
            // Already handled in first pass
        } else if (input_file == NULL) {
            input_file = argv[i];
            full_pipeline = true;
        }
    }

    if (input_file) {
        char* source = NULL;
        size_t size = 0;
        if (!plat_file_read(input_file, &source, &size)) {
            plat_print_error("Could not read file: ");
            plat_print_error(input_file);
            plat_print_error("\n");
            return 1;
        }

        ArenaAllocator arena(DEFAULT_ARENA_SIZE);

        Logger* logger = new (arena.alloc(sizeof(Logger))) Logger(arena, !no_logs, log_file_path);
        logger->setSuppressAll(no_logs);
        logger->setVerbose(verbose);
        plat_set_logger(logger);

        StringInterner interner(arena);
        CompilationUnit unit(arena, interner);

        for (int i = 0; i < include_path_count; ++i) {
            unit.addIncludePath(temp_include_paths[i]);
        }

        unit.injectRuntimeSymbols();
        unit.setTestMode(test_mode);

        CompilationOptions opts;
        opts.enable_double_free_analysis = true;
        opts.enable_null_pointer_analysis = true;
        opts.enable_lifetime_analysis = true;
        opts.debug_lifter = debug_lifter;
        opts.debug_codegen = debug_codegen;
        opts.win_friendly_line_endings = win_line_endings;
        opts.no_logs = no_logs;
        opts.verbose = verbose;
        opts.warn_arena_leaks = warn_arena_leaks;
        opts.header_include_before_defs = header_priority_include;
        opts.log_file_path = log_file_path;
        unit.setOptions(opts);

        u32 file_id = unit.addSource(input_file, source);

        bool success = false;
        if (parse_only) {
            Parser* parser = unit.createParser(file_id);
            ASTNode* ast = parser->parse();
            success = (ast != NULL);
            unit.finalizeParsing();
        } else {
            success = runCompilationPipeline(unit, file_id);
            if (success && output_file) {
                success = unit.generateCode(output_file);
            }
            unit.finalizeParsing();
        }

        plat_free(source);
        if (logger) logger->flush();
        return success ? 0 : 1;
    }

    plat_print_info("Z98 Compiler v0.0.1\n");
    plat_print_info("Usage: z98 [options] <filename>\n");
    plat_print_info("Options:\n");
    plat_print_info("  --self-test             Run internal self-tests\n");
    plat_print_info("  -o <file>               Specify output C file\n");
    plat_print_info("  -I <path>               Add include search path\n");
    plat_print_info("  --test-mode             Enable deterministic name mangling for tests\n");
    plat_print_info("  --debug-lifter          Enable debug logging in AST lifter\n");
    plat_print_info("  --debug-codegen         Enable debug tracing in C89 code generator\n");
    plat_print_info("  --win-line-endings      Use CRLF line endings in generated C code\n");
    plat_print_info("  --log-file=<path>       Enable logging to a file\n");
    plat_print_info("  --no-logs               Suppress all non-essential output\n");
    plat_print_info("  --verbose, -v           Enable verbose debug logging on console\n");
    plat_print_info("  -Warena-leak            Report memory leaks for arena allocations\n");
    plat_print_info("  --header-priority-include  Emit #includes before type definitions in headers\n");
    plat_print_info("  parse <file>            Parse only\n");
    plat_print_info("  full_pipeline <file>    Execute full pipeline and optionally generate code\n");

    return 0;
}
#endif
