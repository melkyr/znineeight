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
                /* Snapshot bucket to prevent iterator invalidation if resolution adds new symbols */
                DynamicArray<Symbol*> snapshot(unit_.getArena());
                Scope::SymbolEntry* curr = entry;
                while (curr) {
                    snapshot.append(&curr->symbol);
                    curr = curr->next;
                }
                for (size_t snap_i = 0; snap_i < snapshot.length(); ++snap_i) {
                    Symbol* sym = snapshot[snap_i];
                    if (sym->symbol_type) {
                        TypeChecker checker(unit_);
                        sym->symbol_type = checker.resolveAllPlaceholders(sym->symbol_type);
                    }
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
                /* Snapshot bucket to prevent iterator invalidation if metadata preparation adds new symbols */
                DynamicArray<Symbol*> snapshot(unit_.getArena());
                Scope::SymbolEntry* curr = entry;
                while (curr) {
                    snapshot.append(&curr->symbol);
                    curr = curr->next;
                }
                for (size_t snap_i = 0; snap_i < snapshot.length(); ++snap_i) {
                    Symbol* sym = snapshot[snap_i];
                    if (sym->symbol_type) {
                        prepareTypeMetadata(mod, sym->symbol_type);
                    }
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
                /* Snapshot bucket to prevent iterator invalidation if collection adds new symbols */
                DynamicArray<Symbol*> snapshot(unit_.getArena());
                Scope::SymbolEntry* curr = entry;
                while (curr) {
                    snapshot.append(&curr->symbol);
                    curr = curr->next;
                }
                for (size_t snap_i = 0; snap_i < snapshot.length(); ++snap_i) {
                    Symbol* sym = snapshot[snap_i];
                    bool is_pub = false;
                    if (sym->details) {
                        if (sym->kind == SYMBOL_VARIABLE) is_pub = ((ASTVarDeclNode*)sym->details)->is_pub;
                        else if (sym->kind == SYMBOL_FUNCTION) is_pub = ((ASTFnDeclNode*)sym->details)->is_pub;
                    }

                    if (is_pub || (sym->flags & SYMBOL_FLAG_EXTERN)) {
                        collectReachableTypes(mod, sym->symbol_type, visited);

                        /* If this is a type constant (e.g., pub const T = struct {...}),
                           ensure the actual type is also collected. */
                        if (sym->symbol_type->kind == TYPE_TYPE && sym->details) {
                            ASTVarDeclNode* decl = (ASTVarDeclNode*)sym->details;
                            if (decl->initializer && decl->initializer->resolved_type) {
                                collectReachableTypes(mod, decl->initializer->resolved_type, visited);
                            }
                        }
                    }
                }
            }
        }

        collectStaticFunctions(mod);
    }
}

