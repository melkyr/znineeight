#include "double_free_analyzer.hpp"
#include "utils.hpp"
#include "type_system.hpp"
#include <new>


AllocationStateMap::AllocationStateMap(ArenaAllocator& arena, AllocationStateMap* p)
    : delta_head(NULL), modified(arena), parent(p), arena_(arena) {
}

void AllocationStateMap::setState(const char* name, const TrackedPointer& state) {
    if (!name) return;

    // Check if already in delta for THIS scope
    StateDelta* curr = delta_head;
    while (curr) {
        if (identifiers_equal(curr->name, name)) {
            curr->state = state;
            curr->state.name = name; // Ensure name is preserved
            return;
        }
        curr = curr->next;
    }

    // Add new delta entry
    void* mem = arena_.alloc(sizeof(StateDelta));
    if (!mem) return;
    StateDelta* new_delta = new (mem) StateDelta(name, state, delta_head);
    new_delta->state.name = name; // Ensure name is preserved in TrackedPointer
    delta_head = new_delta;

    // Mark as modified in this scope
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
}

TrackedPointer* AllocationStateMap::getState(const char* name) {
    // Check deltas in this scope
    StateDelta* curr = delta_head;
    while (curr) {
        if (identifiers_equal(curr->name, name)) {
            return &curr->state;
        }
        curr = curr->next;
    }

    // Recurse to parent
    if (parent) {
        return parent->getState(name);
    }

    return NULL;
}

void AllocationStateMap::addVariable(const char* name, const TrackedPointer& state) {
    setState(name, state);
}

bool AllocationStateMap::hasVariable(const char* name) const {
    StateDelta* curr = delta_head;
    while (curr) {
        if (identifiers_equal(curr->name, name)) {
            return true;
        }
        curr = curr->next;
    }

    if (parent) {
        return parent->hasVariable(name);
    }

    return false;
}

AllocationStateMap* AllocationStateMap::fork() {
    void* mem = arena_.alloc(sizeof(AllocationStateMap));
    if (!mem) return NULL;
    return new (mem) AllocationStateMap(arena_, this);
}

DoubleFreeAnalyzer::DoubleFreeAnalyzer(CompilationUnit& unit)
    : unit_(unit), current_state_(NULL), scopes_(unit.getArena()), deferred_actions_(unit.getArena()), current_scope_depth_(0),
      current_is_errdefer_(false), is_executing_defers_(false) {
    current_defer_loc_.file_id = 0;
    current_defer_loc_.line = 0;
    current_defer_loc_.column = 0;
}

void DoubleFreeAnalyzer::analyze(ASTNode* root) {
    if (!root) return;
    pushScope(); // Global/Function entry scope
    visit(root);
    popScope();
}

void DoubleFreeAnalyzer::pushScope(bool copy_parent) {
    if (copy_parent && current_state_) {
        AllocationStateMap* new_scope = current_state_->fork();
        if (!new_scope) return;
        scopes_.append(new_scope);
        current_state_ = new_scope;
    } else {
        void* mem = unit_.getArena().alloc(sizeof(AllocationStateMap));
        if (!mem) return;
        AllocationStateMap* new_scope = new (mem) AllocationStateMap(unit_.getArena(), current_state_);
        scopes_.append(new_scope);
        current_state_ = new_scope;
    }
}

void DoubleFreeAnalyzer::popScope() {
    if (scopes_.length() > 0) {
        scopes_.pop_back();
        if (scopes_.length() > 0) {
            current_state_ = scopes_.back();
        } else {
            current_state_ = NULL;
        }
    }
}

void DoubleFreeAnalyzer::visit(ASTNode* node) {
    if (!node) return;

    switch (node->type) {
        case NODE_BLOCK_STMT:
            visitBlockStmt(node);
            break;
        case NODE_FN_DECL:
            visitFnDecl(node);
            break;
        case NODE_VAR_DECL:
            visitVarDecl(node);
            break;
        case NODE_ASSIGNMENT:
            visitAssignment(node);
            break;
        case NODE_FUNCTION_CALL:
            visitFunctionCall(node);
            break;
        case NODE_DEFER_STMT:
            visitDeferStmt(node);
            break;
        case NODE_ERRDEFER_STMT:
            visitErrdeferStmt(node);
            break;
        case NODE_IF_STMT:
            visitIfStmt(node);
            break;
        case NODE_WHILE_STMT:
            visitWhileStmt(node);
            break;
        case NODE_FOR_STMT:
            visitForStmt(node);
            break;
        case NODE_RETURN_STMT:
            visitReturnStmt(node);
            break;
        case NODE_BINARY_OP:
            visitBinaryOp(node);
            break;
        case NODE_UNARY_OP:
            visitUnaryOp(node);
            break;
        case NODE_ARRAY_ACCESS:
            visitArrayAccess(node);
            break;
        case NODE_ARRAY_SLICE:
            visitArraySlice(node);
            break;
        case NODE_MEMBER_ACCESS:
            visit(node->as.member_access->base);
            break;
        case NODE_STRUCT_INITIALIZER:
            visit(node->as.struct_initializer->type_expr);
            if (node->as.struct_initializer->fields) {
                for (size_t i = 0; i < node->as.struct_initializer->fields->length(); ++i) {
                    visit((*node->as.struct_initializer->fields)[i]->value);
                }
            }
            break;
        case NODE_COMPOUND_ASSIGNMENT:
            visitCompoundAssignment(node);
            break;
        case NODE_SWITCH_EXPR:
            visitSwitchExpr(node);
            break;
        case NODE_TRY_EXPR:
            visitTryExpr(node);
            break;
        case NODE_CATCH_EXPR:
            visitCatchExpr(node);
            break;
        case NODE_ORELSE_EXPR:
            visitOrelseExpr(node);
            break;
        case NODE_EXPRESSION_STMT:
            visit(node->as.expression_stmt.expression);
            break;
        default:
            // For now, no-op for other node types (literals, identifiers, etc.)
            break;
    }
}

