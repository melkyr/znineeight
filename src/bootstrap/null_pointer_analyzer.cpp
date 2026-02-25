#include "null_pointer_analyzer.hpp"
#include "ast.hpp"
#include "symbol_table.hpp"
#include "type_system.hpp"
#include "utils.hpp"
#include <new>


StateMap::StateMap(ArenaAllocator& arena, StateMap* p)
    : vars(arena), modified(arena), parent(p), arena_(arena) {
}

StateMap::StateMap(const StateMap& other, ArenaAllocator& arena)
    : vars(arena), modified(arena), parent(other.parent), arena_(arena) {
    for (size_t i = 0; i < other.vars.length(); ++i) {
        vars.append(other.vars[i]);
    }
}

void StateMap::setState(const char* name, PointerState state) {
    // Search BACKWARDS for most recent declaration (to handle shadowing)
    for (int i = (int)vars.length() - 1; i >= 0; --i) {
        if (identifiers_equal(vars[i].name, name)) {
            vars[i].state = state;
            // Mark as modified
            bool already_modified = false;
            for (size_t j = 0; j < modified.length(); ++j) {
                if (identifiers_equal(modified[j], name)) {
                    already_modified = true;
                    break;
                }
            }
            if (!already_modified) {
                modified.append(name);
            }
            return;
        }
    }
    // If it's a new variable in this scope
    addVariable(name, state);
}

PointerState StateMap::getState(const char* name) const {
    // Search BACKWARDS
    for (int i = (int)vars.length() - 1; i >= 0; --i) {
        if (identifiers_equal(vars[i].name, name)) {
            return vars[i].state;
        }
    }
    return PS_MAYBE;
}

bool StateMap::hasVariable(const char* name) const {
    for (size_t i = 0; i < vars.length(); ++i) {
        if (identifiers_equal(vars[i].name, name)) {
            return true;
        }
    }
    return false;
}

void StateMap::addVariable(const char* name, PointerState state) {
    VarTrack vt;
    vt.name = name;
    vt.state = state;
    vars.append(vt);
}

NullPointerAnalyzer::NullPointerAnalyzer(CompilationUnit& unit)
    : unit_(unit), current_scope_(NULL), scopes_(unit.getArena()) {
}

void NullPointerAnalyzer::analyze(ASTNode* root) {
    pushScope(); // Global scope
    visit(root);
    popScope();
}

void NullPointerAnalyzer::pushScope(bool copy_parent) {
    void* mem = unit_.getArena().alloc(sizeof(StateMap));
    StateMap* new_scope;
    if (copy_parent && current_scope_) {
        new_scope = new (mem) StateMap(*current_scope_, unit_.getArena());
        new_scope->parent = current_scope_;
    } else {
        new_scope = new (mem) StateMap(unit_.getArena(), current_scope_);
    }
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
    current_scope_->addVariable(name, state);
}

void NullPointerAnalyzer::setState(const char* name, PointerState state) {
    if (!current_scope_) return;
    current_scope_->setState(name, state);
}

