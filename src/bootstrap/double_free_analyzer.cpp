#include "double_free_analyzer.hpp"
#include "utils.hpp"
#include "type_system.hpp"

DoubleFreeAnalyzer::DoubleFreeAnalyzer(CompilationUnit& unit)
    : unit_(unit), tracked_pointers_(unit.getArena()), deferred_actions_(unit.getArena()), current_scope_depth_(0),
      current_is_errdefer_(false), is_executing_defers_(false) {
    current_defer_loc_.file_id = 0;
    current_defer_loc_.line = 0;
    current_defer_loc_.column = 0;
}

void DoubleFreeAnalyzer::analyze(ASTNode* root) {
    if (!root) return;
    visit(root);
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
    if (block.statements) {
        for (size_t i = 0; i < block.statements->length(); ++i) {
            visit((*block.statements)[i]);
        }
    }

    // Phase 6: Execute defers for THIS scope (LIFO)
    executeDefers(current_scope_depth_);

    // Phase 5 & 7: Check for leaks at scope exit
    size_t i = 0;
    while (i < tracked_pointers_.length()) {
        if (tracked_pointers_[i].scope_depth == current_scope_depth_) {
            if (!(tracked_pointers_[i].flags & TP_FLAG_RETURNED)) {
                if (tracked_pointers_[i].state == AS_ALLOCATED) {
                    reportLeak(tracked_pointers_[i].name, node->loc, false);
                } else if (tracked_pointers_[i].state == AS_TRANSFERRED) {
                    reportLeak(tracked_pointers_[i].name, node->loc, false);
                }
            }
            // Remove by swapping with last
            tracked_pointers_[i] = tracked_pointers_[tracked_pointers_.length() - 1];
            tracked_pointers_.pop_back();
            // Don't increment i, check the new element at i
        } else {
            i++;
        }
    }

    current_scope_depth_--;
}

void DoubleFreeAnalyzer::visitFnDecl(ASTNode* node) {
    ASTFnDeclNode* fn = node->as.fn_decl;
    // Phase 3: Clear tracked pointers for each function
    tracked_pointers_.clear();
    deferred_actions_.clear();
    current_scope_depth_ = 0;
    if (fn->body) {
        visit(fn->body);
    }
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
        tracked_pointers_.append(tp);
    }

    if (var->initializer) {
        visit(var->initializer);
    }
}

void DoubleFreeAnalyzer::visitAssignment(ASTNode* node) {
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
                tp->state = AS_ALLOCATED;
                tp->flags &= ~TP_FLAG_RETURNED; // Reset returned flag if reassigned to new allocation
                tp->alloc_loc = assign->rvalue->loc; // Update allocation site
            } else {
                trackAllocation(var_name, assign->rvalue->loc);
            }
        } else if (isChangingPointerValue(assign->rvalue)) {
             if (tp) {
                tp->state = AS_UNKNOWN; // State becomes unknown after general reassignment
             }
        }
    }
}

void DoubleFreeAnalyzer::visitFunctionCall(ASTNode* node) {
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
                        case AS_ALLOCATED:
                            tp->state = AS_FREED;
                            tp->first_free_loc = node->loc; // Record where it was first freed
                            if (is_executing_defers_) {
                                tp->freed_via_defer = true;
                                tp->defer_loc = current_defer_loc_;
                                tp->is_errdefer = current_is_errdefer_;
                            }
                            break;
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
                        tp->state = AS_TRANSFERRED;
                        tp->transfer_loc = node->loc;
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
    if (if_stmt->then_block) visit(if_stmt->then_block);
    if (if_stmt->else_block) visit(if_stmt->else_block);
}

void DoubleFreeAnalyzer::visitWhileStmt(ASTNode* node) {
    ASTWhileStmtNode& while_stmt = node->as.while_stmt;
    visit(while_stmt.condition);
    if (while_stmt.body) visit(while_stmt.body);
}

void DoubleFreeAnalyzer::visitForStmt(ASTNode* node) {
    ASTForStmtNode* for_stmt = node->as.for_stmt;
    // For loop components
    if (for_stmt->iterable_expr) visit(for_stmt->iterable_expr);
    if (for_stmt->body) visit(for_stmt->body);
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
                tp->flags |= TP_FLAG_RETURNED;
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
            tp->state = AS_UNKNOWN;
        }
    }

    visit(assign->lvalue);
}

void DoubleFreeAnalyzer::visitSwitchExpr(ASTNode* node) {
    ASTSwitchExprNode* sw = node->as.switch_expr;
    visit(sw->expression);
    if (sw->prongs) {
        for (size_t i = 0; i < sw->prongs->length(); ++i) {
            ASTSwitchProngNode* prong = (*sw->prongs)[i];
            if (prong->cases) {
                for (size_t j = 0; j < prong->cases->length(); ++j) {
                    visit((*prong->cases)[j]);
                }
            }
            visit(prong->body);
        }
    }
}