void DoubleFreeAnalyzer::visitBlockStmt(ASTNode* node) {
    ASTBlockStmtNode& block = node->as.block_stmt;
    current_scope_depth_++;
    pushScope(true);

    if (block.statements) {
        for (size_t i = 0; i < block.statements->length(); ++i) {
            visit((*block.statements)[i]);
        }
    }

    // Phase 6: Execute defers for THIS scope (LIFO)
    executeDefers(current_scope_depth_);

    // Phase 5 & 7: Check for leaks at scope exit
    if (current_state_) {
        StateDelta* curr = current_state_->delta_head;
        while (curr) {
            TrackedPointer& tp = curr->state;
            // Variables declared in this scope (matching current_scope_depth_)
            // that are still AS_ALLOCATED or AS_TRANSFERRED are leaked.
            if (tp.scope_depth == current_scope_depth_ && !(tp.flags & TP_FLAG_RETURNED)) {
                if (tp.state == AS_ALLOCATED || tp.state == AS_TRANSFERRED) {
                    reportLeak(tp.name, node->loc, false);
                }
            }
            curr = curr->next;
        }
    }

    AllocationStateMap* block_state = current_state_;
    popScope();
    mergeScopesLinear(current_state_, block_state);

    current_scope_depth_--;
}

void DoubleFreeAnalyzer::visitFnDecl(ASTNode* node) {
    ASTFnDeclNode* fn = node->as.fn_decl;

    // Save current scope and start fresh for function
    AllocationStateMap* old_state = current_state_;
    size_t old_scopes_len = scopes_.length();

    current_state_ = NULL; // Don't inherit from parent scope for functions
    pushScope();

    deferred_actions_.clear();
    current_scope_depth_ = 0;
    if (fn->body) {
        visit(fn->body);
    }

    while (scopes_.length() > old_scopes_len) {
        popScope();
    }

    current_state_ = old_state;
}

void DoubleFreeAnalyzer::visitVarDecl(ASTNode* node) {
    ASTVarDeclNode* var = node->as.var_decl;
    // Phase 4: Track all pointer variables
    if (node->resolved_type && node->resolved_type->kind == TYPE_POINTER) {
        TrackedPointer tp;
        tp.name = var->name;
        tp.scope_depth = current_scope_depth_;
        tp.flags = TP_FLAG_NONE;
        if (var->initializer && isAllocationCall(var->initializer)) {
            tp.state = AS_ALLOCATED;
            tp.alloc_loc = var->initializer->loc;
        } else {
            tp.state = AS_UNINITIALIZED;
        }
        if (current_state_) {
            current_state_->addVariable(var->name, tp);
        }
    }

    if (var->initializer) {
        visit(var->initializer);
    }
}

void DoubleFreeAnalyzer::visitAssignment(ASTNode* node) {
    if (!current_state_) return;
    ASTAssignmentNode* assign = node->as.assignment;
    visit(assign->rvalue);

    const char* var_name = extractVariableName(assign->lvalue);
    if (var_name) {
        TrackedPointer* tp = findTrackedPointer(var_name);

        // Phase 7: Check for leak BEFORE updating state
        if (tp && tp->state == AS_ALLOCATED && isChangingPointerValue(assign->rvalue)) {
            reportLeak(var_name, node->loc, true);
        }

        // Update state based on new value
        if (isAllocationCall(assign->rvalue)) {
            if (tp) {
                TrackedPointer next_tp = *tp;
                next_tp.state = AS_ALLOCATED;
                next_tp.flags &= ~TP_FLAG_RETURNED; // Reset returned flag if reassigned to new allocation
                next_tp.alloc_loc = assign->rvalue->loc; // Update allocation site
                current_state_->setState(var_name, next_tp);
            } else {
                trackAllocation(var_name, assign->rvalue->loc);
            }
        } else if (isChangingPointerValue(assign->rvalue)) {
             if (tp) {
                TrackedPointer next_tp = *tp;
                next_tp.state = AS_UNKNOWN; // State becomes unknown after general reassignment
                current_state_->setState(var_name, next_tp);
             }
        }
    }
}

