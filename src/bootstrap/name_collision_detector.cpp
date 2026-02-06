#include "name_collision_detector.hpp"
#include "compilation_unit.hpp"
#include "error_handler.hpp"
#include "utils.hpp"
#include "platform.hpp"
#include <new>

NameCollisionDetector::NameCollisionDetector(CompilationUnit& unit)
    : unit_(unit), error_handler_(unit.getErrorHandler()),
      scope_stack_(unit.getArena()), collision_count_(0) {
    enterScope(); // Initial global scope
}

void NameCollisionDetector::check(ASTNode* root) {
    visit(root);
}

bool NameCollisionDetector::hasCollisions() const {
    return collision_count_ > 0;
}

int NameCollisionDetector::getCollisionCount() const {
    return collision_count_;
}

void NameCollisionDetector::enterScope() {
    void* mem = unit_.getArena().alloc(sizeof(ScopeInfo));
    ScopeInfo* scope = new (mem) ScopeInfo(unit_.getArena());
    scope_stack_.append(scope);
}

void NameCollisionDetector::exitScope() {
    if (scope_stack_.length() > 0) {
        scope_stack_.pop_back();
    }
}

void NameCollisionDetector::visit(ASTNode* node) {
    if (!node) return;

    switch (node->type) {
        case NODE_BLOCK_STMT: {
            enterScope();
            DynamicArray<ASTNode*>* stmts = node->as.block_stmt.statements;
            for (size_t i = 0; i < stmts->length(); ++i) {
                visit((*stmts)[i]);
            }
            exitScope();
            break;
        }

        case NODE_FN_DECL:
            visitFnDecl(node->as.fn_decl);
            break;

        case NODE_VAR_DECL:
            visitVarDecl(node->as.var_decl);
            break;

        case NODE_IF_STMT:
            visit(node->as.if_stmt->condition);
            visit(node->as.if_stmt->then_block);
            if (node->as.if_stmt->else_block) {
                visit(node->as.if_stmt->else_block);
            }
            break;

        case NODE_WHILE_STMT:
            visit(node->as.while_stmt.condition);
            visit(node->as.while_stmt.body);
            break;

        case NODE_FOR_STMT:
            visit(node->as.for_stmt->iterable_expr);
            // The for loop body is a block, but the capture variables belong to the loop scope.
            // However, Zig's block statement already enters a scope.
            // To match Zig semantics where capture variables are in the block scope:
            // We'll let the block statement visit handle its scope, but we need to
            // inject the capture names into that scope.
            // This is tricky because NODE_FOR_STMT has a 'body' which is NODE_BLOCK_STMT.
            // If we visit body, it enters a scope.

            // For simplicity in bootstrap, we'll just visit the body.
            // If we wanted to be precise:
            enterScope();
            if (node->as.for_stmt->item_name) {
                scope_stack_.back()->variable_names.append(node->as.for_stmt->item_name);
            }
            if (node->as.for_stmt->index_name) {
                scope_stack_.back()->variable_names.append(node->as.for_stmt->index_name);
            }
            // If body is a block, it will enter another scope. This is fine for collision detection
            // because names in the outer 'for' scope won't collide with the inner block scope.
            visit(node->as.for_stmt->body);
            exitScope();
            break;

        case NODE_SWITCH_EXPR:
            visit(node->as.switch_expr->expression);
            for (size_t i = 0; i < node->as.switch_expr->prongs->length(); ++i) {
                ASTSwitchProngNode* prong = (*node->as.switch_expr->prongs)[i];
                visit(prong->body);
            }
            break;

        case NODE_TRY_EXPR:
            visit(node->as.try_expr.expression);
            break;

        case NODE_CATCH_EXPR:
            visit(node->as.catch_expr->payload);
            // Catch can have a capture |err|
            if (node->as.catch_expr->error_name) {
                enterScope();
                scope_stack_.back()->variable_names.append(node->as.catch_expr->error_name);
                visit(node->as.catch_expr->else_expr);
                exitScope();
            } else {
                visit(node->as.catch_expr->else_expr);
            }
            break;

        case NODE_ORELSE_EXPR:
            visit(node->as.orelse_expr->payload);
            visit(node->as.orelse_expr->else_expr);
            break;

        case NODE_DEFER_STMT:
            visit(node->as.defer_stmt.statement);
            break;

        case NODE_ERRDEFER_STMT:
            visit(node->as.errdefer_stmt.statement);
            break;

        case NODE_EXPRESSION_STMT:
            visit(node->as.expression_stmt.expression);
            break;

        default:
            break;
    }
}

void NameCollisionDetector::visitFnDecl(ASTFnDeclNode* node) {
    if (checkCollisionInCurrentScope(node->name)) {
        SourceLocation loc = node->body ? node->body->loc : SourceLocation();
        reportCollision(loc, node->name, "function");
    } else {
        scope_stack_.back()->function_names.append(node->name);
    }

    // Visit parameters in a new scope
    enterScope();
    for (size_t i = 0; i < node->params->length(); ++i) {
        ASTParamDeclNode* param = (*node->params)[i];
        if (checkCollisionInCurrentScope(param->name)) {
             reportCollision(node->body ? node->body->loc : SourceLocation(), param->name, "parameter");
        } else {
            scope_stack_.back()->variable_names.append(param->name);
        }
    }
    visit(node->body);
    exitScope();
}

void NameCollisionDetector::visitVarDecl(ASTVarDeclNode* node) {
    if (checkCollisionInCurrentScope(node->name)) {
        reportCollision(node->name_loc, node->name, "variable");
    } else {
        scope_stack_.back()->variable_names.append(node->name);
    }
    if (node->initializer) {
        visit(node->initializer);
    }
}

bool NameCollisionDetector::checkCollisionInCurrentScope(const char* name) {
    if (scope_stack_.length() == 0) return false;
    ScopeInfo* current = scope_stack_.back();

    for (size_t i = 0; i < current->function_names.length(); ++i) {
        if (plat_strcmp(current->function_names[i], name) == 0) return true;
    }
    for (size_t i = 0; i < current->variable_names.length(); ++i) {
        if (plat_strcmp(current->variable_names[i], name) == 0) return true;
    }
    return false;
}

void NameCollisionDetector::reportCollision(SourceLocation loc, const char* name, const char* entity_type) {
    collision_count_++;
    char buffer[256];
    char* cur = buffer;
    size_t rem = sizeof(buffer);

    safe_append(cur, rem, "Redeclaration of name '");
    safe_append(cur, rem, name);
    safe_append(cur, rem, "' as a ");
    safe_append(cur, rem, entity_type);
    safe_append(cur, rem, " in the same scope");

    error_handler_.report(ERR_REDEFINITION, loc, buffer, unit_.getArena());
}
