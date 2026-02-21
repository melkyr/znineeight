#include "cbackend.hpp"
#include "compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include "utils.hpp"

CBackend::CBackend(CompilationUnit& unit) : unit_(unit), entry_filename_(NULL) {}

bool CBackend::generate(const char* output_dir) {
    DynamicArray<Module*>& modules = unit_.getModules();

    bool has_main_function = false;

    for (size_t i = 0; i < modules.length(); ++i) {

        if (modules[i]->ast_root && modules[i]->ast_root->type == NODE_BLOCK_STMT) {
            DynamicArray<ASTNode*>* stmts = modules[i]->ast_root->as.block_stmt.statements;
            for (size_t j = 0; j < stmts->length(); ++j) {
                if ((*stmts)[j]->type == NODE_FN_DECL) {
                    ASTFnDeclNode* fn = (*stmts)[j]->as.fn_decl;
                    if (fn->is_pub && plat_strcmp(fn->name, "main") == 0) {
                        has_main_function = true;
                    }
                }
            }
        }
    }

    if (has_main_function) {
        entry_filename_ = "main.c";
    }

    for (size_t i = 0; i < modules.length(); ++i) {
        DynamicArray<const char*> public_slices(unit_.getArena());
        if (!generateHeaderFile(modules[i], output_dir, &public_slices)) return false;
        if (!generateSourceFile(modules[i], output_dir, &public_slices)) return false;
    }

    if (!generateMasterMain(output_dir)) return false;
    if (!generateBuildBat(output_dir)) return false;
    if (!generateMakefile(output_dir)) return false;

    return true;
}

bool CBackend::generateSourceFile(Module* module, const char* output_dir, DynamicArray<const char*>* public_slices) {
    char path[1024];
    char* cur = path;
    size_t rem = sizeof(path);

    safe_append(cur, rem, output_dir);
    safe_append(cur, rem, "/");
    if (entry_filename_ && plat_strcmp(module->name, "main") == 0) {
        safe_append(cur, rem, "main_module.c");
    } else {
        safe_append(cur, rem, module->name);
        safe_append(cur, rem, ".c");
    }

    C89Emitter emitter(unit_);
    emitter.setModule(module->name);
    emitter.setExternalSliceCache(public_slices);
    if (!emitter.open(path)) {
        unit_.getErrorHandler().report(ERR_INTERNAL_ERROR, SourceLocation(), "Failed to open .c file for writing");
        return false;
    }

    emitter.emitPrologue();

    // Pass 0: Header includes
    emitter.writeString("#include \"");
    emitter.writeString(module->name);
    emitter.writeString(".h\"\n");

    for (size_t i = 0; i < module->imports.length(); ++i) {
        if (plat_strcmp(module->imports[i], module->name) == 0) continue;
        emitter.writeString("#include \"");
        emitter.writeString(module->imports[i]);
        emitter.writeString(".h\"\n");
    }
    emitter.writeString("\n");

    // Discovery Pass: Find all slice types in this module
    if (module->ast_root && module->ast_root->type == NODE_BLOCK_STMT) {
        DynamicArray<ASTNode*>* stmts = module->ast_root->as.block_stmt.statements;
        for (size_t i = 0; i < stmts->length(); ++i) {
            scanForSlices((*stmts)[i], emitter);
        }
    }
    emitter.emitBufferedSliceDefinitions();

    if (!module->ast_root || module->ast_root->type != NODE_BLOCK_STMT) {
        emitter.close();
        return true;
    }

    DynamicArray<ASTNode*>* stmts = module->ast_root->as.block_stmt.statements;

    // Pass 1: Private Type Definitions (Public types are in the .h file)
    for (size_t i = 0; i < stmts->length(); ++i) {
        if ((*stmts)[i]->type == NODE_VAR_DECL) {
            if (!(*stmts)[i]->as.var_decl->is_pub) {
                emitter.emitTypeDefinition((*stmts)[i]);
            }
        }
    }
    emitter.emitBufferedSliceDefinitions();

    // Pass 2: Global Variables
    for (size_t i = 0; i < stmts->length(); ++i) {
        if ((*stmts)[i]->type == NODE_VAR_DECL) {
            emitter.emitGlobalVarDecl((*stmts)[i], (*stmts)[i]->as.var_decl->is_pub);
        }
    }

    // Pass 3: Function Definitions
    for (size_t i = 0; i < stmts->length(); ++i) {
        if ((*stmts)[i]->type == NODE_FN_DECL) {
            emitter.emitFnDecl((*stmts)[i]->as.fn_decl);
        }
    }

    emitter.close();
    return true;
}