void DoubleFreeAnalyzer::visitFunctionCall(ASTNode* node) {
    if (!current_state_) return;
    ASTFunctionCallNode* call = node->as.function_call;
    if (isArenaFreeCall(call)) {
        if (call->args && call->args->length() > 0) {
            const char* var_name = extractVariableName((*call->args)[0]);
            if (var_name) {
                TrackedPointer* tp = findTrackedPointer(var_name);
                if (tp) {
                    switch (tp->state) {
                        case AS_FREED:
                            reportDoubleFree(var_name, node->loc);
                            break;
                        case AS_ALLOCATED: {
                            TrackedPointer next_tp = *tp;
                            next_tp.state = AS_FREED;
                            next_tp.first_free_loc = node->loc; // Record where it was first freed
                            if (is_executing_defers_) {
                                next_tp.freed_via_defer = true;
                                next_tp.defer_loc = current_defer_loc_;
                                next_tp.is_errdefer = current_is_errdefer_;
                            }
                            current_state_->setState(var_name, next_tp);
                            break;
                        }
                        case AS_UNINITIALIZED:
                            reportUninitializedFree(var_name, node->loc);
                            break;
                        case AS_TRANSFERRED:
                            // Don't report double free - ownership might have been transferred
                            break;
                        default:
                            break;
                    }
                }
            }
        }
    } else if (isOwnershipTransferCall(call)) {
        // Check each argument for tracked pointers
        if (call->args) {
            for (size_t i = 0; i < call->args->length(); ++i) {
                const char* var_name = extractVariableName((*call->args)[i]);
                if (var_name) {
                    TrackedPointer* tp = findTrackedPointer(var_name);
                    if (tp && (tp->state == AS_ALLOCATED || tp->state == AS_UNINITIALIZED)) {
                        TrackedPointer next_tp = *tp;
                        next_tp.state = AS_TRANSFERRED;
                        next_tp.transfer_loc = node->loc;
                        current_state_->setState(var_name, next_tp);
                    }
                }
            }
        }
    }

    // Visit arguments
    if (call->args) {
        for (size_t i = 0; i < call->args->length(); ++i) {
            visit((*call->args)[i]);
        }
    }
}

void DoubleFreeAnalyzer::visitDeferStmt(ASTNode* node) {
    ASTDeferStmtNode& defer = node->as.defer_stmt;
    if (defer.statement) {
        DeferredAction action;
        action.statement = defer.statement;
        action.scope_depth = current_scope_depth_;
        action.defer_loc = node->loc;
        action.is_errdefer = false;
        deferred_actions_.append(action);
    }
}

void DoubleFreeAnalyzer::visitErrdeferStmt(ASTNode* node) {
    ASTErrDeferStmtNode& errdefer = node->as.errdefer_stmt;
    if (errdefer.statement) {
        DeferredAction action;
        action.statement = errdefer.statement;
        action.scope_depth = current_scope_depth_;
        action.defer_loc = node->loc;
        action.is_errdefer = true;
        deferred_actions_.append(action);
    }
}

void DoubleFreeAnalyzer::visitIfStmt(ASTNode* node) {
    ASTIfStmtNode* if_stmt = node->as.if_stmt;
    visit(if_stmt->condition);

    // Save entry state
    pushScope(true);
    AllocationStateMap* entry_state = current_state_;

    // Analyze then branch
    pushScope(true);
    if (if_stmt->then_block) visit(if_stmt->then_block);
    AllocationStateMap* then_branch = current_state_;
    popScope();

    // Analyze else branch
    if (if_stmt->else_block) {
        pushScope(true);
        visit(if_stmt->else_block);
        AllocationStateMap* else_branch = current_state_;
        popScope();

        // Merge both branches into entry_state
        if (entry_state && then_branch && else_branch) {
            // Variables to merge are those modified in either branch
            DynamicArray<const char*> to_merge(unit_.getArena());

            for (size_t i = 0; i < then_branch->modified.length(); ++i) {
                to_merge.append(then_branch->modified[i]);
            }
            for (size_t i = 0; i < else_branch->modified.length(); ++i) {
                const char* name = else_branch->modified[i];
                bool already = false;
                for (size_t j = 0; j < to_merge.length(); ++j) {
                    if (identifiers_equal(to_merge[j], name)) {
                        already = true;
                        break;
                    }
                }
                if (!already) to_merge.append(name);
            }

            for (size_t i = 0; i < to_merge.length(); ++i) {
                const char* name = to_merge[i];
                // Only merge variables that existed before the if statement
                if (entry_state->hasVariable(name)) {
                    TrackedPointer* s_then = then_branch->getState(name);
                    TrackedPointer* s_else = else_branch->getState(name);
                    if (s_then && s_else) {
                        TrackedPointer merged = mergeTrackedPointers(*s_then, *s_else);
                        entry_state->setState(name, merged);
                    }
                }
            }
        }
    } else if (entry_state && then_branch) {
        // No else block - merge then branch with entry state
        mergeScopesAlternative(entry_state, then_branch);
    }

    // Restore state, merging modified variables back to parent
    AllocationStateMap* final_if_state = current_state_;
    popScope();
    mergeScopesLinear(current_state_, final_if_state);
}

