#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "ast_lifter.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include <string>
#include <vector>

TEST_FUNC(UnionSliceLifting_Basic) {
    const char* source =
        "const U = union(enum) { A: []i32, B: i32 };\n"
        "fn test_fn(cond: bool, s1: []i32, s2: []i32) void {\n"
        "    var u: U = undefined;\n"
        "    u = U{ .A = if (cond) s1 else s2 };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    // Now check the generated C code
    char* output_path = plat_create_temp_file("test_union", ".c");
    if (!output_path) return false;

    C89Emitter emitter(unit, output_path, false);
    emitter.emitPrologue();

    Module* mod = unit.getModule("test");
    // We need to emit the module's AST
    if (mod->ast_root->type == NODE_BLOCK_STMT) {
        DynamicArray<ASTNode*>* stmts = mod->ast_root->as.block_stmt.statements;
        for (size_t i = 0; i < stmts->length(); ++i) {
            ASTNode* stmt = (*stmts)[i];
            if (stmt->type == NODE_FN_DECL) {
                emitter.emitFnDecl(stmt->as.fn_decl);
            } else if (stmt->type == NODE_VAR_DECL) {
                emitter.emitGlobalVarDecl(stmt, true);
            }
        }
    }
    emitter.close();

    // Read the file back and verify
    char* buffer = NULL;
    size_t bytes = 0;
    if (!plat_file_read(output_path, &buffer, &bytes)) {
        plat_free(output_path);
        return false;
    }

    std::string code(buffer);
    plat_free(buffer);
    plat_delete_file(output_path);
    plat_free(output_path);

    // Verify that the temporary for the if expression is Slice_i32, not Slice_i32*
    size_t tmp_pos = code.find("__tmp_if_");
    ASSERT_TRUE(tmp_pos != std::string::npos);

    // It should be preceded by Slice_i32 (mangled name for []i32)
    ASSERT_TRUE(code.find("Slice_i32 __tmp_if_") != std::string::npos);

    return true;
}

TEST_FUNC(UnionSliceLifting_Coercion) {
    const char* source =
        "const U = union(enum) { A: []i32, B: i32 };\n"
        "fn test_fn(cond: bool) void {\n"
        "    var u: U = undefined;\n"
        "    var arr1 = [3]i32{1, 2, 3};\n"
        "    var arr2 = [3]i32{4, 5, 6};\n"
        "    u = U{ .A = if (cond) arr1 else arr2 };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    char* output_path = plat_create_temp_file("test_union_coercion", ".c");
    if (!output_path) return false;

    C89Emitter emitter(unit, output_path, false);
    emitter.emitPrologue();
    Module* mod = unit.getModule("test");
    if (mod->ast_root->type == NODE_BLOCK_STMT) {
        DynamicArray<ASTNode*>* stmts = mod->ast_root->as.block_stmt.statements;
        for (size_t i = 0; i < stmts->length(); ++i) {
            ASTNode* stmt = (*stmts)[i];
            if (stmt->type == NODE_FN_DECL) {
                emitter.emitFnDecl(stmt->as.fn_decl);
            }
        }
    }
    emitter.close();

    char* buffer = NULL;
    size_t bytes = 0;
    if (!plat_file_read(output_path, &buffer, &bytes)) {
        plat_free(output_path);
        return false;
    }

    std::string code(buffer);
    plat_free(buffer);
    plat_delete_file(output_path);
    plat_free(output_path);

    ASSERT_TRUE(code.find("__make_slice_i32") != std::string::npos);

    return true;
}

TEST_FUNC(UnionSliceLifting_ManualConstruction) {
    const char* source =
        "extern fn my_alloc(size: usize) [*]i32;\n"
        "const U = union(enum) { A: []i32, B: i32 };\n"
        "fn test_fn(count: usize) void {\n"
        "    var u: U = undefined;\n"
        "    const ptr = my_alloc(count * 4);\n"
        "    u = U{ .A = ptr[0..count] };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    // Verify C code for proper slice assignment
    char* output_path = plat_create_temp_file("test_union_manual", ".c");
    if (!output_path) return false;

    C89Emitter emitter(unit, output_path, false);
    emitter.emitPrologue();
    Module* mod = unit.getModule("test");
    if (mod->ast_root->type == NODE_BLOCK_STMT) {
        DynamicArray<ASTNode*>* stmts = mod->ast_root->as.block_stmt.statements;
        for (size_t i = 0; i < stmts->length(); ++i) {
            ASTNode* stmt = (*stmts)[i];
            if (stmt->type == NODE_FN_DECL) {
                emitter.emitFnDecl(stmt->as.fn_decl);
            }
        }
    }
    emitter.close();

    char* buffer = NULL;
    size_t bytes = 0;
    if (!plat_file_read(output_path, &buffer, &bytes)) {
        plat_free(output_path);
        return false;
    }

    std::string code(buffer);
    plat_free(buffer);
    plat_delete_file(output_path);
    plat_free(output_path);

    // It should use __make_slice_i32
    ASSERT_TRUE(code.find("__make_slice_i32") != std::string::npos);
    // And assignment should be direct to the union data field
    ASSERT_TRUE(code.find(".data.A = ") != std::string::npos);

    return true;
}
