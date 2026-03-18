#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file array_property_tests.cpp
 * @brief Integration tests for array built-in properties (.len).
 */

TEST_FUNC(ArrayProperty_Len) {
    const char* source =
        "fn foo() void {\n"
        "    var arr: [5]i32 = undefined;\n"
        "    var x: usize = arr.len;\n"
        "    var ptr: *[10]u8 = undefined;\n"
        "    var y: usize = ptr.len;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for array .len:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTVarDeclNode* x_decl = unit.extractVariableDeclaration("x");
    if (!x_decl || !x_decl->initializer || x_decl->initializer->type != NODE_INTEGER_LITERAL) {
        printf("FAIL: Expected 'x' to be initialized with an integer literal (comptime constant 5)\n");
        return false;
    }
    if (x_decl->initializer->as.integer_literal.value != 5) {
        printf("FAIL: Expected 'x' to be 5, got %llu\n", (unsigned long long)x_decl->initializer->as.integer_literal.value);
        return false;
    }

    const ASTVarDeclNode* y_decl = unit.extractVariableDeclaration("y");
    if (!y_decl || !y_decl->initializer || y_decl->initializer->type != NODE_INTEGER_LITERAL) {
        printf("FAIL: Expected 'y' to be initialized with an integer literal (comptime constant 10)\n");
        return false;
    }
    if (y_decl->initializer->as.integer_literal.value != 10) {
        printf("FAIL: Expected 'y' to be 10, got %llu\n", (unsigned long long)y_decl->initializer->as.integer_literal.value);
        return false;
    }

    return true;
}

TEST_FUNC(ArrayProperty_ComptimeLen) {
    const char* source =
        "fn foo() void {\n"
        "    const arr = [3]i32{1, 2, 3};\n"
        "    var buffer: [arr.len]i32 = undefined;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for array .len in type context:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTVarDeclNode* buffer_decl = unit.extractVariableDeclaration("buffer");
    if (!buffer_decl || !buffer_decl->symbol || !buffer_decl->symbol->symbol_type) return false;

    Type* t = buffer_decl->symbol->symbol_type;
    if (t->kind != TYPE_ARRAY || t->as.array.size != 3) {
        printf("FAIL: Expected 'buffer' to be [3]i32, got size %llu\n", (unsigned long long)t->as.array.size);
        return false;
    }

    return true;
}