void DoubleFreeAnalyzer::visitWhileStmt(ASTNode* node) {
    ASTWhileStmtNode& while_stmt = node->as.while_stmt;
    visit(while_stmt.condition);

    // Save entry state
    pushScope(true);

    // Analyze body once
    pushScope(true);
    if (while_stmt.body) visit(while_stmt.body);
    AllocationStateMap* loop_state = current_state_;
    popScope();

    // Conservative: all variables modified in loop become AS_UNKNOWN
    if (current_state_) {
        for (size_t i = 0; i < loop_state->modified.length(); ++i) {
            const char* name = loop_state->modified[i];
            TrackedPointer* tp = findTrackedPointer(name);
            if (tp) {
                TrackedPointer next_tp = *tp;
                next_tp.state = AS_UNKNOWN;
                current_state_->setState(name, next_tp);
            }
        }
    }

    AllocationStateMap* final_while_state = current_state_;
    popScope();
    mergeScopesLinear(current_state_, final_while_state);
}

void DoubleFreeAnalyzer::visitForStmt(ASTNode* node) {
    ASTForStmtNode* for_stmt = node->as.for_stmt;
    if (for_stmt->iterable_expr) visit(for_stmt->iterable_expr);

    pushScope(true);

    // Analyze body once
    pushScope(true);
    if (for_stmt->body) visit(for_stmt->body);
    AllocationStateMap* loop_state = current_state_;
    popScope();

    // Conservative: all variables modified in loop become AS_UNKNOWN
    if (current_state_) {
        for (size_t i = 0; i < loop_state->modified.length(); ++i) {
            const char* name = loop_state->modified[i];
            TrackedPointer* tp = findTrackedPointer(name);
            if (tp) {
                TrackedPointer next_tp = *tp;
                next_tp.state = AS_UNKNOWN;
                current_state_->setState(name, next_tp);
            }
        }
    }

    AllocationStateMap* final_for_state = current_state_;
    popScope();
    mergeScopesLinear(current_state_, final_for_state);
}

void DoubleFreeAnalyzer::visitReturnStmt(ASTNode* node) {
    // Phase 6: Execute all defers for the entire function (depth_limit = 1)
    // We execute them all because return exits all nested scopes.
    executeDefers(1);

    ASTReturnStmtNode& ret = node->as.return_stmt;
    if (ret.expression) {
        // Phase 7: Exempt returned pointers from leak checks
        const char* var_name = extractVariableName(ret.expression);
        if (var_name) {
            TrackedPointer* tp = findTrackedPointer(var_name);
            if (tp && tp->state == AS_ALLOCATED) {
                TrackedPointer next_tp = *tp;
                next_tp.flags |= TP_FLAG_RETURNED;
                if (current_state_) {
                    current_state_->setState(var_name, next_tp);
                }
            }
        }
        visit(ret.expression);
    }
}

void DoubleFreeAnalyzer::visitBinaryOp(ASTNode* node) {
    ASTBinaryOpNode* bin = node->as.binary_op;
    visit(bin->left);
    visit(bin->right);
}

void DoubleFreeAnalyzer::visitUnaryOp(ASTNode* node) {
    ASTUnaryOpNode& un = node->as.unary_op;
    visit(un.operand);
}

void DoubleFreeAnalyzer::visitArrayAccess(ASTNode* node) {
    ASTArrayAccessNode* access = node->as.array_access;
    visit(access->array);
    visit(access->index);
}

void DoubleFreeAnalyzer::visitArraySlice(ASTNode* node) {
    ASTArraySliceNode* slice = node->as.array_slice;
    visit(slice->array);
    if (slice->start) visit(slice->start);
    if (slice->end) visit(slice->end);
}

void DoubleFreeAnalyzer::visitCompoundAssignment(ASTNode* node) {
    ASTCompoundAssignmentNode* assign = node->as.compound_assignment;
    visit(assign->rvalue);

    // We should also check for leaks if the lvalue is an allocated pointer
    const char* var_name = extractVariableName(assign->lvalue);
    if (var_name) {
        TrackedPointer* tp = findTrackedPointer(var_name);
        if (tp && tp->state == AS_ALLOCATED) {
            // Compound assignment like p += 1 changes the pointer value.
            reportLeak(var_name, node->loc, true);

            TrackedPointer next_tp = *tp;
            next_tp.state = AS_UNKNOWN;
            if (current_state_) {
                current_state_->setState(var_name, next_tp);
            }
        }
    }

    visit(assign->lvalue);
}

