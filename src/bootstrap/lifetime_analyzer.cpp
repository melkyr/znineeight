#include "lifetime_analyzer.hpp"
#include "ast.hpp"
#include "symbol_table.hpp"
#include "type_system.hpp"
#include "utils.hpp"
#include "platform.hpp"
#include <new>


LifetimeAnalyzer::LifetimeAnalyzer(CompilationUnit& unit)
    : unit_(unit), current_assignments_(NULL) {}

void LifetimeAnalyzer::analyze(ASTNode* root) {
    visit(root);
}

void LifetimeAnalyzer::visit(ASTNode* node) {
    if (!node) return;

    switch (node->type) {
        case NODE_BLOCK_STMT:
            visitBlockStmt(&node->as.block_stmt);
            break;
        case NODE_FN_DECL:
            visitFnDecl(node->as.fn_decl);
            break;
        case NODE_RETURN_STMT:
            visitReturnStmt(&node->as.return_stmt);
            break;
        case NODE_VAR_DECL:
            visitVarDecl(node->as.var_decl);
            break;
        case NODE_ASSIGNMENT:
            visitAssignment(node->as.assignment);
            break;
        case NODE_COMPOUND_ASSIGNMENT:
            visit(node->as.compound_assignment->lvalue);
            visit(node->as.compound_assignment->rvalue);
            break;
        case NODE_IF_STMT:
            visitIfStmt(node->as.if_stmt);
            break;
        case NODE_WHILE_STMT:
            visitWhileStmt(node->as.while_stmt);
            break;
        case NODE_FOR_STMT:
            visitForStmt(node->as.for_stmt);
            break;
        case NODE_EXPRESSION_STMT:
            visit(node->as.expression_stmt.expression);
            break;
        case NODE_UNARY_OP:
            visit(node->as.unary_op.operand);
            break;
        case NODE_MEMBER_ACCESS:
            visit(node->as.member_access->base);
            break;
        case NODE_ARRAY_ACCESS:
            visit(node->as.array_access->array);
            visit(node->as.array_access->index);
            break;
        case NODE_ARRAY_SLICE:
            visit(node->as.array_slice->array);
            visit(node->as.array_slice->start);
            visit(node->as.array_slice->end);
            break;
        case NODE_PAREN_EXPR:
            visit(node->as.paren_expr.expr);
            break;
        case NODE_PTR_CAST:
            visit(node->as.ptr_cast->expr);
            break;
        case NODE_INT_CAST:
        case NODE_FLOAT_CAST:
            visit(node->as.numeric_cast->expr);
            break;
        case NODE_BINARY_OP:
            visit(node->as.binary_op->left);
            visit(node->as.binary_op->right);
            break;
        default:
            break;
    }
}

void LifetimeAnalyzer::visitBlockStmt(ASTBlockStmtNode* node) {
    if (!node || !node->statements) return;
    for (size_t i = 0; i < node->statements->length(); ++i) {
        visit((*node->statements)[i]);
    }
}

void LifetimeAnalyzer::visitFnDecl(ASTFnDeclNode* node) {
#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[LifetimeAnalysis] Analyzing function: ");
    plat_printf_debug(node->name);
    plat_printf_debug("\n");
#endif
    DynamicArray<PointerAssignment>* prev_assignments = current_assignments_;
    void* mem = unit_.getArena().alloc(sizeof(DynamicArray<PointerAssignment>));
    current_assignments_ = new (mem) DynamicArray<PointerAssignment>(unit_.getArena());

    visit(node->body);

    current_assignments_ = prev_assignments;
}

void LifetimeAnalyzer::visitReturnStmt(ASTReturnStmtNode* node) {
    if (!node->expression) return;

    if (node->expression->resolved_type && node->expression->resolved_type->kind != TYPE_POINTER && node->expression->resolved_type->kind != TYPE_SLICE) {
        return;
    }

#ifdef Z98_ENABLE_DEBUG_LOGS
    const SourceFile* file = unit_.getSourceManager().getFile(node->expression->loc.file_id);
    plat_printf_debug("[LifetimeAnalysis] Checking return statement at ");
    plat_printf_debug(file ? file->filename : "unknown");
    plat_printf_debug("\n");
#endif

    if (isDangerousLocalPointer(node->expression)) {
#ifdef Z98_ENABLE_DEBUG_LOGS
        plat_printf_debug("[LifetimeAnalysis] VIOLATION DETECTED\n");
#endif
        const char* var_name = extractVariableName(node->expression);

        const char* prefix = "Returning pointer to local variable '";
        if (node->expression->type == NODE_UNARY_OP && node->expression->as.unary_op.op == TOKEN_AMPERSAND) {
            prefix = "Returning address of local variable '";
        }

        char* msg_buffer = (char*)unit_.getArena().alloc(1024);
        char* current = msg_buffer;
        size_t remaining = 1024;
        safe_append(current, remaining, prefix);
        safe_append(current, remaining, var_name);
        safe_append(current, remaining, "' creates dangling pointer");

        unit_.getErrorHandler().report(ERR_LIFETIME_VIOLATION, node->expression->loc, ErrorHandler::getMessage(ERR_LIFETIME_VIOLATION), unit_.getArena(), msg_buffer);
    }
}

