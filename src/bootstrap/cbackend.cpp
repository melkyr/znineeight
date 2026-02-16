#include "cbackend.hpp"
#include "compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include "utils.hpp"

CBackend::CBackend(CompilationUnit& unit) : unit_(unit) {}

bool CBackend::generate(const char* output_dir) {
    DynamicArray<Module*>& modules = unit_.getModules();
    for (size_t i = 0; i < modules.length(); ++i) {
        if (!generateSourceFile(modules[i], output_dir)) return false;
        if (!generateHeaderFile(modules[i], output_dir)) return false;
    }

    return true;
}

bool CBackend::generateSourceFile(Module* module, const char* output_dir) {
    char path[1024];
    char* cur = path;
    size_t rem = sizeof(path);

    safe_append(cur, rem, output_dir);
    safe_append(cur, rem, "/");
    safe_append(cur, rem, module->name);
    safe_append(cur, rem, ".c");

    C89Emitter emitter(unit_.getArena(), unit_.getErrorHandler());
    emitter.setModule(module->name);
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

bool CBackend::generateHeaderFile(Module* module, const char* output_dir) {
    char path[1024];
    char* cur = path;
    size_t rem = sizeof(path);

    safe_append(cur, rem, output_dir);
    safe_append(cur, rem, "/");
    safe_append(cur, rem, module->name);
    safe_append(cur, rem, ".h");

    C89Emitter emitter(unit_.getArena(), unit_.getErrorHandler());
    emitter.setModule(module->name);
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

    emitter.writeString("#include \"zig_runtime.h\"\n\n");

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

        // Pass 2: Public global variable declarations
        for (size_t i = 0; i < stmts->length(); ++i) {
            if ((*stmts)[i]->type == NODE_VAR_DECL) {
                ASTVarDeclNode* decl = (*stmts)[i]->as.var_decl;
                if (decl->is_pub && !decl->is_extern) {
                    // Skip type declarations
                    if (decl->is_const && decl->initializer) {
                        Type* init_type = decl->initializer->resolved_type;
                        if (init_type && (init_type->kind == TYPE_STRUCT || init_type->kind == TYPE_UNION || init_type->kind == TYPE_ENUM)) {
                            continue;
                        }
                    }

                    emitter.writeIndent();
                    emitter.writeString("extern ");

                    Type* type = (*stmts)[i]->resolved_type;
                    const char* c_name = emitter.getC89GlobalName(decl->name);
                    if (type && type->kind == TYPE_POINTER) {
                        emitter.emitType(type);
                        if (decl->is_const) {
                            emitter.writeString(" const");
                        }
                        emitter.writeString(" ");
                        emitter.writeString(c_name);
                    } else {
                        if (decl->is_const) {
                            emitter.writeString("const ");
                        }
                        emitter.emitType(type, c_name);
                    }
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