bool CBackend::generateMasterMain(const char* output_dir) {
    if (!entry_filename_) return true; // No main function found

    char path[1024];
    char* cur = path;
    size_t rem = sizeof(path);
    safe_append(cur, rem, output_dir);
    safe_append(cur, rem, "/");
    safe_append(cur, rem, entry_filename_);

    C89Emitter emitter(unit_);
    if (!emitter.open(path)) {
        unit_.getErrorHandler().report(ERR_INTERNAL_ERROR, SourceLocation(), "Failed to open master main file for writing");
        return false;
    }

    emitter.emitPrologue();
    emitter.writeString("/* Master Single Translation Unit (STU) file */\n\n");

    DynamicArray<Module*>& modules = unit_.getModules();
    for (size_t i = 0; i < modules.length(); ++i) {
        emitter.writeString("#include \"");
        if (plat_strcmp(modules[i]->name, "main") == 0) {
            emitter.writeString("main_module.c\"\n");
        } else {
            emitter.writeString(modules[i]->name);
            emitter.writeString(".c\"\n");
        }
    }

    emitter.close();
    return true;
}

bool CBackend::generateBuildBat(const char* output_dir) {
    if (!entry_filename_) return true;

    char path[1024];
    char* cur = path;
    size_t rem = sizeof(path);
    safe_append(cur, rem, output_dir);
    safe_append(cur, rem, "/build.bat");

    PlatFile f = plat_open_file(path, true);
    if (f == PLAT_INVALID_FILE) return false;

    const char* part1 = "@echo off\ncl /Feapp.exe ";
    const char* part2 = "\n";

    plat_write_file(f, part1, plat_strlen(part1));
    plat_write_file(f, entry_filename_, plat_strlen(entry_filename_));
    plat_write_file(f, part2, plat_strlen(part2));

    plat_close_file(f);
    return true;
}

bool CBackend::generateMakefile(const char* output_dir) {
    if (!entry_filename_) return true;

    char path[1024];
    char* cur = path;
    size_t rem = sizeof(path);
    safe_append(cur, rem, output_dir);
    safe_append(cur, rem, "/Makefile");

    PlatFile f = plat_open_file(path, true);
    if (f == PLAT_INVALID_FILE) return false;

    const char* part1 = "all:\n\tgcc -std=c89 -pedantic -o app ";
    const char* part2 = "\n";

    plat_write_file(f, part1, plat_strlen(part1));
    plat_write_file(f, entry_filename_, plat_strlen(entry_filename_));
    plat_write_file(f, part2, plat_strlen(part2));

    plat_close_file(f);
    return true;
}

