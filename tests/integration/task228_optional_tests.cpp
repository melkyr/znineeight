#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include <string>

TEST_FUNC(Task228_OptionalBasics) {
    const char* source =
        "pub fn main() void {\n"
        "    var x: ?i32 = null;\n"
        "    var y: ?i32 = 10;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    const char* temp_filename = "temp_opt_basics.c";
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

    // UT-01: var x: ?i32 = null; -> has_value = 0
    if (generated_c.find("x.has_value = 0;") == std::string::npos) return false;
    // UT-02: var y: ?i32 = 10; -> has_value = 1, value = 10
    if (generated_c.find("y.value = 10;") == std::string::npos) return false;
    if (generated_c.find("y.has_value = 1;") == std::string::npos) return false;

    return true;
}

TEST_FUNC(Task228_OptionalOrelse) {
    const char* source =
        "fn foo(opt: ?i32) i32 {\n"
        "    const y = opt orelse 0;\n"
        "    return y;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    const char* temp_filename = "temp_opt_orelse.c";
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

    // UT-04: const y = opt orelse 0;
    if (generated_c.find("if (__orelse_res.has_value) {") == std::string::npos) return false;
    if (generated_c.find("y = __orelse_res.value;") == std::string::npos) return false;
    if (generated_c.find("y = 0;") == std::string::npos) return false;

    return true;
}

TEST_FUNC(Task228_OptionalIfCapture) {
    const char* source =
        "fn bar(opt: ?i32) i32 {\n"
        "    if (opt) |v| {\n"
        "        return v;\n"
        "    } else {\n"
        "        return -1;\n"
        "    }\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    const char* temp_filename = "temp_opt_if.c";
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

    // UT-05: if (opt) |v| { ... }
    if (generated_c.find("if (opt_tmp") == std::string::npos) return false;
    if (generated_c.find(".has_value) {") == std::string::npos) return false;
    if (generated_c.find("v = opt_tmp") == std::string::npos) return false;
    if (generated_c.find(".value;") == std::string::npos) return false;

    return true;
}

TEST_FUNC(Task228_OptionalFunction) {
    const char* source =
        "fn foo(x: ?i32) ?i32 {\n"
        "    return x;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    const char* temp_filename = "temp_opt_fn.c";
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

    // UT-06: fn foo(x: ?i32) ?i32
    if (generated_c.find("Optional_i32 foo(Optional_i32 x)") == std::string::npos) return false;
    if (generated_c.find("return x;") == std::string::npos) return false;

    return true;
}

TEST_FUNC(Task228_NestedOptional) {
    const char* source =
        "fn foo() void {\n"
        "    var x: ??i32 = null;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    const char* temp_filename = "temp_opt_nested.c";
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

    // UT-07: var x: ??i32 = null;
    if (generated_c.find("Optional_Optional_i32 x;") == std::string::npos) return false;
    if (generated_c.find("x.has_value = 0;") == std::string::npos) return false;

    return true;
}

TEST_FUNC(Task228_OptionalStruct) {
    const char* source =
        "const Point = struct { x: i32, y: i32 };\n"
        "fn foo() void {\n"
        "    var p: ?Point = null;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    const char* temp_filename = "temp_opt_struct.c";
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

    // UT-08: var x: ?Point = null;
    if (generated_c.find("Optional_Point p;") == std::string::npos) return false;
    if (generated_c.find("p.has_value = 0;") == std::string::npos) return false;

    return true;
}

TEST_FUNC(Task228_OptionalOrelseBlock) {
    const char* source =
        "fn foo(opt: ?i32) i32 {\n"
        "    return opt orelse {\n"
        "        const x = 1;\n"
        "        x + 1\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    const char* temp_filename = "temp_opt_orelse_block.c";
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

    // UT-09: opt orelse { block; }
    if (generated_c.find("} else {") == std::string::npos) return false;
    if (generated_c.find("x = 1;") == std::string::npos) return false;
    if (generated_c.find("__return_val = x + 1;") == std::string::npos) return false;

    return true;
}

TEST_FUNC(Task228_OptionalTypeMismatch) {
    const char* source =
        "fn foo() void {\n"
        "    var x: ?i32 = 10;\n"
        "    var y: i32 = x;\n" // Error: ?i32 assigned to i32
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    // Should fail in type checking
    if (unit.performTestPipeline(file_id)) {
        return false;
    }

    // UT-03: var x: i32 = opt; -> Error
    bool found_error = false;
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].hint && strstr(errors[i].hint, "Incompatible assignment: '?i32' to 'i32'")) {
            found_error = true;
            break;
        }
    }

    return found_error;
}

TEST_FUNC(Task228_OptionalOrelseUnreachable) {
    const char* source =
        "fn foo(opt: ?i32) i32 {\n"
        "    return opt orelse unreachable;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    const char* temp_filename = "temp_opt_unreachable.c";
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

    if (generated_c.find("__bootstrap_panic(\"reached unreachable\"") == std::string::npos) return false;

    return true;
}
