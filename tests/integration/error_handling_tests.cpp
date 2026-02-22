#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include "../test_utils.hpp"
#include "../c89_validation/c89_validator.hpp"
#include <cstdio>

/**
 * @file error_handling_tests.cpp
 * @brief Integration tests for Task 226: Error Unions and Error Sets.
 */

TEST_FUNC(ErrorHandling_ErrorSetDefinition) {
    const char* source =
        "const MyErrors = error { FileNotFound, AccessDenied, OutOfMemory };\n"
        "fn foo() void {}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    ASSERT_TRUE(unit.performTestPipeline(file_id));

    // Verify tags are in the registry
    GlobalErrorRegistry& registry = unit.getGlobalErrorRegistry();
    ASSERT_TRUE(registry.getTagId(interner.intern("FileNotFound")) > 0);
    ASSERT_TRUE(registry.getTagId(interner.intern("AccessDenied")) > 0);
    ASSERT_TRUE(registry.getTagId(interner.intern("OutOfMemory")) > 0);

    return true;
}

TEST_FUNC(ErrorHandling_ErrorLiteral) {
    const char* source =
        "fn fail() !i32 {\n"
        "    return error.FileNotFound;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    ASSERT_TRUE(unit.performTestPipeline(file_id));

    // Verify codegen
    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    emitter.emitFnDecl(unit.extractFunctionDeclaration("fail"));

    // Check for ERROR_FileNotFound and is_error = 1
    ASSERT_TRUE(emitter.contains("ERROR_FileNotFound"));
    ASSERT_TRUE(emitter.contains("is_error = 1"));

    return true;
}

TEST_FUNC(ErrorHandling_SuccessWrapping) {
    const char* source =
        "fn succeed() !i32 {\n"
        "    return 42;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    ASSERT_TRUE(unit.performTestPipeline(file_id));

    // Verify codegen
    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    emitter.emitFnDecl(unit.extractFunctionDeclaration("succeed"));

    // Check for payload assignment and is_error = 0
    ASSERT_TRUE(emitter.contains("payload = 42"));
    ASSERT_TRUE(emitter.contains("is_error = 0"));

    return true;
}

TEST_FUNC(ErrorHandling_VoidPayload) {
    const char* source =
        "fn doSomething() !void {\n"
        "    if (false) { return error.Failed; }\n"
        "    return;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    ASSERT_TRUE(unit.performTestPipeline(file_id));

    // Verify codegen
    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    emitter.emitFnDecl(unit.extractFunctionDeclaration("doSomething"));

    // Check struct has no .data.payload for void
    ASSERT_TRUE(emitter.contains("is_error = 1"));
    ASSERT_TRUE(emitter.contains("is_error = 0"));
    // Since it's void, we should NOT see ".data.payload" or ".data.err"
    // Instead we should see ".err"
    ASSERT_TRUE(emitter.contains(".err = ERROR_Failed"));

    return true;
}

TEST_FUNC(ErrorHandling_TryExpression) {
    const char* source =
        "fn fallible() !i32 { return 10; }\n"
        "fn caller() !i32 {\n"
        "    const x = try fallible();\n"
        "    return x + 5;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    ASSERT_TRUE(unit.performTestPipeline(file_id));

    // Verify codegen
    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    emitter.emitFnDecl(unit.extractFunctionDeclaration("caller"));

    ASSERT_TRUE(emitter.contains("__try_res_"));
    ASSERT_TRUE(emitter.contains(" = fallible()"));
    ASSERT_TRUE(emitter.contains(".is_error"));
    ASSERT_TRUE(emitter.contains("return __ret_err"));

    return true;
}

TEST_FUNC(ErrorHandling_CatchExpression) {
    const char* source =
        "fn fallible() !i32 { return error.Fail; }\n"
        "fn caller() i32 {\n"
        "    const x = fallible() catch 42;\n"
        "    return x;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    ASSERT_TRUE(unit.performTestPipeline(file_id));

    // Verify codegen
    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    emitter.emitFnDecl(unit.extractFunctionDeclaration("caller"));

    ASSERT_TRUE(emitter.contains("__catch_res_"));
    ASSERT_TRUE(emitter.contains(" = fallible()"));
    ASSERT_TRUE(emitter.contains(".is_error"));
    ASSERT_TRUE(emitter.contains(" = 42"));

    return true;
}