void DoubleFreeAnalyzer::visitSwitchExpr(ASTNode* node) {
    ASTSwitchExprNode* sw = node->as.switch_expr;
    visit(sw->expression);

    if (sw->prongs && sw->prongs->length() > 0) {
        pushScope(true);
        AllocationStateMap* entry_state = current_state_;

        DynamicArray<AllocationStateMap*> prong_states(unit_.getArena());

        for (size_t i = 0; i < sw->prongs->length(); ++i) {
            ASTSwitchProngNode* prong = (*sw->prongs)[i];

            pushScope(true);
            if (prong->cases) {
                for (size_t j = 0; j < prong->cases->length(); ++j) {
                    visit((*prong->cases)[j]);
                }
            }
            visit(prong->body);
            prong_states.append(current_state_);
            popScope();
        }

        // Merge all prong states
        DynamicArray<const char*> to_merge(unit_.getArena());
        for (size_t i = 0; i < prong_states.length(); ++i) {
            for (size_t j = 0; j < prong_states[i]->modified.length(); ++j) {
                const char* name = prong_states[i]->modified[j];
                bool already = false;
                for (size_t k = 0; k < to_merge.length(); ++k) {
                    if (identifiers_equal(to_merge[k], name)) {
                        already = true;
                        break;
                    }
                }
                if (!already) to_merge.append(name);
            }
        }

        for (size_t i = 0; i < to_merge.length(); ++i) {
            const char* name = to_merge[i];
            if (entry_state->hasVariable(name)) {
                TrackedPointer* first_prong_tp = prong_states[0]->getState(name);

                TrackedPointer merged;
                if (first_prong_tp) {
                    merged = *first_prong_tp;
                } else {
                    // Not modified in first prong, take from entry state
                    TrackedPointer* entry_tp = entry_state->getState(name);
                    if (entry_tp) merged = *entry_tp;
                    else continue; // Should not happen if hasVariable was true
                }

                for (size_t j = 1; j < prong_states.length(); ++j) {
                    TrackedPointer* next_prong_tp = prong_states[j]->getState(name);
                    if (next_prong_tp) {
                        merged = mergeTrackedPointers(merged, *next_prong_tp);
                    } else {
                        // If one prong doesn't have it, it means it's unchanged from entry state
                        TrackedPointer* entry_tp = entry_state->getState(name);
                        if (entry_tp) {
                            merged = mergeTrackedPointers(merged, *entry_tp);
                        }
                    }
                }
                entry_state->setState(name, merged);
            }
        }

        AllocationStateMap* final_switch_state = current_state_;
        popScope();
        mergeScopesLinear(current_state_, final_switch_state);
    }
}

void DoubleFreeAnalyzer::visitTryExpr(ASTNode* node) {
    visit(node->as.try_expr.expression);

    // Path-awareness for 'try':
    // 'try' introduces a potential early exit path. On that path, 'errdefer's
    // are executed. On the success path, they are not.
    // Since we don't track the exact error path, we transition all currently
    // ALLOCATED pointers to UNKNOWN to conservatively reflect this uncertainty.
    // We only care about pointers that exist in the parent scope (not locals of this try)
    if (current_state_) {
        // Since we don't have a 'vars' array, we have a problem.
        // We could iterate over all deltas in all scopes...
        // Or we just accept that we can only mark currently 'modified' ones?
        // No, that's not enough.

        // Let's iterate up the scope chain.
        AllocationStateMap* s = current_state_;
        while (s) {
            StateDelta* curr = s->delta_head;
            while (curr) {
                if (curr->state.state == AS_ALLOCATED) {
                    TrackedPointer next_tp = curr->state;
                    next_tp.state = AS_UNKNOWN;
                    current_state_->setState(curr->name, next_tp);
                }
                curr = curr->next;
            }
            s = s->parent;
        }
    }
}

void DoubleFreeAnalyzer::visitCatchExpr(ASTNode* node) {
    ASTCatchExprNode* catch_expr = node->as.catch_expr;

    // Save entry state
    pushScope(true);
    AllocationStateMap* entry_state = current_state_;

    // Main path (payload)
    pushScope(true);
    visit(catch_expr->payload);
    AllocationStateMap* main_branch = current_state_;
    popScope();

    // Catch path (else_expr)
    pushScope(true);
    visit(catch_expr->else_expr);
    AllocationStateMap* catch_branch = current_state_;
    popScope();

    // Merge both branches into entry_state
    if (entry_state && main_branch && catch_branch) {
        DynamicArray<const char*> to_merge(unit_.getArena());
        for (size_t i = 0; i < main_branch->modified.length(); ++i) to_merge.append(main_branch->modified[i]);
        for (size_t i = 0; i < catch_branch->modified.length(); ++i) {
            const char* name = catch_branch->modified[i];
            bool already = false;
            for (size_t j = 0; j < to_merge.length(); ++j) if (identifiers_equal(to_merge[j], name)) { already = true; break; }
            if (!already) to_merge.append(name);
        }

        for (size_t i = 0; i < to_merge.length(); ++i) {
            const char* name = to_merge[i];
            TrackedPointer* s_main = main_branch->getState(name);
            TrackedPointer* s_catch = catch_branch->getState(name);
            if (s_main && s_catch) {
                TrackedPointer merged = mergeTrackedPointers(*s_main, *s_catch);
                entry_state->setState(name, merged);
            }
        }
    }

    AllocationStateMap* final_catch_state = current_state_;
    popScope();
    mergeScopesLinear(current_state_, final_catch_state);
}

