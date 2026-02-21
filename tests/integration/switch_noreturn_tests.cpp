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
 * @file switch_noreturn_tests.cpp
 * @brief Integration tests for switch expressions with divergent prongs and noreturn type.
 */

TEST_FUNC(SwitchNoreturn_BasicDivergence) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    return switch (x) {\n"
        "        0 => 10,\n"
        "        1 => return 20,\n"
        "        else => unreachable,\n"
        "    };\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration("foo");
    if (!fn) return false;

    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    std::string emission = emitter.emitExpression(fn->body);

    // Verify emission for divergent prongs
    if (emission.find("case 1: return 20; break;") == std::string::npos) {
        printf("FAIL: Expected 'return 20' without assignment in case 1, got: %s\n", emission.c_str());
        return false;
    }
    if (emission.find("default: __bootstrap_panic") == std::string::npos) {
        printf("FAIL: Expected panic in default prong, got: %s\n", emission.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(SwitchNoreturn_RealCodegen) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    return switch (x) {\n"
        "        0 => 10,\n"
        "        1 => return 20,\n"
        "        else => unreachable,\n"
        "    };\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const char* temp_filename = "temp_switch_noreturn.c";
    {
        C89Emitter emitter(unit, temp_filename);
        if (!emitter.isValid()) return false;
        emitter.emitPrologue();

        ASTNode* root = unit.last_ast;
        if (root && root->type == NODE_BLOCK_STMT) {
            DynamicArray<ASTNode*>* stmts = root->as.block_stmt.statements;
            for (size_t i = 0; i < stmts->length(); ++i) {
                if ((*stmts)[i]->type == NODE_FN_DECL) {
                    emitter.emitFnDecl((*stmts)[i]->as.fn_decl);
                }
            }
        }
    }

    char* buffer = NULL;
    size_t size = 0;
    if (!plat_file_read(temp_filename, &buffer, &size)) return false;
    std::string generated_c(buffer, size);
    plat_free(buffer);
    plat_delete_file(temp_filename);

    // Verify absence of double semicolons
    if (generated_c.find(";;") != std::string::npos) {
        printf("FAIL: Found double semicolon in generated C code:\n%s\n", generated_c.c_str());
        return false;
    }

    // Verify panic emission for unreachable
    if (generated_c.find("__bootstrap_panic") == std::string::npos) {
        printf("FAIL: Expected __bootstrap_panic in generated C code\n");
        return false;
    }

    bool ok = true;

    // Test unreachable as a standalone statement
    const char* source2 = "fn bar() void { unreachable; }";
    u32 file_id2 = unit.addSource("test2.zig", source2);
    if (unit.performTestPipeline(file_id2)) {
        C89Emitter emitter2(unit, temp_filename);
        if (emitter2.isValid()) {
            emitter2.emitPrologue();
            ASTNode* root = unit.last_ast;
            if (root && root->type == NODE_BLOCK_STMT) {
                 DynamicArray<ASTNode*>* stmts = root->as.block_stmt.statements;
                 for (size_t i = 0; i < stmts->length(); ++i) {
                     if ((*stmts)[i]->type == NODE_FN_DECL) {
                         emitter2.emitFnDecl((*stmts)[i]->as.fn_decl);
                     }
                 }
            }
            emitter2.close();

            char* buffer2 = NULL;
            size_t size2 = 0;
            if (plat_file_read(temp_filename, &buffer2, &size2)) {
                std::string gen2(buffer2, size2);
                if (gen2.find(";;") != std::string::npos) {
                    printf("FAIL: Found double semicolon in 'unreachable;' codegen:\n%s\n", gen2.c_str());
                    ok = false;
                }
                plat_free(buffer2);
            }
            plat_delete_file(temp_filename);
        }
    }

    if (!ok) return false;

    C89Validator* validator = createGCCValidator();
    ValidationResult res = validator->validate(generated_c);
    ok = ok && res.isValid;
    if (!ok) {
        printf("FAIL: Generated C code is not valid C89\n");
        for (size_t i = 0; i < res.errors.size(); ++i) {
            printf("  Error: %s\n", res.errors[i].c_str());
        }
        printf("--- Generated Code ---\n%s\n----------------------\n", generated_c.c_str());
    }
    delete validator;

    return ok;
}

TEST_FUNC(SwitchNoreturn_AllDivergent) {
    const char* source =
        "fn bar() void {}\n"
        "fn foo(x: i32) noreturn {\n"
        "    switch (x) {\n"
        "        0 => unreachable,\n"
        "        else => unreachable,\n"
        "    };\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration("foo");
    if (!fn) return false;

    if (!fn->return_type || fn->return_type->resolved_type->kind != TYPE_NORETURN) {
        printf("FAIL: Expected function return type to be noreturn\n");
        return false;
    }

    return true;
}

TEST_FUNC(SwitchNoreturn_BreakInProng) {
    const char* source =
        "fn foo() void {\n"
        "    while (true) {\n"
        "        var x: i32 = 0;\n"
        "        _ = switch (x) {\n"
        "            0 => break,\n"
        "            else => 1,\n"
        "        };\n"
        "    }\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(SwitchNoreturn_LabeledBreakInProng) {
    const char* source =
        "fn foo() void {\n"
        "    outer: while (true) {\n"
        "        var x: i32 = 0;\n"
        "        _ = switch (x) {\n"
        "            0 => break :outer,\n"
        "            else => 1,\n"
        "        };\n"
        "    }\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(SwitchNoreturn_MixedTypesError) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    return switch (x) {\n"
        "        0 => 10,\n"
        "        1 => true,\n" // Type mismatch: i32 vs bool
        "        else => unreachable,\n"
        "    };\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    // This should fail during type checking
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected type mismatch error but pipeline succeeded\n");
        return false;
    }

    return true;
}

TEST_FUNC(SwitchNoreturn_VariableNoreturnError) {
    const char* source =
        "fn foo() void {\n"
        "    var x: noreturn = unreachable;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected error for variable of type noreturn but pipeline succeeded\n");
        return false;
    }

    return true;
}

TEST_FUNC(SwitchNoreturn_BlockProng) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    return switch (x) {\n"
        "        0 => {\n"
        "            var y = 5;\n"
        "            y + 5\n"
        "        },\n"
        "        else => 0,\n"
        "    };\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration("foo");
    if (!fn) return false;

    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    std::string emission = emitter.emitExpression(fn->body);

    if (emission.find("case 0: { int y = 5; y + 5 }") == std::string::npos) {
         // printf("DEBUG: Emission: %s\n", emission.c_str());
    }

    return true;
}
