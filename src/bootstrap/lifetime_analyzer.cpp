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
            // For now, just visit children. Compound assignment doesn't
            // create new pointer provenance in our simple model.
            visit(node->as.compound_assignment->lvalue);
            visit(node->as.compound_assignment->rvalue);
            break;
        case NODE_IF_STMT:
            visitIfStmt(node->as.if_stmt);
            break;
        case NODE_WHILE_STMT:
            visitWhileStmt(&node->as.while_stmt);
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
    DynamicArray<PointerAssignment>* prev_assignments = current_assignments_;
    void* mem = unit_.getArena().alloc(sizeof(DynamicArray<PointerAssignment>));
    current_assignments_ = new (mem) DynamicArray<PointerAssignment>(unit_.getArena());

    visit(node->body);

    current_assignments_ = prev_assignments;
}

void LifetimeAnalyzer::visitReturnStmt(ASTReturnStmtNode* node) {
    if (!node->expression) return;

    if (isDangerousLocalPointer(node->expression)) {
        const char* var_name = extractVariableName(node->expression);

        char* msg_buffer = (char*)unit_.getArena().alloc(1024);
        char* current = msg_buffer;
        size_t remaining = 1024;
        safe_append(current, remaining, "Returning pointer to local variable '");
        safe_append(current, remaining, var_name);
        safe_append(current, remaining, "' creates dangling pointer");

        unit_.getErrorHandler().report(ERR_LIFETIME_VIOLATION, node->expression->loc, msg_buffer, unit_.getArena());
    }
}

void LifetimeAnalyzer::visitVarDecl(ASTVarDeclNode* node) {
    Symbol* sym = unit_.getSymbolTable().findInAnyScope(node->name);
    if (sym && sym->symbol_type && sym->symbol_type->kind == TYPE_POINTER) {
        if (node->initializer) {
            trackLocalPointerAssignment(node->name, node->initializer);
        }
    }
}

void LifetimeAnalyzer::visitAssignment(ASTAssignmentNode* node) {
    if (node->lvalue->type == NODE_IDENTIFIER) {
        const char* name = node->lvalue->as.identifier.name;
        Symbol* sym = unit_.getSymbolTable().findInAnyScope(name);
        if (sym && sym->symbol_type && sym->symbol_type->kind == TYPE_POINTER) {
            trackLocalPointerAssignment(name, node->rvalue);
        }
    }
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
    if (expr->type == NODE_UNARY_OP && expr->as.unary_op.op == TOKEN_AMPERSAND) {
        ASTNode* operand = expr->as.unary_op.operand;
        if (operand->type == NODE_IDENTIFIER) {
            Symbol* sym = unit_.getSymbolTable().findInAnyScope(operand->as.identifier.name);
            return sym && (sym->flags & SYMBOL_FLAG_LOCAL);
        }
    }
    else if (expr->type == NODE_IDENTIFIER) {
        const char* name = expr->as.identifier.name;
        Symbol* sym = unit_.getSymbolTable().findInAnyScope(name);
        if (sym && (sym->flags & SYMBOL_FLAG_LOCAL)) {
            if (sym->symbol_type && sym->symbol_type->kind == TYPE_POINTER) {
                bool is_parameter = (sym->flags & SYMBOL_FLAG_PARAM) != 0;
                if (current_assignments_) {
                    for (size_t i = 0; i < current_assignments_->length(); ++i) {
                        if (identifiers_equal((*current_assignments_)[i].pointer_name, name)) {
                            const char* source = (*current_assignments_)[i].points_to_name;
                            if (source) {
                                return isSymbolLocalVariable(source);
                            }
                            return false;
                        }
                    }
                }
                return !is_parameter;
            }
        }
    }
    return false;
}

bool LifetimeAnalyzer::isSymbolLocalVariable(const char* name) {
    Symbol* sym = unit_.getSymbolTable().findInAnyScope(name);
    if (!sym) return false;
    return (sym->flags & SYMBOL_FLAG_LOCAL) != 0;
}

void LifetimeAnalyzer::trackLocalPointerAssignment(const char* pointer_name, ASTNode* rvalue) {
    if (!current_assignments_) return;
    const char* points_to_name = NULL;

    if (rvalue->type == NODE_UNARY_OP && rvalue->as.unary_op.op == TOKEN_AMPERSAND) {
        ASTNode* operand = rvalue->as.unary_op.operand;
        if (operand->type == NODE_IDENTIFIER) {
            const char* name = operand->as.identifier.name;
            if (isSymbolLocalVariable(name)) {
                points_to_name = name;
            }
        }
    }

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
    if (expr->type == NODE_UNARY_OP && expr->as.unary_op.op == TOKEN_AMPERSAND) {
        ASTNode* operand = expr->as.unary_op.operand;
        if (operand->type == NODE_IDENTIFIER) {
            return operand->as.identifier.name;
        }
    } else if (expr->type == NODE_IDENTIFIER) {
        return expr->as.identifier.name;
    }
    return "local variable";
}