void DoubleFreeAnalyzer::visitOrelseExpr(ASTNode* node) {
    ASTOrelseExprNode* orelse = node->as.orelse_expr;

    // Save entry state
    pushScope(true);
    AllocationStateMap* entry_state = current_state_;

    // Main path (payload)
    pushScope(true);
    visit(orelse->payload);
    AllocationStateMap* main_branch = current_state_;
    popScope();

    // Orelse path (else_expr)
    pushScope(true);
    visit(orelse->else_expr);
    AllocationStateMap* orelse_branch = current_state_;
    popScope();

    // Merge both branches into entry_state
    if (entry_state && main_branch && orelse_branch) {
        DynamicArray<const char*> to_merge(unit_.getArena());
        for (size_t i = 0; i < main_branch->modified.length(); ++i) to_merge.append(main_branch->modified[i]);
        for (size_t i = 0; i < orelse_branch->modified.length(); ++i) {
            const char* name = orelse_branch->modified[i];
            bool already = false;
            for (size_t j = 0; j < to_merge.length(); ++j) if (identifiers_equal(to_merge[j], name)) { already = true; break; }
            if (!already) to_merge.append(name);
        }

        for (size_t i = 0; i < to_merge.length(); ++i) {
            const char* name = to_merge[i];
            TrackedPointer* s_main = main_branch->getState(name);
            TrackedPointer* s_orelse = orelse_branch->getState(name);
            if (s_main && s_orelse) {
                TrackedPointer merged = mergeTrackedPointers(*s_main, *s_orelse);
                entry_state->setState(name, merged);
            }
        }
    }

    AllocationStateMap* final_orelse_state = current_state_;
    popScope();
    mergeScopesLinear(current_state_, final_orelse_state);
}

TrackedPointer DoubleFreeAnalyzer::mergeTrackedPointers(const TrackedPointer& a, const TrackedPointer& b) {
    if (a.state == b.state) return a;

    TrackedPointer result = a;
    result.state = mergeAllocationStates(a.state, b.state);

    // If state is unknown, clear locations to be safe
    if (result.state == AS_UNKNOWN) {
        result.alloc_loc.line = 0;
        result.first_free_loc.line = 0;
        result.transfer_loc.line = 0;
    }

    return result;
}

void DoubleFreeAnalyzer::mergeScopesAlternative(AllocationStateMap* target, AllocationStateMap* branch) {
    if (!target || !branch) return;

    for (size_t i = 0; i < branch->modified.length(); ++i) {
        const char* name = branch->modified[i];
        if (!name) continue;

        if (target->hasVariable(name)) {
            TrackedPointer* branch_tp = branch->getState(name);
            TrackedPointer* target_tp = target->getState(name);

            if (branch_tp && target_tp) {
                TrackedPointer merged = mergeTrackedPointers(*target_tp, *branch_tp);
                target->setState(name, merged);
            }
        }
    }
}

void DoubleFreeAnalyzer::mergeScopesLinear(AllocationStateMap* target, AllocationStateMap* source) {
    if (!target || !source) return;

    for (size_t i = 0; i < source->modified.length(); ++i) {
        const char* name = source->modified[i];
        if (!name) continue;

        if (target->hasVariable(name)) {
            TrackedPointer* source_tp = source->getState(name);
            if (source_tp) {
                target->setState(name, *source_tp);
            }
        }
    }
}

AllocationState DoubleFreeAnalyzer::mergeAllocationStates(AllocationState s1, AllocationState s2) {
    if (s1 == s2) return s1;

    // Conservative merge: if any path differs from another, we lose certainty.
    // Especially important: ALLOCATED + (ANYTHING ELSE) = UNKNOWN
    // to ensure we don't miss potential leaks or double frees.
    return AS_UNKNOWN;
}

void DoubleFreeAnalyzer::executeDefers(int depth_limit) {
    bool old_is_executing = is_executing_defers_;
    is_executing_defers_ = true;

    while (deferred_actions_.length() > 0 && deferred_actions_.back().scope_depth >= depth_limit) {
        DeferredAction action = deferred_actions_.back();
        deferred_actions_.pop_back();

        current_defer_loc_ = action.defer_loc;
        current_is_errdefer_ = action.is_errdefer;

        visit(action.statement);
    }

    is_executing_defers_ = old_is_executing;
}