void LifetimeAnalyzer::visitVarDecl(ASTVarDeclNode* node) {
    if (node->initializer) {
        visit(node->initializer);
    }
    Symbol* sym = unit_.getSymbolTable().findInAnyScope(node->name);
    if (sym && sym->symbol_type && (sym->symbol_type->kind == TYPE_POINTER || sym->symbol_type->kind == TYPE_SLICE)) {
        if (node->initializer) {
#ifdef Z98_ENABLE_DEBUG_LOGS
            plat_printf_debug("[LifetimeAnalysis] Tracking VarDecl: ");
            plat_printf_debug(node->name);
            plat_printf_debug("\n");
#endif
            trackLocalPointerAssignment(node->name, node->initializer);
        }
    }
}

void LifetimeAnalyzer::visitAssignment(ASTAssignmentNode* node) {
    visit(node->rvalue);
    if (node->lvalue->type == NODE_IDENTIFIER) {
        const char* name = node->lvalue->as.identifier.name;
        Symbol* sym = unit_.getSymbolTable().findInAnyScope(name);
        if (sym && sym->symbol_type && (sym->symbol_type->kind == TYPE_POINTER || sym->symbol_type->kind == TYPE_SLICE)) {
#ifdef Z98_ENABLE_DEBUG_LOGS
            plat_printf_debug("[LifetimeAnalysis] Tracking Assignment to: ");
            plat_printf_debug(name);
            plat_printf_debug("\n");
#endif
            trackLocalPointerAssignment(name, node->rvalue);
        }
    }
    visit(node->lvalue);
}

void LifetimeAnalyzer::visitIfStmt(ASTIfStmtNode* node) {
    visit(node->condition);
    visit(node->then_block);
    if (node->else_block) {
        visit(node->else_block);
    }
}

void LifetimeAnalyzer::visitWhileStmt(ASTWhileStmtNode* node) {
    visit(node->condition);
    visit(node->body);
}

void LifetimeAnalyzer::visitForStmt(ASTForStmtNode* node) {
    visit(node->iterable_expr);
    visit(node->body);
}

bool LifetimeAnalyzer::isDangerousLocalPointer(ASTNode* expr) {
    if (!expr) return false;

    // String literals are global/static and never dangerous.
    if (expr->type == NODE_STRING_LITERAL) return false;

    // Handle initializers by checking their value
    if (expr->type == NODE_STRUCT_INITIALIZER || expr->type == NODE_TUPLE_LITERAL) {
        return false;
    }

    const char* provenance = getPointerProvenance(expr);
#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[LifetimeAnalysis] Provenance for expression: ");
    plat_printf_debug(provenance ? provenance : "NULL");
    plat_printf_debug("\n");
#endif
    if (!provenance) return false;

    char base_name[256];
    const char* dot = plat_strchr(provenance, '.');
    if (dot) {
        size_t len = dot - provenance;
        if (len >= 256) len = 255;
        plat_strncpy(base_name, provenance, len);
        base_name[len] = '\0';
    } else {
        plat_strncpy(base_name, provenance, 255);
        base_name[255] = '\0';
    }

    bool dangerous = isSymbolLocalVariable(base_name);
#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[LifetimeAnalysis] isDangerousLocalPointer('");
    plat_printf_debug(base_name);
    plat_printf_debug("') -> ");
    plat_printf_debug(dangerous ? "TRUE" : "FALSE");
    plat_printf_debug("\n");
#endif
    return dangerous;
}

bool LifetimeAnalyzer::isSymbolLocalVariable(const char* name) {
    Symbol* sym = unit_.getSymbolTable().findInAnyScope(name);
    if (!sym) return false;
    return (sym->flags & SYMBOL_FLAG_LOCAL);
}