void DoubleFreeAnalyzer::visitTryExpr(ASTNode* node) {
    visit(node->as.try_expr.expression);
}

void DoubleFreeAnalyzer::visitCatchExpr(ASTNode* node) {
    ASTCatchExprNode* catch_expr = node->as.catch_expr;
    visit(catch_expr->payload);
    visit(catch_expr->else_expr);
}

void DoubleFreeAnalyzer::visitOrelseExpr(ASTNode* node) {
    ASTOrelseExprNode* orelse = node->as.orelse_expr;
    visit(orelse->payload);
    visit(orelse->else_expr);
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
            return strings_equal(call->callee->as.identifier.name, "arena_alloc");
        }
    } else if (node->type == NODE_TRY_EXPR) {
        return isAllocationCall(node->as.try_expr.expression);
    } else if (node->type == NODE_CATCH_EXPR) {
        return isAllocationCall(node->as.catch_expr->payload) || isAllocationCall(node->as.catch_expr->else_expr);
    } else if (node->type == NODE_ORELSE_EXPR) {
        return isAllocationCall(node->as.orelse_expr->payload) || isAllocationCall(node->as.orelse_expr->else_expr);
    } else if (node->type == NODE_BINARY_OP) {
        return isAllocationCall(node->as.binary_op->left) || isAllocationCall(node->as.binary_op->right);
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
    tracked_pointers_.append(tp);
}

TrackedPointer* DoubleFreeAnalyzer::findTrackedPointer(const char* name) {
    for (size_t i = 0; i < tracked_pointers_.length(); ++i) {
        if (strings_equal(tracked_pointers_[i].name, name)) {
            return &tracked_pointers_[i];
        }
    }
    return NULL;
}

const char* DoubleFreeAnalyzer::extractVariableName(ASTNode* node) {
    if (!node) return NULL;
    if (node->type == NODE_IDENTIFIER) {
        return node->as.identifier.name;
    }
    return NULL;
}

void DoubleFreeAnalyzer::reportDoubleFree(const char* name, SourceLocation loc) {
    TrackedPointer* tp = findTrackedPointer(name);
    char* msg = (char*)unit_.getArena().alloc(512);
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
        simple_itoa(tp->alloc_loc.line, buf, sizeof(buf));
        safe_append(p, rem, buf);
        safe_append(p, rem, ":");
        simple_itoa(tp->alloc_loc.column, buf, sizeof(buf));
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
                simple_itoa(tp->defer_loc.line, buf, sizeof(buf));
                safe_append(p, rem, buf);
                safe_append(p, rem, ":");
                simple_itoa(tp->defer_loc.column, buf, sizeof(buf));
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
        simple_itoa(tp->first_free_loc.line, buf, sizeof(buf));
        safe_append(p, rem, buf);
        safe_append(p, rem, ":");
        simple_itoa(tp->first_free_loc.column, buf, sizeof(buf));
        safe_append(p, rem, buf);

        if (tp->freed_via_defer) {
            safe_append(p, rem, ")");
        }
    }

    unit_.getErrorHandler().report(ERR_DOUBLE_FREE, loc, msg, unit_.getArena());
}

void DoubleFreeAnalyzer::reportLeak(const char* name, SourceLocation loc, bool is_reassignment) {
    TrackedPointer* tp = findTrackedPointer(name);
    char* msg = (char*)unit_.getArena().alloc(512);
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
            simple_itoa(tp->transfer_loc.line, buf, sizeof(buf));
            safe_append(p, rem, buf);
            safe_append(p, rem, ":");
            simple_itoa(tp->transfer_loc.column, buf, sizeof(buf));
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
        simple_itoa(tp->alloc_loc.line, buf, sizeof(buf));
        safe_append(p, rem, buf);
        safe_append(p, rem, ":");
        simple_itoa(tp->alloc_loc.column, buf, sizeof(buf));
        safe_append(p, rem, buf);
        safe_append(p, rem, ")");
    }

    unit_.getErrorHandler().reportWarning(code, loc, msg, unit_.getArena());
}

void DoubleFreeAnalyzer::reportUninitializedFree(const char* name, SourceLocation loc) {
    char* msg = (char*)unit_.getArena().alloc(256);
    char* p = msg;
    size_t rem = 256;
    safe_append(p, rem, "Freeing uninitialized pointer '");
    safe_append(p, rem, name);
    safe_append(p, rem, "'");
    unit_.getErrorHandler().reportWarning(WARN_FREE_UNALLOCATED, loc, msg, unit_.getArena());
}