bool DoubleFreeAnalyzer::isArenaAllocCall(ASTNode* node) {
    return isAllocationCall(node);
}

bool DoubleFreeAnalyzer::isAllocationCall(ASTNode* node) {
    if (!node) return false;
    if (node->type == NODE_FUNCTION_CALL) {
        ASTFunctionCallNode* call = node->as.function_call;
        if (call->callee->type == NODE_IDENTIFIER) {
            const char* name = call->callee->as.identifier.name;
            return strings_equal(name, "arena_alloc") || strings_equal(name, "arena_alloc_default");
        }
    } else if (node->type == NODE_TRY_EXPR) {
        return isAllocationCall(node->as.try_expr.expression);
    } else if (node->type == NODE_CATCH_EXPR) {
        return isAllocationCall(node->as.catch_expr->payload) || isAllocationCall(node->as.catch_expr->else_expr);
    } else if (node->type == NODE_ORELSE_EXPR) {
        return isAllocationCall(node->as.orelse_expr->payload) || isAllocationCall(node->as.orelse_expr->else_expr);
    } else if (node->type == NODE_BINARY_OP) {
        return isAllocationCall(node->as.binary_op->left) || isAllocationCall(node->as.binary_op->right);
    } else if (node->type == NODE_PTR_CAST) {
        return isAllocationCall(node->as.ptr_cast->expr);
    }
    return false;
}

bool DoubleFreeAnalyzer::isArenaFreeCall(ASTFunctionCallNode* call) {
    if (!call || call->callee->type != NODE_IDENTIFIER) return false;
    return strings_equal(call->callee->as.identifier.name, "arena_free");
}

bool DoubleFreeAnalyzer::isOwnershipTransferCall(ASTFunctionCallNode* call) {
    // For bootstrap: assume any function call that isn't arena_free
    // and takes a pointer argument could be a transfer.
    // In a more advanced analyzer, we would check the function signature
    // or look for specific ownership-transferring patterns.
    return true;
}

bool DoubleFreeAnalyzer::isChangingPointerValue(ASTNode* rvalue) {
    if (!rvalue) return true;

    if (rvalue->type == NODE_NULL_LITERAL) return true;
    if (rvalue->type == NODE_UNARY_OP && rvalue->as.unary_op.op == TOKEN_AMPERSAND) return true;
    if (rvalue->type == NODE_FUNCTION_CALL && !isAllocationCall(rvalue)) return true;
    if (rvalue->type == NODE_IDENTIFIER) return true; // Reassigning from another variable also loses track
    if (rvalue->type == NODE_PTR_CAST) return isChangingPointerValue(rvalue->as.ptr_cast->expr);
    if (isAllocationCall(rvalue)) return true; // Reassigning to a new allocation also loses track of old one

    return false;
}

void DoubleFreeAnalyzer::trackAllocation(const char* name, SourceLocation loc) {
    TrackedPointer tp;
    tp.name = name;
    tp.state = AS_ALLOCATED;
    tp.scope_depth = current_scope_depth_;
    tp.flags = TP_FLAG_NONE;
    tp.alloc_loc = loc;
    if (current_state_) {
        current_state_->addVariable(name, tp);
    }
}

TrackedPointer* DoubleFreeAnalyzer::findTrackedPointer(const char* name) {
    if (!current_state_) return NULL;
    return current_state_->getState(name);
}

const char* DoubleFreeAnalyzer::extractVariableName(ASTNode* node) {
    if (!node) return NULL;
    if (node->type == NODE_IDENTIFIER) {
        return node->as.identifier.name;
    }
    return NULL;
}

