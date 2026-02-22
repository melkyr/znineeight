#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include <string>

TEST_FUNC(Task225_2_BracelessIfExpr) {
    const char* source =
        "fn foo(b: bool) i32 {\n"
        "    return if (b) 1 else 2;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        return false;
    }

    const char* temp_filename = "temp_if_expr.c";
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

    if (generated_c.find("if (b) {") == std::string::npos) return false;
    if (generated_c.find("__return_val = 1;") == std::string::npos) return false;
    if (generated_c.find("__return_val = 2;") == std::string::npos) return false;

    return true;
}

TEST_FUNC(Task225_2_PrintLowering) {
    const char* source =
        "const debug = @import(\"std_debug.zig\");\n"
        "pub fn main() void {\n"
        "    const x = 42;\n"
        "    debug.print(\"Result: {}\\n\", .{x});\n"
        "}\n";

    const char* std_source =
        "pub extern fn print(fmt: *const u8, args: anytype) void;\n";

    // Create files on disk for import system
    {
        FILE* f = fopen("std_debug.zig", "w");
        if (!f) return false;
        fprintf(f, "%s", std_source);
        fclose(f);
    }

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 main_id = unit.addSource("main.zig", source);

    if (!unit.performFullPipeline(main_id)) {
        unit.getErrorHandler().printErrors();
        remove("std_debug.zig");
        return false;
    }

    const char* temp_filename = "temp_print.c";
    {
        C89Emitter emitter(unit, temp_filename);
        if (!emitter.isValid()) return false;
        emitter.emitPrologue();

        DynamicArray<Module*>& modules = unit.getModules();
        for (size_t i = 0; i < modules.length(); ++i) {
            if (plat_strcmp(modules[i]->name, "main") == 0) {
                ASTNode* root = modules[i]->ast_root;
                DynamicArray<ASTNode*>* stmts = root->as.block_stmt.statements;
                for (size_t j = 0; j < stmts->length(); ++j) {
                    if ((*stmts)[j]->type == NODE_FN_DECL) {
                        emitter.emitFnDecl((*stmts)[j]->as.fn_decl);
                    }
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

    if (generated_c.find("__bootstrap_print(\"Result: \");") == std::string::npos) return false;
    if (generated_c.find("__bootstrap_print_int(x);") == std::string::npos) {
        remove("std_debug.zig");
        return false;
    }

    remove("std_debug.zig");
    return true;
}

TEST_FUNC(Task225_2_SwitchIfExpr) {
    const char* source =
        "fn bar(x: i32, b: bool) i32 {\n"
        "    return switch (x) {\n"
        "        0 => if (b) 1 else 2,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        return false;
    }

    const char* temp_filename = "temp_switch_if.c";
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

    if (generated_c.find("case 0:") == std::string::npos) return false;
    if (generated_c.find("if (b) {") == std::string::npos) return false;
    // The target variable for the switch expression result should be assigned
    if (generated_c.find(" = 1;") == std::string::npos) return false;
    if (generated_c.find(" = 2;") == std::string::npos) return false;

    return true;
}
