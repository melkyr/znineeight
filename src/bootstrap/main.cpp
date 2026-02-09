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

// Default arena size for the bootstrap compiler: 16MB
static const size_t DEFAULT_ARENA_SIZE = 16 * 1024 * 1024;

/**
 * @brief Executes the full compilation pipeline for a single file.
 */
static bool runCompilationPipeline(CompilationUnit& unit, u32 file_id) {
    if (!unit.performFullPipeline(file_id)) {
        return false;
    }

    if (unit.getErrorHandler().hasErrors()) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.areErrorTypesEliminated()) {
        unit.getErrorHandler().report(ERR_INTERNAL_ERROR, SourceLocation(), "Error types were not effectively eliminated during validation.");
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (unit.getErrorHandler().hasWarnings()) {
        unit.getErrorHandler().printWarnings();
    }

    return true;
}

int main(int argc, char* argv[]) {
    if (argc >= 2 && plat_strcmp(argv[1], "--self-test") == 0) {
        plat_print_info("Executing self-test...\n");

        const char* source =
            "fn my_func() -> void {\n"
            "    var p: *u8 = arena_alloc(100u);\n"
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

        unit.injectRuntimeSymbols();

        CompilationOptions opts;
        opts.enable_double_free_analysis = true;
        opts.enable_null_pointer_analysis = true;
        opts.enable_lifetime_analysis = true;
        unit.setOptions(opts);

        u32 file_id = unit.addSource("self_test.zig", source);

        if (runCompilationPipeline(unit, file_id)) {
            // We expect an error in this self-test because of the double free
            plat_print_error("Self-test failed: expected double free error not detected.\n");
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
            return 0;
        } else {
            if (!has_double_free) plat_print_error("Self-test failed: ERR_DOUBLE_FREE not detected.\n");
            if (!has_null_deref) plat_print_error("Self-test failed: ERR_NULL_POINTER_DEREFERENCE not detected.\n");
            if (!has_lifetime_violation) plat_print_error("Self-test failed: ERR_LIFETIME_VIOLATION not detected.\n");
            return 1;
        }
    }

    if (argc >= 3 && (plat_strcmp(argv[1], "--compile") == 0 ||
                     plat_strcmp(argv[1], "parse") == 0 ||
                     plat_strcmp(argv[1], "full_pipeline") == 0)) {
        const char* filename = argv[2];
        char* source = NULL;
        size_t size = 0;
        if (!plat_file_read(filename, &source, &size)) {
            plat_print_error("Could not read file: ");
            plat_print_error(filename);
            plat_print_error("\n");
            return 1;
        }

        // Use default 16MB arena to match project goals
        ArenaAllocator arena(DEFAULT_ARENA_SIZE);
        StringInterner interner(arena);
        CompilationUnit unit(arena, interner);

        unit.injectRuntimeSymbols();

        CompilationOptions opts;
        opts.enable_double_free_analysis = true;
        opts.enable_null_pointer_analysis = true;
        opts.enable_lifetime_analysis = true;
        unit.setOptions(opts);

        u32 file_id = unit.addSource(filename, source);

        bool success = false;
        if (plat_strcmp(argv[1], "parse") == 0) {
            Parser* parser = unit.createParser(file_id);
            ASTNode* ast = parser->parse();
            success = (ast != NULL);
        } else {
            success = runCompilationPipeline(unit, file_id);
        }

        plat_free(source);
        return success ? 0 : 1;
    }

    plat_print_info("RetroZig Compiler v0.0.1\n");
    plat_print_info("Usage: retrozig [options]\n");
    plat_print_info("Options:\n");
    plat_print_info("  --self-test             Run internal self-tests\n");
    plat_print_info("  --compile <filename>    Compile a Zig source file\n");
    plat_print_info("  parse <filename>        Parse only\n");
    plat_print_info("  full_pipeline <filename> Execute full pipeline\n");

    return 0;
}