TEST_FUNC(ErrorHandling_NestedErrorUnion) {
    const char* source =
        "fn foo() !!i32 {\n"
        "    return 42;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    ASSERT_TRUE(unit.performTestPipeline(file_id));

    return true;
}

TEST_FUNC(ErrorHandling_StructField) {
    const char* source =
        "const S = struct {\n"
        "    res: !i32,\n"
        "};\n"
        "fn foo() void {\n"
        "    var s: S;\n"
        "    s.res = 10;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    ASSERT_TRUE(unit.performTestPipeline(file_id));

    return true;
}

TEST_FUNC(ErrorHandling_C89Execution) {
    const char* source =
        "fn fallible(val: i32) !i32 {\n"
        "    if (val == 0) { return error.ZeroValue; }\n"
        "    return val * 2;\n"
        "}\n"
        "pub fn main() i32 {\n"
        "    const a = fallible(10) catch 0;\n"
        "    const b = fallible(0) catch 42;\n"
        "    if (a == 20 and b == 42) { return 0; }\n"
        "    return 1;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    ASSERT_TRUE(unit.performFullPipeline(file_id));

    C89Validator* validator = createGCCValidator();
    if (!validator) return true;

    // Use C89Emitter to generate code to a string/buffer
    const char* temp_path = "temp_error_test.c";
    {
        C89Emitter emitter(unit, temp_path);
        emitter.emitPrologue();

        // 1. Discover Types
        for (size_t i = 0; i < unit.getModules().length(); ++i) {
             Module* mod = unit.getModules()[i];
             if (mod->ast_root) {
                 DynamicArray<ASTNode*>* stmts = mod->ast_root->as.block_stmt.statements;
                 for (size_t j = 0; j < stmts->length(); ++j) {
                     ASTNode* stmt = (*stmts)[j];
                     if (stmt->type == NODE_FN_DECL) {
                         Type* ret = stmt->as.fn_decl->return_type ? stmt->as.fn_decl->return_type->resolved_type : get_g_type_void();
                         if (ret->kind == TYPE_ERROR_UNION) emitter.ensureErrorUnionType(ret);
                         if (stmt->as.fn_decl->params) {
                             for (size_t k = 0; k < stmt->as.fn_decl->params->length(); ++k) {
                                 Type* pt = (*stmt->as.fn_decl->params)[k]->type->resolved_type;
                                 if (pt->kind == TYPE_ERROR_UNION) emitter.ensureErrorUnionType(pt);
                             }
                         }
                     }
                 }
             }
        }

        // 2. Types
        emitter.emitBufferedSliceDefinitions();

        // 3. Prototypes
        for (size_t i = 0; i < unit.getModules().length(); ++i) {
             Module* mod = unit.getModules()[i];
             if (mod->ast_root) {
                 DynamicArray<ASTNode*>* stmts = mod->ast_root->as.block_stmt.statements;
                 for (size_t j = 0; j < stmts->length(); ++j) {
                     ASTNode* stmt = (*stmts)[j];
                     if (stmt->type == NODE_FN_DECL) {
                         emitter.emitFnProto(stmt->as.fn_decl, stmt->as.fn_decl->is_pub);
                     }
                 }
             }
        }

        // 4. Definitions
        for (size_t i = 0; i < unit.getModules().length(); ++i) {
             Module* mod = unit.getModules()[i];
             if (mod->ast_root) {
                 DynamicArray<ASTNode*>* stmts = mod->ast_root->as.block_stmt.statements;
                 for (size_t j = 0; j < stmts->length(); ++j) {
                     ASTNode* stmt = (*stmts)[j];
                     if (stmt->type == NODE_FN_DECL) {
                         emitter.emitFnDecl(stmt->as.fn_decl);
                     } else if (stmt->type == NODE_VAR_DECL) {
                         emitter.emitGlobalVarDecl(stmt, true);
                     }
                 }
             }
        }
        emitter.close();
    }

    PlatFile f = plat_open_file(temp_path, false);
    char buffer[16384];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer)-1);
    buffer[bytes] = '\0';
    plat_close_file(f);
    plat_delete_file(temp_path);

    ValidationResult res = validator->validate(buffer);
    bool ok = res.isValid;
    if (!ok) {
        printf("FAIL: Error handling execution test failed C89 validation\n");
        for (size_t i = 0; i < res.errors.size(); ++i) {
            printf("  Error: %s\n", res.errors[i].c_str());
        }
    }
    delete validator;
    return ok;
}