bool CBackend::generateHeaderFile(Module* module, const char* output_dir, DynamicArray<const char*>* public_slices) {
    char path[1024];
    char* cur = path;
    size_t rem = sizeof(path);

    safe_append(cur, rem, output_dir);
    safe_append(cur, rem, "/");
    safe_append(cur, rem, module->name);
    safe_append(cur, rem, ".h");

    C89Emitter emitter(unit_);
    emitter.setModule(module->name);
    emitter.setExternalSliceCache(public_slices);
    if (!emitter.open(path)) {
        unit_.getErrorHandler().report(ERR_INTERNAL_ERROR, SourceLocation(), "Failed to open .h file for writing");
        return false;
    }

    /* Emit header guards */
    char guard[256];
    char* g_cur = guard;
    size_t g_rem = sizeof(guard);
    safe_append(g_cur, g_rem, "ZIG_MODULE_");

    // Simplistic uppercase conversion
    for (const char* p = module->name; *p; ++p) {
        if (g_rem > 1) {
            char c = *p;
            if (c >= 'a' && c <= 'z') c -= ('a' - 'A');
            else if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) c = '_';
            *g_cur++ = c;
            g_rem--;
        }
    }
    safe_append(g_cur, g_rem, "_H");

    emitter.writeString("#ifndef ");
    emitter.writeString(guard);
    emitter.writeString("\n#define ");
    emitter.writeString(guard);
    emitter.writeString("\n\n");

    emitter.writeString("#include \"zig_runtime.h\"\n");

    for (size_t i = 0; i < module->imports.length(); ++i) {
        if (plat_strcmp(module->imports[i], module->name) == 0) continue;
        emitter.writeString("#include \"");
        emitter.writeString(module->imports[i]);
        emitter.writeString(".h\"\n");
    }
    emitter.writeString("\n");

    // Discovery Pass: Find all slice types used in public declarations
    if (module->ast_root && module->ast_root->type == NODE_BLOCK_STMT) {
        DynamicArray<ASTNode*>* stmts = module->ast_root->as.block_stmt.statements;
        for (size_t i = 0; i < stmts->length(); ++i) {
            ASTNode* node = (*stmts)[i];
            if (node->type == NODE_VAR_DECL && node->as.var_decl->is_pub) {
                scanForSlices(node, emitter);
            } else if (node->type == NODE_FN_DECL && node->as.fn_decl->is_pub) {
                scanForSlices(node, emitter);
            }
        }
    }
    emitter.emitBufferedSliceDefinitions();

    if (module->ast_root && module->ast_root->type == NODE_BLOCK_STMT) {
        DynamicArray<ASTNode*>* stmts = module->ast_root->as.block_stmt.statements;

        // Pass 1: Public Type Definitions
        for (size_t i = 0; i < stmts->length(); ++i) {
            if ((*stmts)[i]->type == NODE_VAR_DECL) {
                if ((*stmts)[i]->as.var_decl->is_pub) {
                    emitter.emitTypeDefinition((*stmts)[i]);
                }
            }
        }
        emitter.emitBufferedSliceDefinitions();

        // Pass 2: Public global variable declarations
        for (size_t i = 0; i < stmts->length(); ++i) {
            if ((*stmts)[i]->type == NODE_VAR_DECL) {
                ASTVarDeclNode* decl = (*stmts)[i]->as.var_decl;
                if (decl->is_pub && !decl->is_extern) {
                    // Skip type and module declarations
                    if (decl->initializer && decl->initializer->resolved_type) {
                        Type* init_type = decl->initializer->resolved_type;
                        if (init_type->kind == TYPE_MODULE ||
                            (decl->is_const && (init_type->kind == TYPE_STRUCT || init_type->kind == TYPE_UNION || init_type->kind == TYPE_ENUM))) {
                            continue;
                        }
                    }

                    emitter.writeIndent();
                    emitter.writeString("extern ");

                    Type* type = (*stmts)[i]->resolved_type;
                    const char* c_name = emitter.getC89GlobalName(decl->name);
                    emitter.emitType(type, c_name);
                    emitter.writeString(";\n");
                }
            }
        }

        emitter.writeString("\n");

        // Emit public function prototypes
        for (size_t i = 0; i < stmts->length(); ++i) {
            if ((*stmts)[i]->type == NODE_FN_DECL) {
                ASTFnDeclNode* fn = (*stmts)[i]->as.fn_decl;
                if (fn->is_pub) {
                    emitter.emitFnProto(fn, true);
                    emitter.writeString("\n");
                }
            }
        }
    }

    emitter.writeString("\n#endif\n");
    emitter.close();
    return true;
}

