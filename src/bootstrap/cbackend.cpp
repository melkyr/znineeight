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

    DynamicArray<const char*>& shared_type_cache = unit_.getEmittedTypesCache();
    for (size_t i = 0; i < modules.length(); ++i) {
        if (!generateHeaderFile(modules[i], output_dir, &shared_type_cache)) return false;
        if (!generateSourceFile(modules[i], output_dir, &shared_type_cache)) return false;
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
        unit_.getErrorHandler().report(ERR_INTERNAL_ERROR, SourceLocation(), ErrorHandler::getMessage(ERR_INTERNAL_ERROR), "Failed to open .c file for writing");
        return false;
    }

    emitter.emitPrologue();

    // Discovery Pass: Find all slice and error union types in this module
    if (module->ast_root && module->ast_root->type == NODE_BLOCK_STMT) {
        DynamicArray<Type*> visited(unit_.getArena());
        DynamicArray<ASTNode*>* stmts = module->ast_root->as.block_stmt.statements;
        for (size_t i = 0; i < stmts->length(); ++i) {
            scanForSpecialTypes((*stmts)[i], emitter, visited);
        }
    }
    emitter.emitBufferedTypeDefinitions();
    emitter.writeString("\n");

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
    emitter.emitBufferedTypeDefinitions();

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
        unit_.getErrorHandler().report(ERR_INTERNAL_ERROR, SourceLocation(), ErrorHandler::getMessage(ERR_INTERNAL_ERROR), "Failed to open master main file for writing");
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
    safe_append(cur, rem, "/build_app.bat");

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
    emitter.setExternalSliceCache(&module->emitted_types_cache);
    if (!emitter.open(path)) {
        unit_.getErrorHandler().report(ERR_INTERNAL_ERROR, SourceLocation(), ErrorHandler::getMessage(ERR_INTERNAL_ERROR), "Failed to open .h file for writing");
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

    emitter.writeString("#include \"zig_runtime.h\"\n\n");

    // Discovery Pass: Find all slice and error union types used in public declarations
    if (module->ast_root && module->ast_root->type == NODE_BLOCK_STMT) {
        DynamicArray<Type*> visited(unit_.getArena());
        DynamicArray<ASTNode*>* stmts = module->ast_root->as.block_stmt.statements;
        for (size_t i = 0; i < stmts->length(); ++i) {
            ASTNode* node = (*stmts)[i];
            if (node->type == NODE_VAR_DECL && node->as.var_decl->is_pub) {
                scanForSpecialTypes(node, emitter, visited);
            } else if (node->type == NODE_FN_DECL && node->as.fn_decl->is_pub) {
                scanForSpecialTypes(node, emitter, visited);
            }
        }
    }
    emitter.emitBufferedTypeDefinitions();
    emitter.writeString("\n");

    for (size_t i = 0; i < module->imports.length(); ++i) {
        if (plat_strcmp(module->imports[i], module->name) == 0) continue;
        emitter.writeString("#include \"");
        emitter.writeString(module->imports[i]);
        emitter.writeString(".h\"\n");
    }
    emitter.writeString("\n");

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
        emitter.emitBufferedTypeDefinitions();

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

void CBackend::scanType(Type* type, C89Emitter& emitter, DynamicArray<Type*>& visited, int depth) {
    if (!type || depth > 200) return;

    if (type->kind == TYPE_PLACEHOLDER) return;

    for (size_t i = 0; i < visited.length(); ++i) {
        if (visited[i] == type) return;
    }
    visited.append(type);

    if (type->kind == TYPE_STRUCT || type->kind == TYPE_UNION || type->kind == TYPE_ENUM) {
        emitter.ensureForwardDeclaration(type);
    }

    // Recurse first (Bottom-up discovery)
    switch (type->kind) {
        case TYPE_POINTER:
            emitter.ensureForwardDeclaration(type->as.pointer.base);
            scanType(type->as.pointer.base, emitter, visited, depth + 1);
            break;
        case TYPE_ARRAY:
            scanType(type->as.array.element_type, emitter, visited, depth + 1);
            break;
        case TYPE_SLICE:
            emitter.ensureForwardDeclaration(type->as.slice.element_type);
            scanType(type->as.slice.element_type, emitter, visited, depth + 1);
            break;
        case TYPE_OPTIONAL:
            scanType(type->as.optional.payload, emitter, visited, depth + 1);
            break;
        case TYPE_ERROR_UNION:
            scanType(type->as.error_union.payload, emitter, visited, depth + 1);
            if (!type->as.error_union.is_inferred && type->as.error_union.error_set)
                scanType(type->as.error_union.error_set, emitter, visited, depth + 1);
            break;
        case TYPE_STRUCT:
        case TYPE_UNION: {
            DynamicArray<StructField>* fields = type->as.struct_details.fields;
            if (fields) {
                for (size_t i = 0; i < fields->length(); ++i) {
                    scanType((*fields)[i].type, emitter, visited, depth + 1);
                }
            }
            break;
        }
        case TYPE_FUNCTION:
            if (type->as.function.params) {
                for (size_t i = 0; i < type->as.function.params->length(); ++i) {
                    scanType((*type->as.function.params)[i], emitter, visited, depth + 1);
                }
            }
            scanType(type->as.function.return_type, emitter, visited, depth + 1);
            break;
        case TYPE_FUNCTION_POINTER:
            if (type->as.function_pointer.param_types) {
                for (size_t i = 0; i < type->as.function_pointer.param_types->length(); ++i) {
                    scanType((*type->as.function_pointer.param_types)[i], emitter, visited, depth + 1);
                }
            }
            scanType(type->as.function_pointer.return_type, emitter, visited, depth + 1);
            break;
        default: break;
    }

    if (type->kind == TYPE_SLICE) {
        emitter.ensureSliceType(type);
    } else if (type->kind == TYPE_ERROR_UNION) {
        emitter.ensureErrorUnionType(type);
    } else if (type->kind == TYPE_OPTIONAL) {
        emitter.ensureOptionalType(type);
    }
}

void CBackend::scanForSpecialTypes(ASTNode* node, C89Emitter& emitter, DynamicArray<Type*>& visited, int depth) {
    if (!node || depth > 200) return;

    if (node->resolved_type) {
        scanType(node->resolved_type, emitter, visited, depth + 1);
    }

    // Recursively check types in declarations
    if (node->type == NODE_VAR_DECL) {
        if (node->as.var_decl->type) scanForSpecialTypes(node->as.var_decl->type, emitter, visited, depth + 1);
        if (node->as.var_decl->initializer) scanForSpecialTypes(node->as.var_decl->initializer, emitter, visited, depth + 1);
    } else if (node->type == NODE_FN_DECL) {
        ASTFnDeclNode* fn = node->as.fn_decl;
        if (fn->params) {
            for (size_t i = 0; i < fn->params->length(); ++i) {
                scanForSpecialTypes((*fn->params)[i]->type, emitter, visited, depth + 1);
            }
        }
        if (fn->return_type) scanForSpecialTypes(fn->return_type, emitter, visited, depth + 1);
        if (fn->body) scanForSpecialTypes(fn->body, emitter, visited, depth + 1);
    } else if (node->type == NODE_BLOCK_STMT) {
        if (node->as.block_stmt.statements) {
            for (size_t i = 0; i < node->as.block_stmt.statements->length(); ++i) {
                scanForSpecialTypes((*node->as.block_stmt.statements)[i], emitter, visited, depth + 1);
            }
        }
    } else if (node->type == NODE_PAREN_EXPR) {
        scanForSpecialTypes(node->as.paren_expr.expr, emitter, visited, depth + 1);
    } else if (node->type == NODE_TUPLE_LITERAL) {
        if (node->as.tuple_literal->elements) {
            for (size_t i = 0; i < node->as.tuple_literal->elements->length(); ++i) {
                scanForSpecialTypes((*node->as.tuple_literal->elements)[i], emitter, visited, depth + 1);
            }
        }
    } else if (node->type == NODE_PTR_CAST) {
        scanForSpecialTypes(node->as.ptr_cast->target_type, emitter, visited, depth + 1);
        scanForSpecialTypes(node->as.ptr_cast->expr, emitter, visited, depth + 1);
    } else if (node->type == NODE_INT_CAST || node->type == NODE_FLOAT_CAST) {
        scanForSpecialTypes(node->as.numeric_cast->target_type, emitter, visited, depth + 1);
        scanForSpecialTypes(node->as.numeric_cast->expr, emitter, visited, depth + 1);
    } else if (node->type == NODE_OFFSET_OF) {
        scanForSpecialTypes(node->as.offset_of->type_expr, emitter, visited, depth + 1);
    } else if (node->type == NODE_COMPTIME_BLOCK) {
        scanForSpecialTypes(node->as.comptime_block.expression, emitter, visited, depth + 1);
    } else if (node->type == NODE_IF_STMT) {
        scanForSpecialTypes(node->as.if_stmt->condition, emitter, visited, depth + 1);
        scanForSpecialTypes(node->as.if_stmt->then_block, emitter, visited, depth + 1);
        if (node->as.if_stmt->else_block) scanForSpecialTypes(node->as.if_stmt->else_block, emitter, visited, depth + 1);
    } else if (node->type == NODE_WHILE_STMT) {
        scanForSpecialTypes(node->as.while_stmt->condition, emitter, visited, depth + 1);
        scanForSpecialTypes(node->as.while_stmt->body, emitter, visited, depth + 1);
    } else if (node->type == NODE_FOR_STMT) {
        scanForSpecialTypes(node->as.for_stmt->iterable_expr, emitter, visited, depth + 1);
        scanForSpecialTypes(node->as.for_stmt->body, emitter, visited, depth + 1);
    } else if (node->type == NODE_RETURN_STMT) {
        if (node->as.return_stmt.expression) scanForSpecialTypes(node->as.return_stmt.expression, emitter, visited, depth + 1);
    } else if (node->type == NODE_ASSIGNMENT) {
        scanForSpecialTypes(node->as.assignment->lvalue, emitter, visited, depth + 1);
        scanForSpecialTypes(node->as.assignment->rvalue, emitter, visited, depth + 1);
    } else if (node->type == NODE_COMPOUND_ASSIGNMENT) {
        scanForSpecialTypes(node->as.compound_assignment->lvalue, emitter, visited, depth + 1);
        scanForSpecialTypes(node->as.compound_assignment->rvalue, emitter, visited, depth + 1);
    } else if (node->type == NODE_RANGE) {
        scanForSpecialTypes(node->as.range.start, emitter, visited, depth + 1);
        scanForSpecialTypes(node->as.range.end, emitter, visited, depth + 1);
    } else if (node->type == NODE_BINARY_OP) {
        scanForSpecialTypes(node->as.binary_op->left, emitter, visited, depth + 1);
        scanForSpecialTypes(node->as.binary_op->right, emitter, visited, depth + 1);
    } else if (node->type == NODE_UNARY_OP) {
        scanForSpecialTypes(node->as.unary_op.operand, emitter, visited, depth + 1);
    } else if (node->type == NODE_FUNCTION_CALL) {
        scanForSpecialTypes(node->as.function_call->callee, emitter, visited, depth + 1);
        if (node->as.function_call->args) {
            for (size_t i = 0; i < node->as.function_call->args->length(); ++i) {
                scanForSpecialTypes((*node->as.function_call->args)[i], emitter, visited, depth + 1);
            }
        }
    } else if (node->type == NODE_ARRAY_ACCESS) {
        scanForSpecialTypes(node->as.array_access->array, emitter, visited, depth + 1);
        scanForSpecialTypes(node->as.array_access->index, emitter, visited, depth + 1);
    } else if (node->type == NODE_MEMBER_ACCESS) {
        scanForSpecialTypes(node->as.member_access->base, emitter, visited, depth + 1);
    } else if (node->type == NODE_STRUCT_INITIALIZER) {
        if (node->as.struct_initializer->type_expr) scanForSpecialTypes(node->as.struct_initializer->type_expr, emitter, visited, depth + 1);
        if (node->as.struct_initializer->fields) {
            for (size_t i = 0; i < node->as.struct_initializer->fields->length(); ++i) {
                scanForSpecialTypes((*node->as.struct_initializer->fields)[i]->value, emitter, visited, depth + 1);
            }
        }
    } else if (node->type == NODE_ARRAY_SLICE) {
        scanForSpecialTypes(node->as.array_slice->array, emitter, visited, depth + 1);
        if (node->as.array_slice->start) scanForSpecialTypes(node->as.array_slice->start, emitter, visited, depth + 1);
        if (node->as.array_slice->end) scanForSpecialTypes(node->as.array_slice->end, emitter, visited, depth + 1);
        if (node->as.array_slice->base_ptr) scanForSpecialTypes(node->as.array_slice->base_ptr, emitter, visited, depth + 1);
        if (node->as.array_slice->len) scanForSpecialTypes(node->as.array_slice->len, emitter, visited, depth + 1);
    } else if (node->type == NODE_TRY_EXPR) {
        scanForSpecialTypes(node->as.try_expr.expression, emitter, visited, depth + 1);
    } else if (node->type == NODE_CATCH_EXPR) {
        scanForSpecialTypes(node->as.catch_expr->payload, emitter, visited, depth + 1);
        scanForSpecialTypes(node->as.catch_expr->else_expr, emitter, visited, depth + 1);
    } else if (node->type == NODE_SWITCH_EXPR) {
        scanForSpecialTypes(node->as.switch_expr->expression, emitter, visited, depth + 1);
        if (node->as.switch_expr->prongs) {
            for (size_t i = 0; i < node->as.switch_expr->prongs->length(); ++i) {
                ASTSwitchProngNode* prong = (*node->as.switch_expr->prongs)[i];
                if (prong->items) {
                    for (size_t j = 0; j < prong->items->length(); ++j) {
                        scanForSpecialTypes((*prong->items)[j], emitter, visited, depth + 1);
                    }
                }
                scanForSpecialTypes(prong->body, emitter, visited, depth + 1);
            }
        }
    } else if (node->type == NODE_IF_EXPR) {
        scanForSpecialTypes(node->as.if_expr->condition, emitter, visited, depth + 1);
        scanForSpecialTypes(node->as.if_expr->then_expr, emitter, visited, depth + 1);
        scanForSpecialTypes(node->as.if_expr->else_expr, emitter, visited, depth + 1);
    } else if (node->type == NODE_DEFER_STMT) {
        scanForSpecialTypes(node->as.defer_stmt.statement, emitter, visited, depth + 1);
    } else if (node->type == NODE_ERRDEFER_STMT) {
        scanForSpecialTypes(node->as.errdefer_stmt.statement, emitter, visited, depth + 1);
    }
}