void MetadataPreparationPass::collectReachableTypes(Module* mod, Type* type, DynamicArray<Type*>& visited) {
    if (!type) return;

    // Check if already visited in this traversal
    for (size_t i = 0; i < visited.length(); ++i) {
        if (visited[i] == type) return;
    }

    visited.append(type);

    // 1. Recurse into VALUE dependencies FIRST.
    // This ensures that if A depends on B by value, B is added to header_types before A.
    // IMPORTANT: Even if B is defined in another module, we must visit it to discover
    // its transitive dependencies (like special types) that might need to be emitted here.
    switch (type->kind) {
        case TYPE_ARRAY:
            collectReachableTypes(mod, type->as.array.element_type, visited);
            break;
        case TYPE_SLICE:
            collectReachableTypes(mod, type->as.slice.element_type, visited);
            break;
        case TYPE_STRUCT:
        case TYPE_UNION:
            if (type->as.struct_details.tag_type) {
                collectReachableTypes(mod, type->as.struct_details.tag_type, visited);
            }
            if (type->as.struct_details.fields) {
                DynamicArray<StructField>* fields = type->as.struct_details.fields;
                size_t count = fields->length();
                StructField* snapshot = (StructField*)unit_.getArena().alloc(count * sizeof(StructField));
                for (size_t i = 0; i < count; ++i) {
                    snapshot[i] = (*fields)[i];
                }
                for (size_t i = 0; i < count; ++i) {
                    collectReachableTypes(mod, snapshot[i].type, visited);
                }
            }
            break;
        case TYPE_TAGGED_UNION:
            if (type->as.tagged_union.tag_type) {
                collectReachableTypes(mod, type->as.tagged_union.tag_type, visited);
            }
            if (type->as.tagged_union.payload_fields) {
                DynamicArray<StructField>* fields = type->as.tagged_union.payload_fields;
                size_t count = fields->length();
                StructField* snapshot = (StructField*)unit_.getArena().alloc(count * sizeof(StructField));
                for (size_t i = 0; i < count; ++i) {
                    snapshot[i] = (*fields)[i];
                }
                for (size_t i = 0; i < count; ++i) {
                    collectReachableTypes(mod, snapshot[i].type, visited);
                }
            }
            break;
        case TYPE_ERROR_UNION:
            collectReachableTypes(mod, type->as.error_union.payload, visited);
            if (type->as.error_union.error_set) {
                collectReachableTypes(mod, type->as.error_union.error_set, visited);
            }
            break;
        case TYPE_OPTIONAL:
            collectReachableTypes(mod, type->as.optional.payload, visited);
            break;
        case TYPE_TUPLE:
            if (type->as.tuple.elements) {
                DynamicArray<Type*>* elements = type->as.tuple.elements;
                size_t count = elements->length();
                Type** snapshot = (Type**)unit_.getArena().alloc(count * sizeof(Type*));
                for (size_t i = 0; i < count; ++i) {
                    snapshot[i] = (*elements)[i];
                }
                for (size_t i = 0; i < count; ++i) {
                    collectReachableTypes(mod, snapshot[i], visited);
                }
            }
            break;
        case TYPE_ENUM:
            collectReachableTypes(mod, type->as.enum_details.backing_type, visited);
            break;
        default:
            break;
    }

    // 2. Add ourselves to header_types if we belong in this module's header.
    if (isHeaderType(type)) {
        /* We add the type to header_types if:
           a) It's owned by this module.
           b) It's a special type (Slice, Optional, ErrorUnion) - these are emitted in every header that uses them for self-containment.
           c) It's from another module - we add it so it gets forward-declared in this module's header.
           In summary, any reachable header type is added to the module's header_types. */
        bool already_in = false;
        /* Take a snapshot to prevent iterator invalidation if mod->header_types is modified during recursion */
        DynamicArray<Type*> header_snapshot(unit_.getArena());
        for (size_t i = 0; i < mod->header_types.length(); ++i) {
            header_snapshot.append(mod->header_types[i]);
        }
        for (size_t i = 0; i < header_snapshot.length(); ++i) {
            if (header_snapshot[i] == type) {
                already_in = true;
                break;
            }
        }
        if (!already_in) {
            mod->header_types.append(type);
        }
    }

    // 3. Finally, recurse into POINTER and FUNCTION dependencies.
    // These do NOT force a definition order, but we must find them so they get forward declared.
    switch (type->kind) {
        case TYPE_POINTER:
            collectReachableTypes(mod, type->as.pointer.base, visited);
            break;
        case TYPE_SLICE:
            collectReachableTypes(mod, type->as.slice.element_type, visited);
            break;
        case TYPE_FUNCTION:
            if (type->as.function.params) {
                DynamicArray<Type*>* params = type->as.function.params;
                size_t count = params->length();
                Type** snapshot = (Type**)unit_.getArena().alloc(count * sizeof(Type*));
                for (size_t i = 0; i < count; ++i) {
                    snapshot[i] = (*params)[i];
                }
                for (size_t i = 0; i < count; ++i) {
                    collectReachableTypes(mod, snapshot[i], visited);
                }
            }
            collectReachableTypes(mod, type->as.function.return_type, visited);
            break;
        case TYPE_FUNCTION_POINTER:
            if (type->as.function_pointer.param_types) {
                DynamicArray<Type*>* params = type->as.function_pointer.param_types;
                size_t count = params->length();
                Type** snapshot = (Type**)unit_.getArena().alloc(count * sizeof(Type*));
                for (size_t i = 0; i < count; ++i) {
                    snapshot[i] = (*params)[i];
                }
                for (size_t i = 0; i < count; ++i) {
                    collectReachableTypes(mod, snapshot[i], visited);
                }
            }
            collectReachableTypes(mod, type->as.function_pointer.return_type, visited);
            break;
        default:
            break;
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
            type->c_name = unit_.getNameMangler().mangleType(type);
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
            /* In Z98, every top-level function should have a symbol in the module scope. */
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
