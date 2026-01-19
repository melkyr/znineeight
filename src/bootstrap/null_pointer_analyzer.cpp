#include "null_pointer_analyzer.hpp"
#include "ast.hpp"
#include "symbol_table.hpp"
#include "type_system.hpp"
#include "utils.hpp"
#include <new>
#include <cstring>

NullPointerAnalyzer::NullPointerAnalyzer(CompilationUnit& unit)
    : unit_(unit), current_scope_(NULL), scopes_(unit.getArena()) {
}

void NullPointerAnalyzer::analyze(ASTNode* root) {
    pushScope(); // Global scope
    visit(root);
    popScope();
}

void NullPointerAnalyzer::pushScope() {
    void* mem = unit_.getArena().alloc(sizeof(DynamicArray<VarTrack>));
    DynamicArray<VarTrack>* new_scope = new (mem) DynamicArray<VarTrack>(unit_.getArena());
    scopes_.append(new_scope);
    current_scope_ = new_scope;
}

void NullPointerAnalyzer::popScope() {
    if (scopes_.length() > 0) {
        scopes_.pop_back();
        if (scopes_.length() > 0) {
            current_scope_ = scopes_.back();
        } else {
            current_scope_ = NULL;
        }
    }
}

void NullPointerAnalyzer::addVariable(const char* name, PointerState state) {
    if (!current_scope_) return;
    VarTrack vt;
    vt.name = name;
    vt.state = state;
    current_scope_->append(vt);
}

void NullPointerAnalyzer::setState(const char* name, PointerState state) {
    // Search from innermost scope outwards for an existing variable to update
    for (int i = (int)scopes_.length() - 1; i >= 0; --i) {
        DynamicArray<VarTrack>* scope = scopes_[i];
        for (size_t j = 0; j < scope->length(); ++j) {
            if ((*scope)[j].name == name) {
                (*scope)[j].state = state;
                return;
            }
        }
    }

    // If not found, it might be a new variable or a global.
    // In Phase 1, we only update existing tracked variables.
}

PointerState NullPointerAnalyzer::getState(const char* name) {
    // Search from innermost scope outwards
    for (int i = (int)scopes_.length() - 1; i >= 0; --i) {
        DynamicArray<VarTrack>* scope = scopes_[i];
        for (size_t j = 0; j < scope->length(); ++j) {
            if ((*scope)[j].name == name) {
                return (*scope)[j].state;
            }
        }
    }
    return PS_MAYBE;
}

void NullPointerAnalyzer::visit(ASTNode* node) {
    if (!node) return;

    switch (node->type) {
        case NODE_FN_DECL:
            visitFnDecl(node->as.fn_decl);
            break;
        case NODE_BLOCK_STMT:
            visitBlock(&node->as.block_stmt);
            break;
        case NODE_VAR_DECL:
            visitVarDecl(node->as.var_decl);
            break;
        case NODE_ASSIGNMENT:
            visitAssignment(node->as.assignment);
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
        case NODE_RETURN_STMT:
            visitReturnStmt(&node->as.return_stmt);
            break;
        case NODE_EXPRESSION_STMT:
            visit(node->as.expression_stmt.expression);
            break;
        case NODE_UNARY_OP:
            if (node->as.unary_op.op == TOKEN_STAR) {
                checkDereference(node->as.unary_op.operand);
            }
            visit(node->as.unary_op.operand);
            break;
        case NODE_BINARY_OP:
            visit(node->as.binary_op->left);
            visit(node->as.binary_op->right);
            break;
        case NODE_FUNCTION_CALL:
            visit(node->as.function_call->callee);
            if (node->as.function_call->args) {
                for (size_t i = 0; i < node->as.function_call->args->length(); ++i) {
                    visit((*node->as.function_call->args)[i]);
                }
            }
            break;
        case NODE_ARRAY_ACCESS:
            checkDereference(node->as.array_access->array);
            visit(node->as.array_access->array);
            visit(node->as.array_access->index);
            break;
        default:
            break;
    }
}

void NullPointerAnalyzer::visitFnDecl(ASTFnDeclNode* node) {
    pushScope();

    // Add parameters to the scope
    if (node->params) {
        for (size_t i = 0; i < node->params->length(); ++i) {
            ASTParamDeclNode* param = (*node->params)[i];
            // Parameters are considered MAYBE initially
            addVariable(param->name, PS_MAYBE);
        }
    }

    visit(node->body);
    popScope();
}

void NullPointerAnalyzer::visitBlock(ASTBlockStmtNode* node) {
    pushScope();
    if (node->statements) {
        for (size_t i = 0; i < node->statements->length(); ++i) {
            visit((*node->statements)[i]);
        }
    }
    popScope();
}

void NullPointerAnalyzer::visitVarDecl(ASTVarDeclNode* node) {
    Symbol* sym = unit_.getSymbolTable().lookup(node->name);
    if (sym && sym->symbol_type && sym->symbol_type->kind == TYPE_POINTER) {
        PointerState state = PS_UNINIT;
        if (node->initializer) {
            visit(node->initializer);
            state = getExpressionState(node->initializer);
        }
        addVariable(node->name, state);
    }
}

void NullPointerAnalyzer::visitAssignment(ASTAssignmentNode* node) {
    visit(node->rvalue);
    if (node->lvalue->type == NODE_IDENTIFIER) {
        const char* name = node->lvalue->as.identifier.name;
        Symbol* sym = unit_.getSymbolTable().lookup(name);
        if (sym && sym->symbol_type && sym->symbol_type->kind == TYPE_POINTER) {
            PointerState state = getExpressionState(node->rvalue);
            setState(name, state);
            return;
        }
    }
    visit(node->lvalue);
}

void NullPointerAnalyzer::visitIfStmt(ASTIfStmtNode* node) {
    visit(node->condition);
    visit(node->then_block);
    if (node->else_block) {
        visit(node->else_block);
    }
}

void NullPointerAnalyzer::visitWhileStmt(ASTWhileStmtNode* node) {
    visit(node->condition);
    visit(node->body);
}

void NullPointerAnalyzer::visitForStmt(ASTForStmtNode* node) {
    visit(node->iterable_expr);
    pushScope();
    addVariable(node->item_name, PS_MAYBE);
    if (node->index_name) {
        addVariable(node->index_name, PS_SAFE);
    }
    visit(node->body);
    popScope();
}

void NullPointerAnalyzer::visitReturnStmt(ASTReturnStmtNode* node) {
    if (node->expression) {
        visit(node->expression);
    }
}

PointerState NullPointerAnalyzer::getExpressionState(ASTNode* expr) {
    if (!expr) return PS_MAYBE;

    switch (expr->type) {
        case NODE_NULL_LITERAL:
            return PS_NULL;
        case NODE_INTEGER_LITERAL:
            if (expr->as.integer_literal.value == 0) return PS_NULL;
            return PS_MAYBE;
        case NODE_UNARY_OP:
            if (expr->as.unary_op.op == TOKEN_AMPERSAND) return PS_SAFE;
            return PS_MAYBE;
        case NODE_IDENTIFIER:
            return getState(expr->as.identifier.name);
        default:
            return PS_MAYBE;
    }
}

void NullPointerAnalyzer::checkDereference(ASTNode* /*expr*/) {
    // Phase 2 implementation
}
