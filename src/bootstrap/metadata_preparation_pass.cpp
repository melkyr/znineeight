#include "metadata_preparation_pass.hpp"
#include "type_system.hpp"
#include "symbol_table.hpp"
#include "type_checker.hpp"
#include "name_mangler.hpp"
#include "platform.hpp"
#include "utils.hpp"

MetadataPreparationPass::MetadataPreparationPass(CompilationUnit& unit)
    : unit_(unit) {}

void MetadataPreparationPass::run() {
    DynamicArray<Module*>& modules = unit_.getModules();

    // Pass 1: Resolve all placeholders for all symbols in all modules.
    for (size_t i = 0; i < modules.length(); ++i) {
        Module* mod = modules[i];
        if (!mod->symbols) continue;

        const DynamicArray<Scope*>& scopes = mod->symbols->getAllScopes();
        for (size_t j = 0; j < scopes.length(); ++j) {
            Scope* scope = scopes[j];
            for (size_t k = 0; k < scope->buckets.length(); ++k) {
                Scope::SymbolEntry* entry = scope->buckets[k];
                while (entry) {
                    if (entry->symbol.symbol_type) {
                        TypeChecker checker(unit_);
                        entry->symbol.symbol_type = checker.resolveAllPlaceholders(entry->symbol.symbol_type);
                    }
                    entry = entry->next;
                }
            }
        }
    }

    // Pass 2: Ensure metadata and layouts for all types
    for (size_t i = 0; i < modules.length(); ++i) {
        Module* mod = modules[i];
        if (!mod->symbols) continue;

        const DynamicArray<Scope*>& scopes = mod->symbols->getAllScopes();
        for (size_t j = 0; j < scopes.length(); ++j) {
            Scope* scope = scopes[j];
            for (size_t k = 0; k < scope->buckets.length(); ++k) {
                Scope::SymbolEntry* entry = scope->buckets[k];
                while (entry) {
                    if (entry->symbol.symbol_type) {
                        prepareTypeMetadata(mod, entry->symbol.symbol_type);
                    }
                    entry = entry->next;
                }
            }
        }
    }

    // Pass 3: Collect reachable types for headers using post-order traversal
    for (size_t i = 0; i < modules.length(); ++i) {
        Module* mod = modules[i];
        if (!mod->symbols) continue;

        DynamicArray<Type*> visited(unit_.getArena());
        const DynamicArray<Scope*>& scopes = mod->symbols->getAllScopes();

        if (scopes.length() > 0) {
            Scope* global_scope = scopes[0];
            for (size_t k = 0; k < global_scope->buckets.length(); ++k) {
                Scope::SymbolEntry* entry = global_scope->buckets[k];
                while (entry) {
                    const Symbol& sym = entry->symbol;
                    bool is_pub = false;
                    if (sym.details) {
                        if (sym.kind == SYMBOL_VARIABLE) is_pub = ((ASTVarDeclNode*)sym.details)->is_pub;
                        else if (sym.kind == SYMBOL_FUNCTION) is_pub = ((ASTFnDeclNode*)sym.details)->is_pub;
                    }

                    if (is_pub || (sym.flags & SYMBOL_FLAG_EXTERN)) {
                        collectReachableTypes(mod, sym.symbol_type, visited);
                    }
                    entry = entry->next;
                }
            }
        }

        collectStaticFunctions(mod);
    }
}

void MetadataPreparationPass::collectReachableTypes(Module* mod, Type* type, DynamicArray<Type*>& visited) {
    if (!type) return;

    // Check if already visited
    for (size_t i = 0; i < visited.length(); ++i) {
        if (visited[i] == type) return;
    }
    visited.append(type);

    // Recursively visit component types FIRST (Post-order traversal)
    switch (type->kind) {
        case TYPE_POINTER:
            // Pointers only need forward declaration of base type, so they don't force ordering.
            break;
        case TYPE_ARRAY:
            collectReachableTypes(mod, type->as.array.element_type, visited);
            break;
        case TYPE_SLICE:
            // Slices only contain a pointer to the element type, so they don't force ordering.
            break;
        case TYPE_OPTIONAL:
            collectReachableTypes(mod, type->as.optional.payload, visited);
            break;
        case TYPE_ERROR_UNION:
            collectReachableTypes(mod, type->as.error_union.payload, visited);
            if (type->as.error_union.error_set) {
                collectReachableTypes(mod, type->as.error_union.error_set, visited);
            }
            break;
        case TYPE_FUNCTION:
            if (type->as.function.params) {
                for (size_t i = 0; i < type->as.function.params->length(); ++i) {
                    collectReachableTypes(mod, (*type->as.function.params)[i], visited);
                }
            }
            collectReachableTypes(mod, type->as.function.return_type, visited);
            break;
        case TYPE_FUNCTION_POINTER:
            if (type->as.function_pointer.param_types) {
                for (size_t i = 0; i < type->as.function_pointer.param_types->length(); ++i) {
                    collectReachableTypes(mod, (*type->as.function_pointer.param_types)[i], visited);
                }
            }
            collectReachableTypes(mod, type->as.function_pointer.return_type, visited);
            break;
        case TYPE_STRUCT:
        case TYPE_UNION:
            if (type->as.struct_details.fields) {
                for (size_t i = 0; i < type->as.struct_details.fields->length(); ++i) {
                    collectReachableTypes(mod, (*type->as.struct_details.fields)[i].type, visited);
                }
            }
            break;
        case TYPE_TAGGED_UNION:
            if (type->as.tagged_union.tag_type) {
                collectReachableTypes(mod, type->as.tagged_union.tag_type, visited);
            }
            if (type->as.tagged_union.payload_fields) {
                for (size_t i = 0; i < type->as.tagged_union.payload_fields->length(); ++i) {
                    collectReachableTypes(mod, (*type->as.tagged_union.payload_fields)[i].type, visited);
                }
            }
            break;
        case TYPE_ENUM:
            collectReachableTypes(mod, type->as.enum_details.backing_type, visited);
            break;
        default:
            break;
    }

    // Add to header types list AFTER its dependencies
    if (isHeaderType(type)) {
        bool already_in = false;
        for (size_t i = 0; i < mod->header_types.length(); ++i) {
            if (mod->header_types[i] == type) {
                already_in = true;
                break;
            }
        }
        if (!already_in) {
            mod->header_types.append(type);
        }
    }
}

