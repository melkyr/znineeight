#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include "codegen.hpp"
#include "c89_validator.hpp"
#include "platform.hpp"
#include <cstdio>
#include <string>

/**
 * @file unreachable_tests.cpp
 * @brief Integration tests for Phase 2: unreachable Statement Emission.
 */

TEST_FUNC(Unreachable_Statement) {
    const char* source =
        "fn foo() void {\n"
        "    unreachable;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed\n");
        return false;
    }

    const char* temp_filename = "temp_unreachable_stmt.c";
    C89Emitter emitter(unit, temp_filename);
    emitter.emitPrologue();

    ASTNode* root = unit.last_ast;
    DynamicArray<ASTNode*>* stmts = root->as.block_stmt.statements;
    for (size_t i = 0; i < stmts->length(); ++i) {
        if ((*stmts)[i]->type == NODE_FN_DECL) {
            emitter.emitFnDecl((*stmts)[i]->as.fn_decl);
        }
    }
    emitter.close();

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read(temp_filename, &buffer, &size)) return false;
    std::string generated_c(buffer, size);
    plat_free(buffer);
    plat_delete_file(temp_filename);

    if (generated_c.find("__bootstrap_panic(\"reached unreachable\"") == std::string::npos) {
        printf("FAIL: Expected __bootstrap_panic call, got:\n%s\n", generated_c.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(Unreachable_DeadCode) {
    const char* source =
        "fn foo() void {\n"
        "    unreachable;\n"
        "    var x: i32 = 1;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    const char* temp_filename = "temp_unreachable_dead.c";
    C89Emitter emitter(unit, temp_filename);
    emitter.emitPrologue();

    ASTNode* root = unit.last_ast;
    DynamicArray<ASTNode*>* stmts = root->as.block_stmt.statements;
    for (size_t i = 0; i < stmts->length(); ++i) {
        if ((*stmts)[i]->type == NODE_FN_DECL) {
            emitter.emitFnDecl((*stmts)[i]->as.fn_decl);
        }
    }
    emitter.close();

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read(temp_filename, &buffer, &size)) return false;
    std::string generated_c(buffer, size);
    plat_free(buffer);
    plat_delete_file(temp_filename);

    if (generated_c.find("z_test_x = 1") != std::string::npos) {
        printf("FAIL: Dead code should not be emitted after unreachable:\n%s\n", generated_c.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(Unreachable_Initializer) {
    const char* source =
        "fn foo() void {\n"
        "    const x: i32 = unreachable;\n"
        "    var y: i32 = 1;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    const char* temp_filename = "temp_unreachable_init.c";
    C89Emitter emitter(unit, temp_filename);
    emitter.emitPrologue();

    ASTNode* root = unit.last_ast;
    DynamicArray<ASTNode*>* stmts = root->as.block_stmt.statements;
    for (size_t i = 0; i < stmts->length(); ++i) {
        if ((*stmts)[i]->type == NODE_FN_DECL) {
            emitter.emitFnDecl((*stmts)[i]->as.fn_decl);
        }
    }
    emitter.close();

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read(temp_filename, &buffer, &size)) return false;
    std::string generated_c(buffer, size);
    plat_free(buffer);
    plat_delete_file(temp_filename);

    if (generated_c.find("__bootstrap_panic") == std::string::npos) {
        printf("FAIL: Expected __bootstrap_panic for unreachable initializer\n");
        return false;
    }
    if (generated_c.find("z_test_y = 1") != std::string::npos) {
        printf("FAIL: Dead code should not be emitted after unreachable initializer:\n%s\n", generated_c.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(Unreachable_ErrDefer) {
    const char* source =
        "fn foo() !void {\n"
        "    errdefer unreachable;\n"
        "    return error.Fail;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    const char* temp_filename = "temp_unreachable_errdefer.c";
    C89Emitter emitter(unit, temp_filename);
    emitter.emitPrologue();

    ASTNode* root = unit.last_ast;
    DynamicArray<ASTNode*>* stmts = root->as.block_stmt.statements;
    for (size_t i = 0; i < stmts->length(); ++i) {
        if ((*stmts)[i]->type == NODE_FN_DECL) {
            emitter.emitFnDecl((*stmts)[i]->as.fn_decl);
        }
    }
    emitter.close();

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read(temp_filename, &buffer, &size)) return false;
    std::string generated_c(buffer, size);
    plat_free(buffer);
    plat_delete_file(temp_filename);

    // Current minimal errdefer implementation treats it as defer, so it should be emitted at function exit
    if (generated_c.find("__bootstrap_panic") == std::string::npos) {
        printf("FAIL: Expected __bootstrap_panic for unreachable inside errdefer:\n%s\n", generated_c.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(Unreachable_IfExpr) {
    const char* source =
        "fn foo(c: bool) i32 {\n"
        "    const val = if (c) 1 else unreachable;\n"
        "    return val;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    const char* temp_filename = "temp_unreachable_ifexpr.c";
    C89Emitter emitter(unit, temp_filename);
    emitter.emitPrologue();

    ASTNode* root = unit.last_ast;
    DynamicArray<ASTNode*>* stmts = root->as.block_stmt.statements;
    for (size_t i = 0; i < stmts->length(); ++i) {
        if ((*stmts)[i]->type == NODE_FN_DECL) {
            emitter.emitFnDecl((*stmts)[i]->as.fn_decl);
        }
    }
    emitter.close();

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read(temp_filename, &buffer, &size)) return false;
    std::string generated_c(buffer, size);
    plat_free(buffer);
    plat_delete_file(temp_filename);

    if (generated_c.find("__bootstrap_panic") == std::string::npos) {
        printf("FAIL: Expected __bootstrap_panic in else branch of if expression:\n%s\n", generated_c.c_str());
        return false;
    }

    return true;
}