void DoubleFreeAnalyzer::reportDoubleFree(const char* name, SourceLocation loc) {
    if (!name) return;
    TrackedPointer* tp = findTrackedPointer(name);
    char* msg = (char*)unit_.getArena().alloc(512);
    if (!msg) return; // OOM, nothing we can do here

    char* p = msg;
    size_t rem = 512;
    safe_append(p, rem, "Double free of pointer '");
    safe_append(p, rem, name);
    safe_append(p, rem, "'");

    if (tp && tp->alloc_loc.line > 0) {
        const SourceFile* file = unit_.getSourceManager().getFile(tp->alloc_loc.file_id);
        safe_append(p, rem, " (allocated at ");
        if (file) safe_append(p, rem, file->filename);
        else safe_append(p, rem, "unknown");
        safe_append(p, rem, ":");
        char buf[16];
        plat_i64_to_string(tp->alloc_loc.line, buf, sizeof(buf));
        safe_append(p, rem, buf);
        safe_append(p, rem, ":");
        plat_i64_to_string(tp->alloc_loc.column, buf, sizeof(buf));
        safe_append(p, rem, buf);
        safe_append(p, rem, ")");
    }

    if (tp && tp->first_free_loc.line > 0) {
        if (tp->freed_via_defer) {
            safe_append(p, rem, " - first freed via ");
            safe_append(p, rem, tp->is_errdefer ? "errdefer" : "defer");
            if (tp->defer_loc.line > 0) {
                const SourceFile* file = unit_.getSourceManager().getFile(tp->defer_loc.file_id);
                safe_append(p, rem, " at ");
                if (file) safe_append(p, rem, file->filename);
                else safe_append(p, rem, "unknown");
                safe_append(p, rem, ":");
                char buf[16];
                plat_i64_to_string(tp->defer_loc.line, buf, sizeof(buf));
                safe_append(p, rem, buf);
                safe_append(p, rem, ":");
                plat_i64_to_string(tp->defer_loc.column, buf, sizeof(buf));
                safe_append(p, rem, buf);
            }
            safe_append(p, rem, " (deferred free at ");
        } else {
            safe_append(p, rem, " - first freed at ");
        }

        const SourceFile* file = unit_.getSourceManager().getFile(tp->first_free_loc.file_id);
        if (file) safe_append(p, rem, file->filename);
        else safe_append(p, rem, "unknown");
        safe_append(p, rem, ":");
        char buf[16];
        plat_i64_to_string(tp->first_free_loc.line, buf, sizeof(buf));
        safe_append(p, rem, buf);
        safe_append(p, rem, ":");
        plat_i64_to_string(tp->first_free_loc.column, buf, sizeof(buf));
        safe_append(p, rem, buf);

        if (tp->freed_via_defer) {
            safe_append(p, rem, ")");
        }
    }

    unit_.getErrorHandler().report(ERR_DOUBLE_FREE, loc, msg, unit_.getArena());
}

void DoubleFreeAnalyzer::reportLeak(const char* name, SourceLocation loc, bool is_reassignment) {
    if (!name) return;
    TrackedPointer* tp = findTrackedPointer(name);
    char* msg = (char*)unit_.getArena().alloc(512);
    if (!msg) return;

    char* p = msg;
    size_t rem = 512;

    WarningCode code = WARN_MEMORY_LEAK;

    if (tp && tp->state == AS_TRANSFERRED) {
        code = WARN_TRANSFERRED_MEMORY;
        safe_append(p, rem, "Pointer '");
        safe_append(p, rem, name);
        safe_append(p, rem, "' transferred");
        if (tp->transfer_loc.line > 0) {
            const SourceFile* file = unit_.getSourceManager().getFile(tp->transfer_loc.file_id);
            safe_append(p, rem, " (at ");
            if (file) safe_append(p, rem, file->filename);
            else safe_append(p, rem, "unknown");
            safe_append(p, rem, ":");
            char buf[16];
            plat_i64_to_string(tp->transfer_loc.line, buf, sizeof(buf));
            safe_append(p, rem, buf);
            safe_append(p, rem, ":");
            plat_i64_to_string(tp->transfer_loc.column, buf, sizeof(buf));
            safe_append(p, rem, buf);
            safe_append(p, rem, ")");
        }
        safe_append(p, rem, " - receiver responsible for freeing");
    } else {
        if (is_reassignment) {
            safe_append(p, rem, "Memory leak: reassigning allocated pointer '");
        } else {
            safe_append(p, rem, "Memory leak: pointer '");
        }
        safe_append(p, rem, name);
        if (is_reassignment) {
            safe_append(p, rem, "'");
        } else {
            safe_append(p, rem, "' not freed");
        }
    }

    if (tp && tp->alloc_loc.line > 0) {
        const SourceFile* file = unit_.getSourceManager().getFile(tp->alloc_loc.file_id);
        safe_append(p, rem, " (allocated at ");
        if (file) safe_append(p, rem, file->filename);
        else safe_append(p, rem, "unknown");
        safe_append(p, rem, ":");
        char buf[16];
        plat_i64_to_string(tp->alloc_loc.line, buf, sizeof(buf));
        safe_append(p, rem, buf);
        safe_append(p, rem, ":");
        plat_i64_to_string(tp->alloc_loc.column, buf, sizeof(buf));
        safe_append(p, rem, buf);
        safe_append(p, rem, ")");
    }

    unit_.getErrorHandler().reportWarning(code, loc, msg, unit_.getArena());
}

void DoubleFreeAnalyzer::reportUninitializedFree(const char* name, SourceLocation loc) {
    if (!name) return;
    char* msg = (char*)unit_.getArena().alloc(256);
    if (!msg) return;

    char* p = msg;
    size_t rem = 256;
    safe_append(p, rem, "Freeing uninitialized pointer '");
    safe_append(p, rem, name);
    safe_append(p, rem, "'");
    unit_.getErrorHandler().reportWarning(WARN_FREE_UNALLOCATED, loc, msg, unit_.getArena());
}