void MetadataPreparationPass::prepareTypeMetadata(Module* mod, Type* type) {
    if (!type) return;

    // 1. Resolve placeholder if still present
    if (type->kind == TYPE_PLACEHOLDER) {
        if (type->as.placeholder.decl_node) {
            TypeChecker checker(unit_);
            type = checker.resolvePlaceholder(type);
        }
    }

    // 2. Ensure c_name is set for aggregate types
    if (type->kind == TYPE_STRUCT || type->kind == TYPE_UNION || type->kind == TYPE_TAGGED_UNION || type->kind == TYPE_ENUM) {
        if (!type->c_name) {
            const char* name = NULL;
            if (type->kind == TYPE_ENUM) name = type->as.enum_details.name;
            else if (type->kind == TYPE_TAGGED_UNION) name = type->as.tagged_union.name;
            else name = type->as.struct_details.name;

            if (name) {
                type->c_name = unit_.getNameMangler().mangleTypeName(name, mod->name);
            }
        }
    }

    // 3. Compute special type mangled names
    if (type->kind == TYPE_SLICE || type->kind == TYPE_OPTIONAL || type->kind == TYPE_ERROR_UNION) {
        if (!type->c_name) {
            type->c_name = unit_.getNameMangler().mangleType(type);
        }
    }

    // 4. Force layout calculation
    if (isTypeComplete(type)) {
        if (type->size == 0 && type->kind != TYPE_VOID && type->kind != TYPE_NORETURN) {
            refreshLayout(type);
        }
    }
}

void MetadataPreparationPass::collectStaticFunctions(Module* mod) {
    if (!mod->ast_root || mod->ast_root->type != NODE_BLOCK_STMT) return;

    DynamicArray<ASTNode*>* stmts = mod->ast_root->as.block_stmt.statements;
    for (size_t i = 0; i < stmts->length(); ++i) {
        ASTNode* node = (*stmts)[i];
        if (node->type == NODE_FN_DECL) {
            ASTFnDeclNode* fn = node->as.fn_decl;
            /* In RetroZig, every top-level function should have a symbol in the module scope. */
            Symbol* sym = mod->symbols->lookup(fn->name);
            if (sym && sym->kind == SYMBOL_FUNCTION) {
                /* We collect non-pub functions for forward declarations in .c files. 
                   Includes both static and non-pub extern functions to ensure they are prototyped before use. */
                if (!fn->is_pub) {
                    mod->static_function_prototypes.append(sym);
                }
            }
        }
    }
}

bool MetadataPreparationPass::isHeaderType(Type* type) {
    if (!type) return false;
    if (type->kind < TYPE_POINTER && type->kind != TYPE_C_CHAR) return false;

    // Aggregates with names
    if (type->kind == TYPE_STRUCT || type->kind == TYPE_UNION || type->kind == TYPE_TAGGED_UNION || type->kind == TYPE_ENUM) {
        const char* name = NULL;
        if (type->kind == TYPE_ENUM) name = type->as.enum_details.name;
        else if (type->kind == TYPE_TAGGED_UNION) name = type->as.tagged_union.name;
        else name = type->as.struct_details.name;

        if (name) {
            return true;
        }
    }

    // Special types needing typedefs
    if (type->kind == TYPE_SLICE || type->kind == TYPE_ERROR_UNION || type->kind == TYPE_OPTIONAL) {
        return true;
    }

    return false;
}