PointerState NullPointerAnalyzer::getState(const char* name) {
    if (!current_scope_) return PS_MAYBE;
    return current_scope_->getState(name);
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
        case NODE_COMPOUND_ASSIGNMENT:
            visitCompoundAssignment(node->as.compound_assignment);
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
        case NODE_RETURN_STMT:
            visitReturnStmt(&node->as.return_stmt);
            break;
        case NODE_EXPRESSION_STMT:
            visit(node->as.expression_stmt.expression);
            break;
        case NODE_UNARY_OP:
            if (node->as.unary_op.op == TOKEN_STAR || node->as.unary_op.op == TOKEN_DOT_ASTERISK) {
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
    pushScope(true); // Functions should probably have a copy of global state

    if (node->params) {
        for (size_t i = 0; i < node->params->length(); ++i) {
            ASTParamDeclNode* param = (*node->params)[i];
            addVariable(param->name, PS_MAYBE);
        }
    }

    visit(node->body);
    popScope();
}

void NullPointerAnalyzer::visitBlock(ASTBlockStmtNode* node) {
    pushScope(true);
    if (node->statements) {
        for (size_t i = 0; i < node->statements->length(); ++i) {
            visit((*node->statements)[i]);
        }
    }
    StateMap* block_state = current_scope_;
    popScope();
    mergeScopes(current_scope_, block_state);
}

void NullPointerAnalyzer::visitVarDecl(ASTVarDeclNode* node) {
    if (node->initializer) {
        visit(node->initializer);
    }

    Symbol* sym = unit_.getSymbolTable().findInAnyScope(node->name);
    if (sym && sym->symbol_type && sym->symbol_type->kind == TYPE_POINTER) {
        PointerState state = PS_UNINIT;
        if (node->initializer) {
            state = getExpressionState(node->initializer);
        }
        addVariable(node->name, state);
    }
}

void NullPointerAnalyzer::visitAssignment(ASTAssignmentNode* node) {
    visit(node->rvalue);

    // Track assignment to identifiers
    if (node->lvalue->type == NODE_IDENTIFIER) {
        const char* name = node->lvalue->as.identifier.name;

        // Use resolved_type from ASTNode if available (justifying its addition)
        Type* target_type = node->lvalue->resolved_type;

        // Fallback to symbol table if TypeChecker hasn't run or resolved it
        if (!target_type) {
            Symbol* sym = unit_.getSymbolTable().findInAnyScope(name);
            if (sym) target_type = sym->symbol_type;
        }

        if (target_type && target_type->kind == TYPE_POINTER) {
            PointerState state = getExpressionState(node->rvalue);
            setState(name, state);
        }
    }
    visit(node->lvalue);
}

void NullPointerAnalyzer::visitCompoundAssignment(ASTCompoundAssignmentNode* node) {
    visit(node->rvalue);

    // For pointers, compound assignment (like p += 1) makes the state MAYBE
    if (node->lvalue->type == NODE_IDENTIFIER) {
        const char* name = node->lvalue->as.identifier.name;
        Type* target_type = node->lvalue->resolved_type;
        if (!target_type) {
            Symbol* sym = unit_.getSymbolTable().findInAnyScope(name);
            if (sym) target_type = sym->symbol_type;
        }

        if (target_type && target_type->kind == TYPE_POINTER) {
            setState(name, PS_MAYBE);
        }
    }
    visit(node->lvalue);
}

void NullPointerAnalyzer::visitIfStmt(ASTIfStmtNode* node) {
    // 2. Analyze condition
    visit(node->condition);

    // 1. Save entry state
    pushScope(true); // Working copy of parent state
    StateMap* entry_state = current_scope_;

    const char* varName = NULL;
    bool isEqual = false;

    // 3. Check if it's a null comparison (e.g., if (p != null))
    if (isNullComparison(node->condition, varName, isEqual)) {
        PointerState originalVarState = getState(varName);

        // 4. Analyze then block with refined state
        pushScope(true); // Branch for then
        if (isEqual) {
            setState(varName, PS_NULL); // p == null
        } else {
            setState(varName, PS_SAFE); // p != null
        }

        visit(node->then_block);
        StateMap* then_branch = current_scope_;
        popScope(); // Exit then branch

        // 5. Analyze else block if present
        if (node->else_block) {
            pushScope(true); // Branch for else
            if (isEqual) {
                setState(varName, PS_SAFE); // else of p == null
            } else {
                setState(varName, PS_NULL); // else of p != null
            }

            visit(node->else_block);
            StateMap* else_branch = current_scope_;
            popScope(); // Exit else branch

            // 6. Merge states from both branches precisely
            // We need to merge variables modified in EITHER branch.
            // For each variable in entry_state:
            for (size_t i = 0; i < entry_state->vars.length(); ++i) {
                const char* name = entry_state->vars[i].name;
                PointerState s_then = then_branch->getState(name);
                PointerState s_else = else_branch->getState(name);
                PointerState merged = mergeStates(s_then, s_else);
                entry_state->setState(name, merged);
            }
        } else {
            // No else block - merge then branch with entry state
            mergeScopes(entry_state, then_branch);
            // And ensure the checked variable is reverted to its original state outside the if
            entry_state->setState(varName, originalVarState);
        }
    } else {
        // Not a null check - analyze normally
        pushScope(true);
        visit(node->then_block);
        StateMap* then_branch = current_scope_;
        popScope();

        if (node->else_block) {
            pushScope(true);
            visit(node->else_block);
            StateMap* else_branch = current_scope_;
            popScope();

            // Merge branches precisely
            for (size_t i = 0; i < entry_state->vars.length(); ++i) {
                const char* name = entry_state->vars[i].name;
                PointerState s_then = then_branch->getState(name);
                PointerState s_else = else_branch->getState(name);
                PointerState merged = mergeStates(s_then, s_else);
                entry_state->setState(name, merged);
            }
        } else {
            mergeScopes(entry_state, then_branch);
        }
    }

    // Restore state, merging modified variables back to parent
    StateMap* final_if_state = current_scope_;
    popScope();
    mergeScopes(current_scope_, final_if_state);
}

void NullPointerAnalyzer::visitWhileStmt(ASTWhileStmtNode* node) {
    // Save entry state
    pushScope(true);

    // Analyze condition
    visit(node->condition);

    const char* varName = NULL;
    bool isEqual = false;

    // Check for null guard (e.g., while (p != null))
    if (isNullComparison(node->condition, varName, isEqual) && !isEqual) {
        // while (p != null)
        // In loop body, p is SAFE
        pushScope(true);
        setState(varName, PS_SAFE);

        visit(node->body);
        StateMap* loop_state = current_scope_;
        popScope();

        // After loop, all modified variables in loop become MAYBE
        for (size_t i = 0; i < loop_state->modified.length(); ++i) {
            setState(loop_state->modified[i], PS_MAYBE);
        }
    } else {
        // Unknown condition - analyze normally
        pushScope(true);
        visit(node->body);
        StateMap* loop_state = current_scope_;
        popScope();

        // All modified variables become MAYBE
        for (size_t i = 0; i < loop_state->modified.length(); ++i) {
            setState(loop_state->modified[i], PS_MAYBE);
        }
    }

    // Merge back to parent scope
    StateMap* final_while_state = current_scope_;
    popScope();
    mergeScopes(current_scope_, final_while_state);
}

void NullPointerAnalyzer::visitForStmt(ASTForStmtNode* node) {
    visit(node->iterable_expr);
    pushScope(true); // For loops also branch
    addVariable(node->item_name, PS_MAYBE);
    if (node->index_name) {
        addVariable(node->index_name, PS_SAFE);
    }
    visit(node->body);
    StateMap* loop_state = current_scope_;
    popScope();

    // Conservative: variables modified in for loop become MAYBE
    for (size_t i = 0; i < loop_state->modified.length(); ++i) {
        setState(loop_state->modified[i], PS_MAYBE);
    }
}

void NullPointerAnalyzer::visitReturnStmt(ASTReturnStmtNode* node) {
    if (node->expression) {
        visit(node->expression);
    }
}

PointerState NullPointerAnalyzer::getExpressionState(ASTNode* expr) {
    if (!expr) return PS_MAYBE;

    if (isNullExpression(expr)) return PS_NULL;

    switch (expr->type) {
        case NODE_NULL_LITERAL:
            return PS_NULL;
        case NODE_INTEGER_LITERAL:
            if (expr->as.integer_literal.value == 0) return PS_NULL;
            return PS_MAYBE;
        case NODE_UNARY_OP:
            if (expr->as.unary_op.op == TOKEN_AMPERSAND) return PS_SAFE;
            return PS_MAYBE;
        case NODE_IDENTIFIER: {
            const char* name = expr->as.identifier.name;
            PointerState state = getState(name);
            return state;
        }
        case NODE_FUNCTION_CALL:
            return PS_MAYBE;
        default:
            return PS_MAYBE;
    }
}

bool NullPointerAnalyzer::isNullExpression(ASTNode* expr) {
    if (!expr) return false;
    if (expr->type == NODE_NULL_LITERAL) return true;
    if (expr->type == NODE_INTEGER_LITERAL && expr->as.integer_literal.value == 0) return true;
    if (expr->type == NODE_IDENTIFIER && strings_equal(expr->as.identifier.name, "NULL")) return true;
    return false;
}

bool NullPointerAnalyzer::isNullComparison(ASTNode* cond, const char*& varName, bool& isEqual) {
    if (!cond) return false;

    // Pattern: p == null, p != null
    if (cond->type == NODE_BINARY_OP) {
        ASTBinaryOpNode* bin = cond->as.binary_op;
        if (bin->op == TOKEN_EQUAL_EQUAL || bin->op == TOKEN_BANG_EQUAL) {
            isEqual = (bin->op == TOKEN_EQUAL_EQUAL);

            if (bin->left->type == NODE_IDENTIFIER && isNullExpression(bin->right)) {
                varName = bin->left->as.identifier.name;
                return true;
            }
            if (bin->right->type == NODE_IDENTIFIER && isNullExpression(bin->left)) {
                varName = bin->right->as.identifier.name;
                return true;
            }
        }
    }

    // Pattern: !p (means p == null)
    if (cond->type == NODE_UNARY_OP && (cond->as.unary_op.op == TOKEN_BANG)) {
        if (cond->as.unary_op.operand->type == NODE_IDENTIFIER) {
            varName = cond->as.unary_op.operand->as.identifier.name;
            isEqual = true;
            return true;
        }
    }

    // Pattern: p (means p != null)
    if (cond->type == NODE_IDENTIFIER) {
        varName = cond->as.identifier.name;
        isEqual = false;
        return true;
    }

    return false;
}

PointerState NullPointerAnalyzer::mergeStates(PointerState s1, PointerState s2) {
    if (s1 == s2) return s1;

    // Precise merges
    if (s1 == PS_SAFE && s2 == PS_SAFE) return PS_SAFE;
    if (s1 == PS_NULL && s2 == PS_NULL) return PS_NULL;
    if (s1 == PS_UNINIT && s2 == PS_UNINIT) return PS_UNINIT;

    // Everything else is conservative
    return PS_MAYBE;
}

void NullPointerAnalyzer::mergeScopes(StateMap* target, StateMap* branch) {
    if (!target || !branch) return;

    for (size_t i = 0; i < branch->modified.length(); ++i) {
        const char* name = branch->modified[i];

        // Only propagate if the variable existed in the target scope
        // (i.e., it wasn't a local variable declared in the branch)
        if (target->hasVariable(name)) {
            PointerState branch_state = branch->getState(name);
            PointerState target_state = target->getState(name);

            PointerState merged = mergeStates(target_state, branch_state);
            target->setState(name, merged);
        }
    }
}

void NullPointerAnalyzer::checkDereference(ASTNode* expr) {
    if (!expr) return;

    PointerState state = getExpressionState(expr);

    switch (state) {
        case PS_NULL:
            unit_.getErrorHandler().report(ERR_NULL_POINTER_DEREFERENCE, expr->loc, ErrorHandler::getMessage(ERR_NULL_POINTER_DEREFERENCE), "Definite null pointer dereference");
            break;
        case PS_UNINIT:
            unit_.getErrorHandler().reportWarning(WARN_UNINITIALIZED_POINTER, expr->loc,
                "Using uninitialized pointer");
            break;
        case PS_MAYBE:
            unit_.getErrorHandler().reportWarning(WARN_POTENTIAL_NULL_DEREFERENCE, expr->loc,
                "Potential null pointer dereference");
            break;
        case PS_SAFE:
            break;
    }
}