void LifetimeAnalyzer::trackLocalPointerAssignment(const char* pointer_name, ASTNode* rvalue) {
    if (!current_assignments_) return;
    const char* points_to_name = NULL;

#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[LifetimeAnalysis] trackLocalPointerAssignment: ");
    plat_printf_debug(pointer_name);
    plat_printf_debug("\n");
#endif

    // 0. Explicitly handle NULL to clear assignments
    if (rvalue->type == NODE_NULL_LITERAL) {
        points_to_name = NULL;
    } else
    // 1. Resolve aliases: if rvalue is an identifier, check if it's already a tracked pointer
    if (rvalue->type == NODE_IDENTIFIER) {
        const char* rname = rvalue->as.identifier.name;
        for (size_t i = 0; i < current_assignments_->length(); ++i) {
            if (identifiers_equal((*current_assignments_)[i].pointer_name, rname)) {
                points_to_name = (*current_assignments_)[i].points_to_name;
                break;
            }
        }
    }

    // 2. If not an alias, or we want to follow member access to a tracked base
    if (!points_to_name) {
        const char* origin = getPointerOrigin(rvalue);
        if (origin) {
            char base_name[256];
            const char* dot = plat_strchr(origin, '.');
            if (dot) {
                size_t len = dot - origin;
                if (len >= 256) len = 255;
                plat_strncpy(base_name, origin, len);
                base_name[len] = '\0';
            } else {
                plat_strncpy(base_name, origin, 255);
                base_name[255] = '\0';
            }

            // Check if base_name is a local variable
            Symbol* sym = unit_.getSymbolTable().findInAnyScope(base_name);
            if (sym && (sym->flags & SYMBOL_FLAG_LOCAL)) {
#ifdef Z98_ENABLE_DEBUG_LOGS
                plat_printf_debug("[LifetimeAnalysis] Base '");
                plat_printf_debug(base_name);
                plat_printf_debug("' is a local variable\n");
#endif
                // If base is a pointer, check if it's tracked
                bool base_is_pointer = (sym->symbol_type && (sym->symbol_type->kind == TYPE_POINTER || sym->symbol_type->kind == TYPE_SLICE));
                if (base_is_pointer) {
                    for (size_t i = 0; i < current_assignments_->length(); ++i) {
                        if (plat_strcmp((*current_assignments_)[i].pointer_name, base_name) == 0) {
                            points_to_name = (*current_assignments_)[i].points_to_name;
#ifdef Z98_ENABLE_DEBUG_LOGS
                            plat_printf_debug("[LifetimeAnalysis] Base '");
                            plat_printf_debug(base_name);
                            plat_printf_debug("' is a tracked pointer, points to: ");
                            plat_printf_debug(points_to_name ? points_to_name : "NULL");
                            plat_printf_debug("\n");
#endif
                            break;
                        }
                    }
                } else {
                    // Base is a local variable (struct, array, etc), so this pointer points to a local
                    points_to_name = sym->name;
#ifdef Z98_ENABLE_DEBUG_LOGS
                    plat_printf_debug("[LifetimeAnalysis] Base '");
                    plat_printf_debug(base_name);
                    plat_printf_debug("' is a local non-pointer, setting points_to_name to it\n");
#endif
                }
            }
        }
    }

    // Update existing assignment or append new one
    for (size_t i = 0; i < current_assignments_->length(); ++i) {
        if (identifiers_equal((*current_assignments_)[i].pointer_name, pointer_name)) {
            (*current_assignments_)[i].points_to_name = points_to_name;
            return;
        }
    }

    PointerAssignment pa;
    pa.pointer_name = pointer_name;
    pa.points_to_name = points_to_name;
    current_assignments_->append(pa);
}

const char* LifetimeAnalyzer::extractVariableName(ASTNode* expr) {
    const char* origin = getPointerOrigin(expr);
    if (origin) return origin;
    return "local variable";
}

const char* LifetimeAnalyzer::getPointerProvenance(ASTNode* expr) {
    if (!expr) return NULL;

    if (expr->type == NODE_IDENTIFIER) {
        const char* name = expr->as.identifier.name;
        if (current_assignments_) {
            for (size_t i = 0; i < current_assignments_->length(); ++i) {
                if (identifiers_equal((*current_assignments_)[i].pointer_name, name)) {
                    return (*current_assignments_)[i].points_to_name;
                }
            }
        }
    }

    return getPointerOrigin(expr);
}

const char* LifetimeAnalyzer::getPointerOrigin(ASTNode* expr) {
    if (!expr) return NULL;

    switch (expr->type) {
        case NODE_IDENTIFIER:
            return expr->as.identifier.name;

        case NODE_UNARY_OP:
            if (expr->as.unary_op.op == TOKEN_AMPERSAND) {
                return getPointerOrigin(expr->as.unary_op.operand);
            }
            break;

        case NODE_MEMBER_ACCESS: {
            if (expr->as.member_access->base) {
                const char* base_origin = getPointerOrigin(expr->as.member_access->base);
                if (!base_origin) return NULL;

                size_t base_len = plat_strlen(base_origin);
                size_t field_len = plat_strlen(expr->as.member_access->field_name);
                char* combined = (char*)unit_.getArena().alloc(base_len + field_len + 2);
                plat_strcpy(combined, base_origin);
                plat_strcat(combined, ".");
                plat_strcat(combined, expr->as.member_access->field_name);
                return combined;
            }
            break;
        }

        case NODE_ARRAY_ACCESS: {
            return getPointerOrigin(expr->as.array_access->array);
        }

        case NODE_ARRAY_SLICE: {
            if (expr->as.array_slice->array) {
                return getPointerOrigin(expr->as.array_slice->array);
            }
            break;
        }

        default:
            break;
    }

    return NULL;
}