void CBackend::scanForSlices(ASTNode* node, C89Emitter& emitter) {
    if (!node) return;

    if (node->resolved_type && node->resolved_type->kind == TYPE_SLICE) {
        emitter.ensureSliceType(node->resolved_type);
    }

    // Recursively check types in declarations
    if (node->type == NODE_VAR_DECL) {
        if (node->as.var_decl->type) scanForSlices(node->as.var_decl->type, emitter);
        if (node->as.var_decl->initializer) scanForSlices(node->as.var_decl->initializer, emitter);
    } else if (node->type == NODE_FN_DECL) {
        ASTFnDeclNode* fn = node->as.fn_decl;
        if (fn->params) {
            for (size_t i = 0; i < fn->params->length(); ++i) {
                scanForSlices((*fn->params)[i]->type, emitter);
            }
        }
        if (fn->return_type) scanForSlices(fn->return_type, emitter);
        if (fn->body) scanForSlices(fn->body, emitter);
    } else if (node->type == NODE_BLOCK_STMT) {
        if (node->as.block_stmt.statements) {
            for (size_t i = 0; i < node->as.block_stmt.statements->length(); ++i) {
                scanForSlices((*node->as.block_stmt.statements)[i], emitter);
            }
        }
    } else if (node->type == NODE_IF_STMT) {
        scanForSlices(node->as.if_stmt->condition, emitter);
        scanForSlices(node->as.if_stmt->then_block, emitter);
        if (node->as.if_stmt->else_block) scanForSlices(node->as.if_stmt->else_block, emitter);
    } else if (node->type == NODE_WHILE_STMT) {
        scanForSlices(node->as.while_stmt->condition, emitter);
        scanForSlices(node->as.while_stmt->body, emitter);
    } else if (node->type == NODE_FOR_STMT) {
        scanForSlices(node->as.for_stmt->iterable_expr, emitter);
        scanForSlices(node->as.for_stmt->body, emitter);
    } else if (node->type == NODE_RETURN_STMT) {
        if (node->as.return_stmt.expression) scanForSlices(node->as.return_stmt.expression, emitter);
    } else if (node->type == NODE_ASSIGNMENT) {
        scanForSlices(node->as.assignment->lvalue, emitter);
        scanForSlices(node->as.assignment->rvalue, emitter);
    } else if (node->type == NODE_BINARY_OP) {
        scanForSlices(node->as.binary_op->left, emitter);
        scanForSlices(node->as.binary_op->right, emitter);
    } else if (node->type == NODE_UNARY_OP) {
        scanForSlices(node->as.unary_op.operand, emitter);
    } else if (node->type == NODE_FUNCTION_CALL) {
        scanForSlices(node->as.function_call->callee, emitter);
        if (node->as.function_call->args) {
            for (size_t i = 0; i < node->as.function_call->args->length(); ++i) {
                scanForSlices((*node->as.function_call->args)[i], emitter);
            }
        }
    } else if (node->type == NODE_ARRAY_ACCESS) {
        scanForSlices(node->as.array_access->array, emitter);
        scanForSlices(node->as.array_access->index, emitter);
    } else if (node->type == NODE_MEMBER_ACCESS) {
        scanForSlices(node->as.member_access->base, emitter);
    } else if (node->type == NODE_STRUCT_INITIALIZER) {
        if (node->as.struct_initializer->type_expr) scanForSlices(node->as.struct_initializer->type_expr, emitter);
        if (node->as.struct_initializer->fields) {
            for (size_t i = 0; i < node->as.struct_initializer->fields->length(); ++i) {
                scanForSlices((*node->as.struct_initializer->fields)[i]->value, emitter);
            }
        }
    } else if (node->type == NODE_ARRAY_SLICE) {
        scanForSlices(node->as.array_slice->array, emitter);
        if (node->as.array_slice->start) scanForSlices(node->as.array_slice->start, emitter);
        if (node->as.array_slice->end) scanForSlices(node->as.array_slice->end, emitter);
        if (node->as.array_slice->base_ptr) scanForSlices(node->as.array_slice->base_ptr, emitter);
        if (node->as.array_slice->len) scanForSlices(node->as.array_slice->len, emitter);
    }
}
