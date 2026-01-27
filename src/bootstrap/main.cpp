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
#include <iostream>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <new>

// Helper to read a file into a buffer
static char* readEntireFile(const char* path) {
    FILE* file = fopen(path, "rb");
    if (!file) return NULL;
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    fseek(file, 0, SEEK_SET);
    char* buffer = (char*)malloc(length + 1);
    if (!buffer) {
        fclose(file);
        return NULL;
    }
    size_t read = fread(buffer, 1, (size_t)length, file);
    buffer[read] = '\0';
    fclose(file);
    return buffer;
}

/**
 * @brief Executes the full compilation pipeline for a single file.
 */
static bool runCompilationPipeline(CompilationUnit& unit, u32 file_id) {
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    if (!ast) {
        return false;
    }

    // Pass 0: Type Checking (resolves !T -> TYPE_ERROR_UNION)
    TypeChecker checker(unit);
    checker.check(ast);

    // Pass 1: C89 feature validation (detects error returns via resolved types)
    C89FeatureValidator validator(unit);
    validator.validate(ast);

    const CompilationOptions& opts = unit.getOptions();

    // Pass 2: Lifetime Analysis
    if (opts.enable_lifetime_analysis) {
        LifetimeAnalyzer analyzer(unit);
        analyzer.analyze(ast);
    }

    // Pass 3: Null Pointer Analysis
    if (opts.enable_null_pointer_analysis) {
        NullPointerAnalyzer analyzer(unit);
        analyzer.analyze(ast);
    }

    // Pass 4: Double Free Detection
    if (opts.enable_double_free_analysis) {
        DoubleFreeAnalyzer analyzer(unit);
        analyzer.analyze(ast);
    }

    if (unit.getErrorHandler().hasErrors()) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (unit.getErrorHandler().hasWarnings()) {
        unit.getErrorHandler().printWarnings();
    }

    return true;
}

int main(int argc, char* argv[]) {
    if (argc >= 2 && strcmp(argv[1], "--self-test") == 0) {
        std::cout << "Executing self-test..." << std::endl;

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
            std::cout << "Self-test failed: expected double free error not detected." << std::endl;
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
            std::cout << "Self-test passed: All memory safety violations correctly detected." << std::endl;
            return 0;
        } else {
            if (!has_double_free) std::cout << "Self-test failed: ERR_DOUBLE_FREE not detected." << std::endl;
            if (!has_null_deref) std::cout << "Self-test failed: ERR_NULL_POINTER_DEREFERENCE not detected." << std::endl;
            if (!has_lifetime_violation) std::cout << "Self-test failed: ERR_LIFETIME_VIOLATION not detected." << std::endl;
            return 1;
        }
    }

    if (argc >= 3 && strcmp(argv[1], "--compile") == 0) {
        const char* filename = argv[2];
        char* source = readEntireFile(filename);
        if (!source) {
            std::cerr << "Could not read file: " << filename << std::endl;
            return 1;
        }

        ArenaAllocator arena(1024 * 1024); // 1MB for now
        StringInterner interner(arena);
        CompilationUnit unit(arena, interner);

        unit.injectRuntimeSymbols();

        CompilationOptions opts;
        opts.enable_double_free_analysis = true;
        opts.enable_null_pointer_analysis = true;
        opts.enable_lifetime_analysis = true;
        unit.setOptions(opts);

        u32 file_id = unit.addSource(filename, source);
        bool success = runCompilationPipeline(unit, file_id);

        free(source);
        return success ? 0 : 1;
    }

    std::cout << "RetroZig Compiler v0.0.1" << std::endl;
    std::cout << "Usage: retrozig [options]" << std::endl;
    std::cout << "Options:" << std::endl;
    std::cout << "  --self-test             Run internal self-tests" << std::endl;
    std::cout << "  --compile <filename>    Compile a Zig source file" << std::endl;

    return 0;
}
