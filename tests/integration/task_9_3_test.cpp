#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include "../test_utils.hpp"
#include <cstdio>
#include <string>

static bool run_string_type_test(const char* zig_code) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);

    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();
    if (!root) return false;

    TypeChecker checker(unit);
    checker.check(root);

    // Check global variable msg
    const ASTVarDeclNode* vd = unit.findVariableDeclaration(root, "msg");
    if (vd && vd->symbol && vd->symbol->symbol_type) {
        Type* t = vd->symbol->symbol_type;
        if (t->kind != TYPE_POINTER || t->as.pointer.base->kind != TYPE_ARRAY) {
             return false;
        }
    }

    const ASTNode* call = unit.findFunctionCall(root, "puts");
    if (!call) {
        return false;
    }

    ASTNode* arg = (*call->as.function_call->args)[0];
    Type* t = arg->resolved_type;

    if (t->kind == TYPE_POINTER && t->as.pointer.is_many) {
        return true;
    } else {
        return false;
    }
}

static bool verify_real_emission_task93(const char* zig_code, const char* expected_substring) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        return false;
    }

    const char* temp_path = "temp_task_9_3.c";
    C89Emitter emitter(unit, temp_path);
    emitter.emitPrologue();

    if (unit.last_ast->type == NODE_BLOCK_STMT) {
        DynamicArray<ASTNode*>* stmts = unit.last_ast->as.block_stmt.statements;
        for (size_t i = 0; i < stmts->length(); ++i) {
            ASTNode* stmt = (*stmts)[i];
            if (stmt->type == NODE_VAR_DECL) {
                emitter.emitGlobalVarDecl(stmt, true);
            } else if (stmt->type == NODE_FN_DECL) {
                emitter.emitFnDecl(stmt->as.fn_decl);
            }
        }
    }

    emitter.flush();
    emitter.close();

    PlatFile f = plat_open_file(temp_path, false);
    char buffer[8192];
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer) - 1);
    buffer[bytes] = '\0';
    plat_close_file(f);

    if (strstr(buffer, expected_substring) == NULL) {
        return false;
    }

    return true;
}

TEST_FUNC(StringLiteral_To_ManyItemPointer) {
    const char* source =
        "extern fn puts(s: [*]const u8) i32;\n"
        "const msg = \"hello\";\n"
        "pub fn main() void {\n"
        "    _ = puts(\"world\");\n"
        "    _ = puts(msg);\n"
        "}";
    if (!run_string_type_test(source)) return false;
    if (!verify_real_emission_task93(source, "puts(\"world\")")) return false;
    if (!verify_real_emission_task93(source, "puts(&(*msg)[0])")) return false;

    return true;
}

TEST_FUNC(StringLiteral_To_Slice) {
    const char* source =
        "fn takeSlice(s: []const u8) void { _ = s; }\n"
        "pub fn main() void {\n"
        "    takeSlice(\"hello\");\n"
        "    const s: []const u8 = \"world\";\n"
        "    _ = s;\n"
        "}";

    if (!verify_real_emission_task93(source, "__make_slice_u8(\"hello\", 5)")) return false;
    if (!verify_real_emission_task93(source, "__make_slice_u8(\"world\", 5)")) return false;

    return true;
}
