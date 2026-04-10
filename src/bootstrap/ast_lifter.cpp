#include "ast_lifter.hpp"
#include "ast_utils.hpp"
#include "error_handler.hpp"
#include "type_system.hpp"
#include "symbol_table.hpp"
#include "platform.hpp"
#include "utils.hpp"
#include <new>

ControlFlowLifter::StmtGuard::StmtGuard(ControlFlowLifter& l, ASTNode* stmt) : lifter_(l) {
    lifter_.stmt_stack_.append(stmt);
}

ControlFlowLifter::StmtGuard::~StmtGuard() {
    lifter_.stmt_stack_.pop_back();
}

ControlFlowLifter::BlockGuard::BlockGuard(ControlFlowLifter& l, ASTBlockStmtNode* block) : lifter_(l) {
    lifter_.block_stack_.append(block);
    lifter_.block_decl_insert_idx_stack_.append(0);
}

ControlFlowLifter::BlockGuard::~BlockGuard() {
    lifter_.block_stack_.pop_back();
    lifter_.block_decl_insert_idx_stack_.pop_back();
}

ControlFlowLifter::ParentGuard::ParentGuard(ControlFlowLifter& l, ASTNode* node) : lifter_(l) {
    lifter_.parent_stack_.append(node);
}

ControlFlowLifter::ParentGuard::~ParentGuard() {
    lifter_.parent_stack_.pop_back();
}

ControlFlowLifter::FnGuard::FnGuard(ControlFlowLifter& l, ASTFnDeclNode* fn) : lifter_(l) {
    lifter_.fn_stack_.append(fn);
    lifter_.current_fn_return_type_ = fn->return_type ? fn->return_type->resolved_type : get_g_type_void();
}

ControlFlowLifter::FnGuard::~FnGuard() {
    lifter_.fn_stack_.pop_back();
    if (lifter_.fn_stack_.length() > 0) {
        ASTFnDeclNode* prev_fn = lifter_.fn_stack_.back();
        lifter_.current_fn_return_type_ = prev_fn->return_type ? prev_fn->return_type->resolved_type : get_g_type_void();
    } else {
        lifter_.current_fn_return_type_ = NULL;
    }
}

ControlFlowLifter::ScopeGuard::ScopeGuard(ControlFlowLifter& l) : lifter_(l) {
    if (lifter_.unit_ && lifter_.module_name_) {
        lifter_.unit_->getSymbolTable(lifter_.module_name_).enterScope();
    }
}

ControlFlowLifter::ScopeGuard::~ScopeGuard() {
    if (lifter_.unit_ && lifter_.module_name_) {
        lifter_.unit_->getSymbolTable(lifter_.module_name_).exitScope();
    }
}

ControlFlowLifter::ControlFlowLifter(ArenaAllocator* arena, StringInterner* interner, ErrorHandler* error_handler)
    : arena_(arena), interner_(interner), error_handler_(error_handler),
      unit_(NULL), module_name_(NULL), debug_mode_(false),
      tmp_counter_(0), depth_(0), MAX_LIFTING_DEPTH(1000),
      current_fn_return_type_(NULL),
      registered_temps_(*arena),
      processed_calls_(*arena),
      stmt_stack_(*arena), block_stack_(*arena), 
      block_decl_insert_idx_stack_(*arena),
      parent_stack_(*arena), fn_stack_(*arena) {}

void ControlFlowLifter::lift(CompilationUnit* unit) {
    unit_ = unit;
    const DynamicArray<Module*>& modules = unit->getModules();
    for (size_t i = 0; i < modules.length(); ++i) {
        Module* mod = modules[i];
        if (!mod->ast_root) continue;

        module_name_ = mod->name;
        tmp_counter_ = 0;
        depth_ = 0;
        registered_temps_.clear();
        processed_calls_.clear();

        transformNode(&mod->ast_root, NULL);
        validateLifting(mod);
    }
    unit_ = NULL;
    module_name_ = NULL;
}

void ControlFlowLifter::transformNode(ASTNode** node_slot, ASTNode* parent) {
    ASTNode* node = *node_slot;
    if (!node) return;

    if (debug_mode_) {
#ifdef Z98_ENABLE_DEBUG_LOGS
        plat_printf_debug("[LIFTER] transformNode type=%d\n", (int)node->type);
#endif
    }

    depth_++;
    if (depth_ > MAX_LIFTING_DEPTH) {
        error_handler_->report(ERR_INTERNAL_ERROR, node->loc, "AST lifting recursion depth exceeded", NULL);
        plat_abort();
    }

    // Identify if this node is a statement or a block to manage the context stacks.
    bool is_stmt = (node->type == NODE_EXPRESSION_STMT || node->type == NODE_RETURN_STMT ||
                    node->type == NODE_VAR_DECL || node->type == NODE_IF_STMT ||
                    node->type == NODE_WHILE_STMT || node->type == NODE_FOR_STMT ||
                    node->type == NODE_BREAK_STMT || node->type == NODE_CONTINUE_STMT ||
                    node->type == NODE_DEFER_STMT || node->type == NODE_ERRDEFER_STMT ||
                    node->type == NODE_SWITCH_STMT);

    bool is_block = (node->type == NODE_BLOCK_STMT);
    bool is_fn = (node->type == NODE_FN_DECL);

    // Wrap non-block bodies of control-flow statements before they are transformed.
    if (node->type == NODE_IF_STMT) {
        ASTIfStmtNode* if_stmt = node->as.if_stmt;
        if (if_stmt->then_block && if_stmt->then_block->type != NODE_BLOCK_STMT) {
            if_stmt->then_block = wrapInBlock(if_stmt->then_block);
        }
        if (if_stmt->else_block && if_stmt->else_block->type != NODE_BLOCK_STMT &&
            if_stmt->else_block->type != NODE_IF_STMT) {
            if_stmt->else_block = wrapInBlock(if_stmt->else_block);
        }
    } else if (node->type == NODE_WHILE_STMT) {
        ASTWhileStmtNode* while_stmt = node->as.while_stmt;
        if (while_stmt->body && while_stmt->body->type != NODE_BLOCK_STMT) {
            while_stmt->body = wrapInBlock(while_stmt->body);
        }

        if (while_stmt->capture_name && while_stmt->capture_sym) {
            // Scope for while capture is handled in transformNode recursion for the body
        }
    } else if (node->type == NODE_FOR_STMT) {
        ASTForStmtNode* for_stmt = node->as.for_stmt;
        if (for_stmt->body && for_stmt->body->type != NODE_BLOCK_STMT) {
            for_stmt->body = wrapInBlock(for_stmt->body);
        }
    } else if (node->type == NODE_DEFER_STMT) {
        if (node->as.defer_stmt.statement && node->as.defer_stmt.statement->type != NODE_BLOCK_STMT) {
            node->as.defer_stmt.statement = wrapInBlock(node->as.defer_stmt.statement);
        }
    } else if (node->type == NODE_ERRDEFER_STMT) {
        if (node->as.errdefer_stmt.statement && node->as.errdefer_stmt.statement->type != NODE_BLOCK_STMT) {
            node->as.errdefer_stmt.statement = wrapInBlock(node->as.errdefer_stmt.statement);
        }
    } else if (node->type == NODE_SWITCH_STMT) {
        ASTSwitchStmtNode* switch_stmt = node->as.switch_stmt;
        if (switch_stmt->prongs) {
            for (size_t i = 0; i < switch_stmt->prongs->length(); ++i) {
                ASTSwitchStmtProngNode* prong = (*switch_stmt->prongs)[i];
                if (prong->body && prong->body->type != NODE_BLOCK_STMT) {
                    prong->body = wrapInBlock(prong->body);
                }
            }
        }
    }

    // Expression-form control flow gets handled Top-Down to ensure nested lifting
    // is contained within the branches' lowering blocks.
    if (isControlFlowExpr(node->type) && needsLifting(node, parent)) {
        // Transform the "input" children first
        if (node->type == NODE_IF_EXPR) {
            transformNode(&node->as.if_expr->condition, node);
        } else if (node->type == NODE_SWITCH_EXPR) {
            transformNode(&node->as.switch_expr->expression, node);
        } else if (node->type == NODE_TRY_EXPR) {
            transformNode(&node->as.try_expr.expression, node);
        } else if (node->type == NODE_CATCH_EXPR) {
            transformNode(&node->as.catch_expr->payload, node);
        } else if (node->type == NODE_ORELSE_EXPR) {
            transformNode(&node->as.orelse_expr->payload, node);
        } else if (node->type == NODE_SWITCH_STMT) {
            // Recurse but do NOT lift
            ASTSwitchStmtNode* sw = node->as.switch_stmt;
            transformNode(&sw->expression, node);
            if (sw->prongs) {
                for (size_t i = 0; i < sw->prongs->length(); ++i) {
                    ASTSwitchStmtProngNode* prong = (*sw->prongs)[i];
                    if (prong->items) {
                        for (size_t j = 0; j < prong->items->length(); ++j) {
                            transformNode(&(*prong->items)[j], node);
                        }
                    }
                    transformNode(&prong->body, node);
                    if (prong->body->type != NODE_BLOCK_STMT) {
                        prong->body = wrapInBlock(prong->body);
                    }
                }
            }
            depth_--;
            return;
        }

        bool needs_wrapping = false;
        if (node->type == NODE_TRY_EXPR) {
            const ASTNode* effective_parent = skipParens(parent);
            if (effective_parent && effective_parent->type == NODE_RETURN_STMT) {
                needs_wrapping = true;
            }
        }
        liftNode(node_slot, parent, getPrefixForType(node->type), needs_wrapping);

        if (debug_mode_ && *node_slot) {
            validateASTIntegrity(*node_slot, "pre-lift-transformed");
        }
        depth_--;
        return;
    }

    {
        ParentGuard pguard(*this, node);

        // Inner function to handle the rest of transformation after potentially setting guards
        struct Inner {
            static void process(ControlFlowLifter* lifter, ASTNode* node) {
                // Post-order: transform children first
                struct TransformVisitor : ChildVisitor {
                    ControlFlowLifter* lifter;
                    ASTNode* current_node;
                    TransformVisitor(ControlFlowLifter* l, ASTNode* n) : lifter(l), current_node(n) {}

                    void visitChild(ASTNode** child_slot) {
                        // Skip branches of control flow expressions as they are handled in lowerXXX
                        if (isControlFlowExpr(current_node->type)) {
                            if (current_node->type == NODE_IF_EXPR) {
                                if (child_slot == &current_node->as.if_expr->then_expr ||
                                    child_slot == &current_node->as.if_expr->else_expr) return;
                            } else if (current_node->type == NODE_SWITCH_EXPR) {
                                // Branches are prong bodies
                                return; // Handled manually in lowerSwitchExpr
                            } else if (current_node->type == NODE_CATCH_EXPR) {
                                if (child_slot == &current_node->as.catch_expr->else_expr) return;
                            } else if (current_node->type == NODE_ORELSE_EXPR) {
                                if (child_slot == &current_node->as.orelse_expr->else_expr) return;
                            }
                        }

                        lifter->transformNode(child_slot, current_node);
                    }
                };
                TransformVisitor visitor(lifter, node);
                forEachChild(node, visitor);
            }
        };

        if (is_stmt && is_block) {
            StmtGuard sguard(*this, node);
            BlockGuard bguard(*this, &node->as.block_stmt);
            ScopeGuard scguard(*this);
            Inner::process(this, node);
            if (node->type == NODE_RETURN_STMT) lowerExportReturn(node_slot, parent);
        } else if (is_stmt) {
            StmtGuard sguard(*this, node);
            Inner::process(this, node);
            if (node->type == NODE_RETURN_STMT) lowerExportReturn(node_slot, parent);
        } else if (is_block) {
            BlockGuard bguard(*this, &node->as.block_stmt);
            ScopeGuard scguard(*this);
            Inner::process(this, node);
        } else if (is_fn) {
            FnGuard fguard(*this, node->as.fn_decl);
            if (node->as.fn_decl->is_export) {
                lowerExportPrologue(node->as.fn_decl);
            }
            Inner::process(this, node);
        } else if (node->type == NODE_WHILE_STMT && node->as.while_stmt->capture_name) {
            // Special handling for while capture scope
            transformNode(&node->as.while_stmt->condition, node);
            if (node->as.while_stmt->iter_expr) transformNode(&node->as.while_stmt->iter_expr, node);

            ScopeGuard scguard(*this);
            transformNode(&node->as.while_stmt->body, node);
        } else {
            Inner::process(this, node);
            // Handle extern calls (ABI unwrapping)
            if (node->type == NODE_FUNCTION_CALL && block_stack_.length() > 0 && stmt_stack_.length() > 0) {
                bool already_processed = false;
                for (size_t i = 0; i < processed_calls_.length(); ++i) {
                    if (processed_calls_[i] == node) {
                        already_processed = true;
                        break;
                    }
                }
                if (!already_processed) {
                    lowerExternCall(node_slot, parent);
                }
            }
        }
    }

    // Decision: does THIS node need lifting? (for non-CF expressions if any)
    if (needsLifting(node, parent)) {
        bool needs_wrapping = false;
        if (node->type == NODE_TRY_EXPR) {
            const ASTNode* effective_parent = skipParens(parent);
            if (effective_parent && effective_parent->type == NODE_RETURN_STMT) {
                needs_wrapping = true;
            }
        }
        liftNode(node_slot, parent, getPrefixForType(node->type), needs_wrapping);

        if (debug_mode_ && *node_slot) {
            validateASTIntegrity(*node_slot, "post-lift");
        }
    }

    depth_--;
}

ASTNode* ControlFlowLifter::wrapInBlock(ASTNode* stmt) {
    if (!stmt) return NULL;
    if (stmt->type == NODE_BLOCK_STMT) return stmt;

    void* array_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    DynamicArray<ASTNode*>* stmts = new (array_mem) DynamicArray<ASTNode*>(*arena_);
    stmts->append(stmt);

    ASTNode* block_node = createBlock(stmts, stmt->loc);
    return block_node;
}

void ControlFlowLifter::lowerExternCall(ASTNode** node_slot, ASTNode* parent) {
    RETR_UNUSED(parent);
    ASTNode* node = *node_slot;
    processed_calls_.append(node);

    ASTFunctionCallNode* call = node->as.function_call;
    Symbol* sym = NULL;

    if (call->callee->type == NODE_IDENTIFIER) {
        sym = call->callee->as.identifier.symbol;
    } else if (call->callee->type == NODE_MEMBER_ACCESS) {
        sym = call->callee->as.member_access->symbol;
    }

    if (!sym || !sym->c_prototype_type) return;

#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[LIFTER] lowerExternCall for sym=%s\n", sym->name);
#endif

    // 1. Lower arguments
    DynamicArray<Type*>* abi_params = sym->c_prototype_type->as.function.params;
    for (size_t i = 0; i < call->args->length(); ++i) {
        if (i >= abi_params->length()) break;
        Type* abi_type = (*abi_params)[i];
        ASTNode* arg = (*call->args)[i];

        if (abi_type->kind == TYPE_POINTER && isOptionalPointer(arg->resolved_type)) {
            // Fix double-evaluation: evaluate expression into an optional temporary first
            const char* opt_tmp_name = generateTempName("arg_opt");
            ASTNode* opt_tmp_decl = createVarDecl(opt_tmp_name, arg->resolved_type, arg, true);
            Symbol* opt_tmp_sym = opt_tmp_decl->as.var_decl->symbol;

            // Unwrap optional pointer: (opt_tmp.has_value) ? opt_tmp.value : NULL
            const char* arg_tmp_name = generateTempName("arg_unwrapped");
            ASTNode* arg_tmp_decl = createVarDecl(arg_tmp_name, abi_type, NULL, false);
            Symbol* arg_tmp_sym = arg_tmp_decl->as.var_decl->symbol;

            // Find insertion point
            ASTBlockStmtNode* current_block = block_stack_.back();
            ASTNode* current_stmt = stmt_stack_.back();
            int insert_idx = findStatementIndex(current_block, current_stmt);
            if (insert_idx == -1) {
#ifdef Z98_ENABLE_DEBUG_LOGS
                 plat_printf_debug("[LIFTER] WARNING: Could not find insertion point for arg unwrapping!\n");
#endif
                 continue;
            }
            current_block->statements->insert((size_t)insert_idx, opt_tmp_decl);
            current_block->statements->insert((size_t)insert_idx + 1, arg_tmp_decl);

            ASTNode* opt_tmp_ident = createIdentifier(opt_tmp_name, arg->loc, opt_tmp_sym);
            opt_tmp_ident->resolved_type = arg->resolved_type;

            ASTNode* arg_tmp_ident = createIdentifier(arg_tmp_name, arg->loc, arg_tmp_sym);
            arg_tmp_ident->resolved_type = abi_type;

            ASTNode* has_value = createMemberAccess(opt_tmp_ident, "has_value", arg->loc);
            has_value->resolved_type = get_g_type_bool();
            ASTNode* value = createMemberAccess(opt_tmp_ident, "value", arg->loc);
            value->resolved_type = abi_type;
            ASTNode* null_lit = createIntegerLiteral(0, abi_type, arg->loc);

            ASTNode* then_assign = createExpressionStmt(createAssignment(arg_tmp_ident, value, arg->loc), arg->loc);
            ASTNode* else_assign = createExpressionStmt(createAssignment(arg_tmp_ident, null_lit, arg->loc), arg->loc);
            ASTNode* if_stmt = createIfStmt(has_value, createBlock(new (arena_->alloc(sizeof(DynamicArray<ASTNode*>))) DynamicArray<ASTNode*>(*arena_), arg->loc),
                                           createBlock(new (arena_->alloc(sizeof(DynamicArray<ASTNode*>))) DynamicArray<ASTNode*>(*arena_), arg->loc), arg->loc);
            if_stmt->as.if_stmt->then_block->as.block_stmt.statements->append(then_assign);
            if_stmt->as.if_stmt->else_block->as.block_stmt.statements->append(else_assign);

            current_block->statements->insert((size_t)insert_idx + 2, if_stmt);

            // Re-find current_stmt index because we modified the array
            insert_idx = findStatementIndex(current_block, current_stmt);

            (*call->args)[i] = arg_tmp_ident;
        }
    }

    // 2. Wrap return value if needed
    Type* abi_ret = sym->c_prototype_type->as.function.return_type;
    if (abi_ret->kind == TYPE_POINTER && isOptionalPointer(node->resolved_type)) {
        const char* call_tmp_name = generateTempName("call_res_raw");
        ASTNode* call_tmp_decl = createVarDecl(call_tmp_name, abi_ret, node, true);
        Symbol* call_tmp_sym = call_tmp_decl->as.var_decl->symbol;

        const char* wrapped_tmp_name = generateTempName("call_res_wrapped");
        ASTNode* wrapped_tmp_decl = createVarDecl(wrapped_tmp_name, node->resolved_type, NULL, false);
        Symbol* wrapped_tmp_sym = wrapped_tmp_decl->as.var_decl->symbol;

        ASTBlockStmtNode* current_block = block_stack_.back();
        ASTNode* current_stmt = stmt_stack_.back();
        int insert_idx = findStatementIndex(current_block, current_stmt);
        if (insert_idx == -1) {
#ifdef Z98_ENABLE_DEBUG_LOGS
             plat_printf_debug("[LIFTER] WARNING: Could not find insertion point for call res wrapping!\n");
#endif
             return;
        }

        current_block->statements->insert((size_t)insert_idx, call_tmp_decl);
        current_block->statements->insert((size_t)insert_idx + 1, wrapped_tmp_decl);

        ASTNode* call_tmp_ident = createIdentifier(call_tmp_name, node->loc, call_tmp_sym);
        call_tmp_ident->resolved_type = abi_ret;
        ASTNode* wrapped_tmp_ident = createIdentifier(wrapped_tmp_name, node->loc, wrapped_tmp_sym);
        wrapped_tmp_ident->resolved_type = node->resolved_type;

        ASTNode* cond = createBinaryOp(call_tmp_ident, createIntegerLiteral(0, abi_ret, node->loc), TOKEN_BANG_EQUAL, get_g_type_bool(), node->loc);

        // wrapped.has_value = 1; wrapped.value = call_res;
        ASTNode* then_has = createExpressionStmt(createAssignment(createMemberAccess(wrapped_tmp_ident, "has_value", node->loc), createIntegerLiteral(1, get_g_type_bool(), node->loc), node->loc), node->loc);
        ASTNode* then_val = createExpressionStmt(createAssignment(createMemberAccess(wrapped_tmp_ident, "value", node->loc), call_tmp_ident, node->loc), node->loc);

        // wrapped.has_value = 0;
        ASTNode* else_has = createExpressionStmt(createAssignment(createMemberAccess(wrapped_tmp_ident, "has_value", node->loc), createIntegerLiteral(0, get_g_type_bool(), node->loc), node->loc), node->loc);

        ASTNode* then_block = createBlock(new (arena_->alloc(sizeof(DynamicArray<ASTNode*>))) DynamicArray<ASTNode*>(*arena_), node->loc);
        then_block->as.block_stmt.statements->append(then_has);
        then_block->as.block_stmt.statements->append(then_val);

        ASTNode* else_block = createBlock(new (arena_->alloc(sizeof(DynamicArray<ASTNode*>))) DynamicArray<ASTNode*>(*arena_), node->loc);
        else_block->as.block_stmt.statements->append(else_has);

        current_block->statements->insert((size_t)insert_idx + 2, createIfStmt(cond, then_block, else_block, node->loc));

        *node_slot = wrapped_tmp_ident;
    }
}

void ControlFlowLifter::lowerExportPrologue(ASTFnDeclNode* fn) {
    Symbol* sym = (unit_ && module_name_) ? unit_->getSymbolTable(module_name_).lookup(fn->name) : NULL;
    if (!sym || !sym->c_prototype_type || !fn->body) return;

#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[LIFTER] lowerExportPrologue for %s\n", fn->name);
#endif

    DynamicArray<Type*>* abi_params = sym->c_prototype_type->as.function.params;
    ASTBlockStmtNode* body = &fn->body->as.block_stmt;

    DynamicArray<ASTNode*> prologue(*arena_);
    DynamicArray<RebindEntry> rebinds(*arena_);

    for (size_t i = 0; i < fn->params->length(); ++i) {
        if (i >= abi_params->length()) break;
        ASTParamDeclNode& param = (*fn->params)[i]->as.param_decl;
        Type* abi_type = (*abi_params)[i];

        if (abi_type->kind == TYPE_POINTER && isOptionalPointer(param.symbol->symbol_type)) {
#ifdef Z98_ENABLE_DEBUG_LOGS
            plat_printf_debug("[LIFTER]   Wrapping param %s\n", param.name);
#endif
            // Wrap raw pointer parameter in Zig-side optional
            const char* wrapped_name = generateTempName(param.name);
            ASTNode* wrapped_decl = createVarDecl(wrapped_name, param.symbol->symbol_type, NULL, false);
            Symbol* wrapped_sym = wrapped_decl->as.var_decl->symbol;
            ASTNode* wrapped_ident = createIdentifier(wrapped_name, fn->body->loc, wrapped_sym);
            wrapped_ident->resolved_type = param.symbol->symbol_type;

            // Important: raw parameter identifier MUST NOT have a symbol that gets rebound
            ASTNode* param_ident = createIdentifier(param.name, fn->body->loc, NULL);
            param_ident->resolved_type = abi_type;
            param_ident->as.identifier.symbol = param.symbol;

            ASTNode* cond = createBinaryOp(param_ident, createIntegerLiteral(0, abi_type, fn->body->loc), TOKEN_BANG_EQUAL, get_g_type_bool(), fn->body->loc);

            ASTNode* then_has = createExpressionStmt(createAssignment(createMemberAccess(wrapped_ident, "has_value", fn->body->loc), createIntegerLiteral(1, get_g_type_bool(), fn->body->loc), fn->body->loc), fn->body->loc);
            ASTNode* then_val = createExpressionStmt(createAssignment(createMemberAccess(wrapped_ident, "value", fn->body->loc), param_ident, fn->body->loc), fn->body->loc);
            ASTNode* else_has = createExpressionStmt(createAssignment(createMemberAccess(wrapped_ident, "has_value", fn->body->loc), createIntegerLiteral(0, get_g_type_bool(), fn->body->loc), fn->body->loc), fn->body->loc);

            ASTNode* then_block = createBlock(new (arena_->alloc(sizeof(DynamicArray<ASTNode*>))) DynamicArray<ASTNode*>(*arena_), fn->body->loc);
            then_block->as.block_stmt.statements->append(then_has);
            then_block->as.block_stmt.statements->append(then_val);

            ASTNode* else_block = createBlock(new (arena_->alloc(sizeof(DynamicArray<ASTNode*>))) DynamicArray<ASTNode*>(*arena_), fn->body->loc);
            else_block->as.block_stmt.statements->append(else_has);

            prologue.append(wrapped_decl);
            prologue.append(createIfStmt(cond, then_block, else_block, fn->body->loc));

            RebindEntry r; r.old_sym = param.symbol; r.new_sym = wrapped_sym;
            rebinds.append(r);
        }
    }

    // 1. Rebind original body
    for (size_t j = 0; j < body->statements->length(); ++j) {
        for (size_t k = 0; k < rebinds.length(); ++k) {
            updateCaptureSymbols((*body->statements)[j], rebinds[k].old_sym, rebinds[k].new_sym);
        }
    }

    // 2. Prepend prologue
    for (int i = (int)prologue.length() - 1; i >= 0; --i) {
        body->statements->insert(0, prologue[i]);
    }
}

void ControlFlowLifter::lowerExportReturn(ASTNode** node_slot, ASTNode* parent) {
    RETR_UNUSED(parent);
    if (fn_stack_.length() == 0) return;
    ASTFnDeclNode* fn = fn_stack_.back();
    if (!fn->is_export) return;

    Symbol* sym = (unit_ && module_name_) ? unit_->getSymbolTable(module_name_).lookup(fn->name) : NULL;
    if (!sym || !sym->c_prototype_type) return;

    Type* abi_ret = sym->c_prototype_type->as.function.return_type;
    ASTNode* node = *node_slot;
    ASTReturnStmtNode& ret = node->as.return_stmt;

    bool abi_ret_is_ptr = (abi_ret->kind == TYPE_POINTER || abi_ret->kind == TYPE_FUNCTION_POINTER);
    if (ret.expression && abi_ret_is_ptr && isOptionalPointer(ret.expression->resolved_type)) {
#ifdef Z98_ENABLE_DEBUG_LOGS
        plat_printf_debug("[LIFTER] lowerExportReturn for fn=%s\n", fn->name);
#endif

        // Fix double-evaluation: evaluate expression into an optional temporary first
        const char* opt_tmp_name = generateTempName("ret_opt");
        ASTNode* opt_tmp_decl = createVarDecl(opt_tmp_name, ret.expression->resolved_type, ret.expression, true);
        Symbol* opt_tmp_sym = opt_tmp_decl->as.var_decl->symbol;

        // Unwrap optional before return: (opt_tmp.has_value) ? opt_tmp.value : NULL
        const char* ret_tmp_name = generateTempName("ret_unwrapped");
        ASTNode* ret_tmp_decl = createVarDecl(ret_tmp_name, abi_ret, NULL, false);
        Symbol* ret_tmp_sym = ret_tmp_decl->as.var_decl->symbol;

        ASTBlockStmtNode* current_block = block_stack_.back();
        ASTNode* current_stmt = stmt_stack_.back();
        int insert_idx = findStatementIndex(current_block, current_stmt);
        if (insert_idx == -1) {
#ifdef Z98_ENABLE_DEBUG_LOGS
             plat_printf_debug("[LIFTER] WARNING: Could not find insertion point for return unwrapping!\n");
#endif
             return;
        }
        current_block->statements->insert((size_t)insert_idx, opt_tmp_decl);
        current_block->statements->insert((size_t)insert_idx + 1, ret_tmp_decl);

        ASTNode* opt_tmp_ident = createIdentifier(opt_tmp_name, ret.expression->loc, opt_tmp_sym);
        opt_tmp_ident->resolved_type = ret.expression->resolved_type;

        ASTNode* ret_tmp_ident = createIdentifier(ret_tmp_name, ret.expression->loc, ret_tmp_sym);
        ret_tmp_ident->resolved_type = abi_ret;

        ASTNode* has_value = createMemberAccess(opt_tmp_ident, "has_value", ret.expression->loc);
        has_value->resolved_type = get_g_type_bool();
        ASTNode* value = createMemberAccess(opt_tmp_ident, "value", ret.expression->loc);
        value->resolved_type = abi_ret;
        ASTNode* null_lit = createIntegerLiteral(0, abi_ret, ret.expression->loc);

        ASTNode* then_assign = createExpressionStmt(createAssignment(ret_tmp_ident, value, ret.expression->loc), ret.expression->loc);
        ASTNode* else_assign = createExpressionStmt(createAssignment(ret_tmp_ident, null_lit, ret.expression->loc), ret.expression->loc);

        ASTNode* then_block = createBlock(new (arena_->alloc(sizeof(DynamicArray<ASTNode*>))) DynamicArray<ASTNode*>(*arena_), ret.expression->loc);
        then_block->as.block_stmt.statements->append(then_assign);
        ASTNode* else_block = createBlock(new (arena_->alloc(sizeof(DynamicArray<ASTNode*>))) DynamicArray<ASTNode*>(*arena_), ret.expression->loc);
        else_block->as.block_stmt.statements->append(else_assign);

        current_block->statements->insert((size_t)insert_idx + 2, createIfStmt(has_value, then_block, else_block, ret.expression->loc));

        ret.expression = ret_tmp_ident;
    }
}

bool ControlFlowLifter::isOptionalPointer(Type* t) {
    if (!t || t->kind != TYPE_OPTIONAL) return false;
    Type* payload = t->as.optional.payload;
    return payload->kind == TYPE_POINTER || payload->kind == TYPE_FUNCTION_POINTER;
}

bool ControlFlowLifter::isAggregateType(Type* t) {
    if (!t) return false;
    switch (t->kind) {
        case TYPE_STRUCT:
        case TYPE_UNION:
        case TYPE_TAGGED_UNION:
        case TYPE_SLICE:
        case TYPE_OPTIONAL:
        case TYPE_ERROR_UNION:
        case TYPE_ARRAY:
            return true;
        default:
            return false;
    }
}

bool ControlFlowLifter::needsLifting(ASTNode* node, ASTNode* parent) {
    if (!node || !parent) return false;

    // [NEW] Don't lift synthetic anytype placeholders.
    // These are internal coercion artifacts that must be resolved
    // by their parent context before any lifting occurs.
    if (node->resolved_type && node->resolved_type->kind == TYPE_ANYTYPE) {
        return false;
    }

    // 1. Control-flow expressions always need lifting (unless they yield void)
    if (isControlFlowExpr(node->type)) {
        if (node->type == NODE_SWITCH_STMT) return false; // Statement form

        if (node->resolved_type) {
            TypeKind k = node->resolved_type->kind;
            if (k == TYPE_VOID) return false;
        }

        // Skip parentheses to get the real semantic parent
        const ASTNode* effective_parent = skipParens(parent);
        if (!effective_parent) return false; // Root is always safe

        // unreachable is already a valid statement if handled by the emitter.
        if (node->type == NODE_UNREACHABLE) {
            if (effective_parent->type == NODE_BLOCK_STMT ||
                effective_parent->type == NODE_EXPRESSION_STMT ||
                effective_parent->type == NODE_DEFER_STMT ||
                effective_parent->type == NODE_ERRDEFER_STMT) {
                return false;
            }
        }

        return true;
    }

    // 2. Aggregate literals in expression contexts need lifting to avoid C99 compound literals.
    if (node->type == NODE_STRUCT_INITIALIZER || node->type == NODE_TUPLE_LITERAL) {
        // If the parent is a VarDecl and this node is its direct initializer, it's allowed in C89.
        const ASTNode* effective_parent = skipParens(parent);
        if (effective_parent) {
            if (effective_parent->type == NODE_VAR_DECL) {
                ASTVarDeclNode* vd = effective_parent->as.var_decl;
                if (vd->initializer == node) {
                    return false; // keep as initializer
                }
            }

            // [NEW] Aggregate literals in return statements and assignments
            // can be decomposed by the emitter into direct field assignments,
            // which is both C89-compliant and avoids introducing temporaries
            // that break existing tests.
            if (effective_parent->type == NODE_RETURN_STMT ||
                effective_parent->type == NODE_ASSIGNMENT) {
                return false;
            }

            // [NEW] Nested aggregate literals do not need lifting because their parent's
            // decomposition will handle them recursively. This also prevents lifting
            // synthetic coercion artifacts that have concrete types.
            if (effective_parent->type == NODE_STRUCT_INITIALIZER ||
                effective_parent->type == NODE_TUPLE_LITERAL) {
                return false;
            }
        }
        return true; // lift in all other contexts (function arguments, returns, assignments, etc.)
    }

    return false;
}

const ASTNode* ControlFlowLifter::skipParens(const ASTNode* parent) {
    if (!parent) return NULL;
    const ASTNode* cur = parent;

    int idx = (int)parent_stack_.length() - 1;
    if (idx < 0 || parent_stack_[idx] != parent) {
        idx = -1;
        for (int i = (int)parent_stack_.length() - 1; i >= 0; --i) {
            if (parent_stack_[i] == parent) {
                idx = i;
                break;
            }
        }
    }

    if (idx < 0) return parent;

    while (cur && cur->type == NODE_PAREN_EXPR) {
        if (idx > 0) {
            idx--;
            cur = parent_stack_[idx];
        } else {
            return NULL;
        }
    }

    return cur;
}

Symbol* ControlFlowLifter::createSymbol(const char* name, Type* type, bool is_const) {
    Symbol* sym = (Symbol*)arena_->alloc(sizeof(Symbol));
    plat_memset(sym, 0, sizeof(Symbol));
    sym->name = name;
    sym->symbol_type = type;
    sym->kind = SYMBOL_VARIABLE;
    sym->flags = SYMBOL_FLAG_LOCAL;
    if (is_const) sym->flags |= SYMBOL_FLAG_CONST;
    sym->scope_level = 0; // Temporaries are managed via blocks, not SymbolTable scope
    return sym;
}

ASTNode* ControlFlowLifter::createVarDecl(const char* name, Type* type, ASTNode* init, bool is_const) {
    ASTVarDeclNode* var_decl_data = (ASTVarDeclNode*)arena_->alloc(sizeof(ASTVarDeclNode));
    plat_memset(var_decl_data, 0, sizeof(ASTVarDeclNode));
    var_decl_data->name = name;
    var_decl_data->name_loc = init ? init->loc : (stmt_stack_.length() > 0 ? stmt_stack_.back()->loc : SourceLocation());
    var_decl_data->initializer = init;
    var_decl_data->is_const = is_const;
    var_decl_data->is_mut = !is_const;

    if (name) {
        var_decl_data->symbol = createSymbol(name, type, is_const);

        if (plat_strncmp(name, "__tmp_", 6) == 0) {
            registered_temps_.append(name);
        }
    }

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(node, 0, sizeof(ASTNode));
    node->type = NODE_VAR_DECL;
    node->loc = var_decl_data->name_loc;
    node->resolved_type = type;
    node->as.var_decl = var_decl_data;
    return node;
}

ASTNode* ControlFlowLifter::createIdentifier(const char* name, SourceLocation loc, Symbol* sym) {
    ASTNode* ident_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(ident_node, 0, sizeof(ASTNode));
    ident_node->type = NODE_IDENTIFIER;
    ident_node->loc = loc;
    ident_node->as.identifier.name = name;
    ident_node->as.identifier.symbol = sym;
    return ident_node;
}

ASTNode* ControlFlowLifter::createBinaryOp(ASTNode* left, ASTNode* right, Zig0TokenType op, Type* type, SourceLocation loc) {
    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(node, 0, sizeof(ASTNode));
    node->type = NODE_BINARY_OP;
    node->loc = loc;
    node->as.binary_op = (ASTBinaryOpNode*)arena_->alloc(sizeof(ASTBinaryOpNode));
    node->as.binary_op->left = left;
    node->as.binary_op->right = right;
    node->as.binary_op->op = op;
    node->resolved_type = type;
    return node;
}

ASTNode* ControlFlowLifter::createAssignment(ASTNode* lvalue, ASTNode* rvalue, SourceLocation loc) {
    ASTAssignmentNode* assign = (ASTAssignmentNode*)arena_->alloc(sizeof(ASTAssignmentNode));
    plat_memset(assign, 0, sizeof(ASTAssignmentNode));
    assign->lvalue = lvalue;
    assign->rvalue = rvalue;

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(node, 0, sizeof(ASTNode));
    node->type = NODE_ASSIGNMENT;
    node->loc = loc;
    node->resolved_type = lvalue->resolved_type;
    node->as.assignment = assign;
    return node;
}

ASTNode* ControlFlowLifter::createBlock(DynamicArray<ASTNode*>* statements, SourceLocation loc) {
    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(node, 0, sizeof(ASTNode));
    node->type = NODE_BLOCK_STMT;
    node->loc = loc;
    node->as.block_stmt.statements = statements;
    return node;
}

ASTNode* ControlFlowLifter::createIfStmt(ASTNode* cond, ASTNode* then_block, ASTNode* else_block, SourceLocation loc) {
    ASTIfStmtNode* if_stmt = (ASTIfStmtNode*)arena_->alloc(sizeof(ASTIfStmtNode));
    plat_memset(if_stmt, 0, sizeof(ASTIfStmtNode));
    if_stmt->condition = cond;
    if_stmt->then_block = then_block;
    if_stmt->else_block = else_block;

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(node, 0, sizeof(ASTNode));
    node->type = NODE_IF_STMT;
    node->loc = loc;
    node->as.if_stmt = if_stmt;
    return node;
}

ASTNode* ControlFlowLifter::createSwitchStmt(ASTNode* cond, DynamicArray<ASTSwitchStmtProngNode*>* prongs, SourceLocation loc) {
    ASTSwitchStmtNode* switch_stmt = (ASTSwitchStmtNode*)arena_->alloc(sizeof(ASTSwitchStmtNode));
    plat_memset(switch_stmt, 0, sizeof(ASTSwitchStmtNode));
    switch_stmt->expression = cond;
    switch_stmt->prongs = prongs;

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(node, 0, sizeof(ASTNode));
    node->type = NODE_SWITCH_STMT;
    node->loc = loc;
    node->as.switch_stmt = switch_stmt;
    return node;
}

ASTNode* ControlFlowLifter::createExpressionStmt(ASTNode* expr, SourceLocation loc) {
    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(node, 0, sizeof(ASTNode));
    node->type = NODE_EXPRESSION_STMT;
    node->loc = loc;
    node->as.expression_stmt.expression = expr;
    return node;
}

ASTNode* ControlFlowLifter::createReturn(ASTNode* expr, SourceLocation loc) {
    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(node, 0, sizeof(ASTNode));
    node->type = NODE_RETURN_STMT;
    node->loc = loc;
    node->as.return_stmt.expression = expr;
    return node;
}

ASTNode* ControlFlowLifter::createMemberAccess(ASTNode* base, const char* field_name, SourceLocation loc) {
    ASTMemberAccessNode* member = (ASTMemberAccessNode*)arena_->alloc(sizeof(ASTMemberAccessNode));
    plat_memset(member, 0, sizeof(ASTMemberAccessNode));
    member->base = base;
    member->field_name = field_name;

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(node, 0, sizeof(ASTNode));
    node->type = NODE_MEMBER_ACCESS;
    node->loc = loc;
    node->as.member_access = member;
    return node;
}

ASTNode* ControlFlowLifter::createIntegerLiteral(u64 value, Type* type, SourceLocation loc) {
    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(node, 0, sizeof(ASTNode));
    node->type = NODE_INTEGER_LITERAL;
    node->loc = loc;
    node->resolved_type = type;
    node->as.integer_literal.value = value;
    node->as.integer_literal.resolved_type = type;
    return node;
}

ASTNode* ControlFlowLifter::createNodeAt(NodeType type, SourceLocation loc) {
    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(node, 0, sizeof(ASTNode));
    node->type = type;
    node->loc = loc;
    node->module = module_name_;
    return node;
}

void ControlFlowLifter::updateCaptureSymbols(ASTNode* node, Symbol* old_sym, Symbol* new_sym) {
    if (!node || !old_sym || !new_sym) return;

    if (node->type == NODE_IDENTIFIER) {
        if (node->as.identifier.symbol == old_sym) {
            node->as.identifier.symbol = new_sym;
            node->resolved_type = new_sym->symbol_type;
        }
    }

    struct UpdateVisitor : ChildVisitor {
        ControlFlowLifter* lifter;
        Symbol* old_sym;
        Symbol* new_sym;
        UpdateVisitor(ControlFlowLifter* l, Symbol* o, Symbol* n) : lifter(l), old_sym(o), new_sym(n) {}
        void visitChild(ASTNode** child_slot) {
            lifter->updateCaptureSymbols(*child_slot, old_sym, new_sym);
        }
    };

    UpdateVisitor visitor(this, old_sym, new_sym);
    forEachChild(node, visitor);
}

ASTNode* ControlFlowLifter::lowerIfExpr(ASTNode* node, Symbol* temp_sym) {
    ASTIfExprNode* if_expr = node->as.if_expr;
    SourceLocation loc = node->loc;

    ASTNode* temp_ident = createIdentifier(temp_sym->name, loc, temp_sym);
    temp_ident->resolved_type = node->resolved_type;

    ASTNode* then_block;
    {
        ASTNode* branch_expr = if_expr->then_expr;
        if (branch_expr->type == NODE_BLOCK_STMT) {
            then_block = cloneASTNode(branch_expr, arena_);
            BlockGuard bguard(*this, &then_block->as.block_stmt);
            DynamicArray<ASTNode*>* stmts = then_block->as.block_stmt.statements;
            if (stmts->length() > 0) {
                (*stmts)[stmts->length() - 1] = createYieldingStmt((*stmts)[stmts->length() - 1], temp_ident, loc);
            }
        } else {
            void* stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
            DynamicArray<ASTNode*>* stmts = new (stmts_mem) DynamicArray<ASTNode*>(*arena_);
            ASTNode* block_node = createBlock(stmts, loc);
            BlockGuard bguard(*this, &block_node->as.block_stmt);
            stmts->append(createYieldingStmt(branch_expr, temp_ident, loc));
            then_block = block_node;
        }
    }

    ASTNode* else_block;
    {
        ASTNode* branch_expr = if_expr->else_expr;
        if (branch_expr->type == NODE_BLOCK_STMT) {
            else_block = cloneASTNode(branch_expr, arena_);
            BlockGuard bguard(*this, &else_block->as.block_stmt);
            DynamicArray<ASTNode*>* stmts = else_block->as.block_stmt.statements;
            if (stmts->length() > 0) {
                (*stmts)[stmts->length() - 1] = createYieldingStmt((*stmts)[stmts->length() - 1], temp_ident, loc);
            }
        } else {
            void* stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
            DynamicArray<ASTNode*>* stmts = new (stmts_mem) DynamicArray<ASTNode*>(*arena_);
            ASTNode* block_node = createBlock(stmts, loc);
            BlockGuard bguard(*this, &block_node->as.block_stmt);
            stmts->append(createYieldingStmt(branch_expr, temp_ident, loc));
            else_block = block_node;
        }
    }

    ASTNode* if_stmt_node = createIfStmt(if_expr->condition, then_block, else_block, loc);
    ASTIfStmtNode* if_stmt = if_stmt_node->as.if_stmt;

    if (if_expr->capture_name && if_expr->capture_sym) {
        if_stmt->capture_name = if_expr->capture_name;
        Symbol* new_sym = (Symbol*)arena_->alloc(sizeof(Symbol));
        plat_memcpy(new_sym, if_expr->capture_sym, sizeof(Symbol));
        new_sym->flags |= SYMBOL_FLAG_LOCAL | SYMBOL_FLAG_CONST;
        if_stmt->capture_sym = new_sym;

        updateCaptureSymbols(then_block, if_expr->capture_sym, new_sym);
    }

    transformNode(&then_block, if_stmt_node);
    transformNode(&else_block, if_stmt_node);

    return if_stmt_node;
}

ASTNode* ControlFlowLifter::lowerSwitchExpr(ASTNode* node, Symbol* temp_sym) {
    ASTSwitchExprNode* sw_expr = node->as.switch_expr;
    SourceLocation loc = node->loc;

    ASTNode* temp_ident = createIdentifier(temp_sym->name, loc, temp_sym);
    temp_ident->resolved_type = node->resolved_type;

    void* prongs_mem = arena_->alloc(sizeof(DynamicArray<ASTSwitchStmtProngNode*>));
    DynamicArray<ASTSwitchStmtProngNode*>* prongs = new (prongs_mem) DynamicArray<ASTSwitchStmtProngNode*>(*arena_);

    ASTNode* switch_stmt_node = createSwitchStmt(sw_expr->expression, prongs, loc);

    for (size_t i = 0; i < sw_expr->prongs->length(); ++i) {
        ASTSwitchProngNode* orig_prong = (*sw_expr->prongs)[i];
        ASTSwitchStmtProngNode* new_prong = (ASTSwitchStmtProngNode*)arena_->alloc(sizeof(ASTSwitchStmtProngNode));
        plat_memset(new_prong, 0, sizeof(ASTSwitchStmtProngNode));

        new_prong->items = orig_prong->items;
        new_prong->is_else = orig_prong->is_else;
        new_prong->capture_name = orig_prong->capture_name;
        new_prong->capture_sym = orig_prong->capture_sym;

        ASTNode* body_node = orig_prong->body;
        if (body_node->type == NODE_BLOCK_STMT) {
            body_node = cloneASTNode(body_node, arena_);
            BlockGuard bguard(*this, &body_node->as.block_stmt);
            DynamicArray<ASTNode*>* stmts = body_node->as.block_stmt.statements;
            if (stmts->length() > 0) {
                (*stmts)[stmts->length() - 1] = createYieldingStmt((*stmts)[stmts->length() - 1], temp_ident, loc);
            }
            new_prong->body = body_node;
        } else {
            void* stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
            DynamicArray<ASTNode*>* stmts = new (stmts_mem) DynamicArray<ASTNode*>(*arena_);
            ASTNode* block_node = createBlock(stmts, loc);
            BlockGuard bguard(*this, &block_node->as.block_stmt);
            stmts->append(createYieldingStmt(body_node, temp_ident, loc));
            new_prong->body = block_node;
        }

        transformNode(&new_prong->body, switch_stmt_node);

        if (new_prong->capture_name && new_prong->capture_sym) {
            Symbol* new_sym = (Symbol*)arena_->alloc(sizeof(Symbol));
            plat_memcpy(new_sym, new_prong->capture_sym, sizeof(Symbol));
            new_sym->flags |= SYMBOL_FLAG_LOCAL | SYMBOL_FLAG_CONST;
            Symbol* old_capture_sym = new_prong->capture_sym;
            new_prong->capture_sym = new_sym;

            updateCaptureSymbols(new_prong->body, old_capture_sym, new_sym);
        }

        prongs->append(new_prong);
    }

    return switch_stmt_node;
}

void ControlFlowLifter::lowerTryExpr(ASTNode* node, Symbol* temp_sym, DynamicArray<ASTNode*>& out_stmts, bool needs_wrapping) {
    ASTTryExprNode& try_expr = node->as.try_expr;
    SourceLocation loc = node->loc;
    Type* error_union_type = try_expr.expression->resolved_type;

    const char* res_name = generateTempName("try_res");
    ASTNode* res_decl = createVarDecl(res_name, error_union_type, try_expr.expression, true);
    out_stmts.append(res_decl);

    ASTNode* res_ident = createIdentifier(res_name, loc, res_decl->as.var_decl->symbol);
    res_ident->resolved_type = error_union_type;

    ASTNode* is_error_access = createMemberAccess(res_ident, "is_error", loc);
    is_error_access->resolved_type = get_g_type_bool();

    if (needs_wrapping && current_fn_return_type_) {
        ASTNode* temp_ident = createIdentifier(temp_sym->name, loc, temp_sym);
        temp_ident->resolved_type = current_fn_return_type_;

        void* err_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
        DynamicArray<ASTNode*>* err_stmts = new (err_stmts_mem) DynamicArray<ASTNode*>(*arena_);
        ASTNode* then_block_node = createBlock(err_stmts, loc);
        BlockGuard bguard(*this, &then_block_node->as.block_stmt);

        ASTNode* is_error_assign = createAssignment(createMemberAccess(temp_ident, "is_error", loc), createIntegerLiteral(1, get_g_type_i32(), loc), loc);
        err_stmts->append(createExpressionStmt(is_error_assign, loc));

        ASTNode* src_err;
        ASTNode* dest_err;
        if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
            src_err = createMemberAccess(createMemberAccess(res_ident, "data", loc), "err", loc);
        } else {
            src_err = createMemberAccess(res_ident, "err", loc);
        }
        if (current_fn_return_type_->as.error_union.payload->kind != TYPE_VOID) {
            dest_err = createMemberAccess(createMemberAccess(temp_ident, "data", loc), "err", loc);
        } else {
            dest_err = createMemberAccess(temp_ident, "err", loc);
        }
        dest_err->resolved_type = src_err->resolved_type = get_g_type_i32();
        err_stmts->append(createExpressionStmt(createAssignment(dest_err, src_err, loc), loc));

        ASTNode* then_block = then_block_node;

        void* succ_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
        DynamicArray<ASTNode*>* succ_stmts = new (succ_stmts_mem) DynamicArray<ASTNode*>(*arena_);
        ASTNode* else_block_node = createBlock(succ_stmts, loc);
        BlockGuard bguard_else(*this, &else_block_node->as.block_stmt);

        ASTNode* is_error_succ_assign = createAssignment(createMemberAccess(temp_ident, "is_error", loc), createIntegerLiteral(0, get_g_type_i32(), loc), loc);
        succ_stmts->append(createExpressionStmt(is_error_succ_assign, loc));

        if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
             ASTNode* src_payload = createMemberAccess(createMemberAccess(res_ident, "data", loc), "payload", loc);
             ASTNode* dest_payload = createMemberAccess(createMemberAccess(temp_ident, "data", loc), "payload", loc);
             dest_payload->resolved_type = src_payload->resolved_type = error_union_type->as.error_union.payload;
             succ_stmts->append(createExpressionStmt(createAssignment(dest_payload, src_payload, loc), loc));
        }

        ASTNode* else_block = else_block_node;

        out_stmts.append(createIfStmt(is_error_access, then_block, else_block, loc));
    } else {
        Type* ret_type = current_fn_return_type_ ? current_fn_return_type_ : get_g_type_void();

        ASTNode* ret_val;
        if (areTypesEqual(ret_type, error_union_type)) {
            ret_val = res_ident;
        } else {
            ASTNode* err_access;
            if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
                ASTNode* data_access = createMemberAccess(res_ident, "data", loc);
                data_access->resolved_type = error_union_type;
                err_access = createMemberAccess(data_access, "err", loc);
            } else {
                err_access = createMemberAccess(res_ident, "err", loc);
            }
            err_access->resolved_type = get_g_type_i32();
            
            void* array_mem = arena_->alloc(sizeof(DynamicArray<ASTNamedInitializer*>));
            DynamicArray<ASTNamedInitializer*>* fields = new (array_mem) DynamicArray<ASTNamedInitializer*>(*arena_);
            
            if (ret_type->as.error_union.payload->kind == TYPE_VOID) {
                ASTNamedInitializer* err_init = (ASTNamedInitializer*)arena_->alloc(sizeof(ASTNamedInitializer));
                err_init->field_name = "err";
                err_init->value = err_access;
                err_init->loc = loc;
                fields->append(err_init);
            } else {
                void* inner_array_mem = arena_->alloc(sizeof(DynamicArray<ASTNamedInitializer*>));
                DynamicArray<ASTNamedInitializer*>* inner_fields = new (inner_array_mem) DynamicArray<ASTNamedInitializer*>(*arena_);
                
                ASTNamedInitializer* err_init = (ASTNamedInitializer*)arena_->alloc(sizeof(ASTNamedInitializer));
                err_init->field_name = "err";
                err_init->value = err_access;
                err_init->loc = loc;
                inner_fields->append(err_init);

                ASTStructInitializerNode* inner_init = (ASTStructInitializerNode*)arena_->alloc(sizeof(ASTStructInitializerNode));
                inner_init->type_expr = NULL;
                inner_init->fields = inner_fields;

                ASTNode* inner_init_node = createNodeAt(NODE_STRUCT_INITIALIZER, loc);
                inner_init_node->as.struct_initializer = inner_init;
                inner_init_node->resolved_type = get_g_type_anytype(); 

                ASTNamedInitializer* data_init = (ASTNamedInitializer*)arena_->alloc(sizeof(ASTNamedInitializer));
                data_init->field_name = "data";
                data_init->value = inner_init_node;
                data_init->loc = loc;
                fields->append(data_init);
            }

            ASTNamedInitializer* is_err_init = (ASTNamedInitializer*)arena_->alloc(sizeof(ASTNamedInitializer));
            is_err_init->field_name = "is_error";
            is_err_init->value = createIntegerLiteral(1, get_g_type_i32(), loc);
            is_err_init->loc = loc;
            fields->append(is_err_init);

            ASTStructInitializerNode* init = (ASTStructInitializerNode*)arena_->alloc(sizeof(ASTStructInitializerNode));
            init->type_expr = NULL;
            init->fields = fields;

            ret_val = createNodeAt(NODE_STRUCT_INITIALIZER, loc);
            ret_val->as.struct_initializer = init;
            ret_val->resolved_type = ret_type;
        }

        ASTNode* ret_stmt = createReturn(ret_val, loc);
        void* ret_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
        DynamicArray<ASTNode*>* ret_stmts = new (ret_stmts_mem) DynamicArray<ASTNode*>(*arena_);
        ASTNode* then_block_node = createBlock(ret_stmts, loc);
        BlockGuard bguard(*this, &then_block_node->as.block_stmt);
        ret_stmts->append(ret_stmt);
        ASTNode* then_block = then_block_node;

        ASTNode* if_stmt = createIfStmt(is_error_access, then_block, NULL, loc);
        out_stmts.append(if_stmt);

        if (node->resolved_type && node->resolved_type->kind != TYPE_VOID) {
            ASTNode* temp_ident = createIdentifier(temp_sym->name, loc, temp_sym);
            temp_ident->resolved_type = node->resolved_type;

            ASTNode* payload_access;
            if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
                ASTNode* data_access = createMemberAccess(res_ident, "data", loc);
                data_access->resolved_type = error_union_type;
                payload_access = createMemberAccess(data_access, "payload", loc);
            } else {
                payload_access = createIntegerLiteral(0, get_g_type_void(), loc);
            }
            payload_access->resolved_type = node->resolved_type;

            out_stmts.append(createYieldingStmt(payload_access, temp_ident, loc));
        }
    }
}

void ControlFlowLifter::lowerCatchExpr(ASTNode* node, Symbol* temp_sym, DynamicArray<ASTNode*>& out_stmts) {
    ASTCatchExprNode* catch_expr = node->as.catch_expr;
    SourceLocation loc = node->loc;
    Type* error_union_type = catch_expr->payload->resolved_type;

    ASTNode* temp_ident = createIdentifier(temp_sym->name, loc, temp_sym);
    temp_ident->resolved_type = node->resolved_type;

    const char* res_name = generateTempName("catch_res");
    ASTNode* res_decl = createVarDecl(res_name, error_union_type, catch_expr->payload, true);
    out_stmts.append(res_decl);

    ASTNode* res_ident = createIdentifier(res_name, loc, res_decl->as.var_decl->symbol);
    res_ident->resolved_type = error_union_type;

    ASTNode* is_error_access = createMemberAccess(res_ident, "is_error", loc);
    is_error_access->resolved_type = get_g_type_bool();

    void* catch_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    DynamicArray<ASTNode*>* catch_stmts = new (catch_stmts_mem) DynamicArray<ASTNode*>(*arena_);
    ASTNode* catch_lower_block = createBlock(catch_stmts, loc);

    ASTNode* catch_body = catch_expr->else_expr;
    if (catch_body->type == NODE_BLOCK_STMT) {
        catch_body = cloneASTNode(catch_body, arena_);
        DynamicArray<ASTNode*>* inner_stmts = catch_body->as.block_stmt.statements;
        if (inner_stmts->length() > 0) {
            (*inner_stmts)[inner_stmts->length() - 1] = createYieldingStmt((*inner_stmts)[inner_stmts->length() - 1], temp_ident, loc);
        }
    } else {
        catch_body = createYieldingStmt(catch_body, temp_ident, loc);
    }

    if (catch_expr->error_name) {
        ASTNode* err_access;
        if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
            ASTNode* data_access = createMemberAccess(res_ident, "data", loc);
            data_access->resolved_type = error_union_type;
            err_access = createMemberAccess(data_access, "err", loc);
        } else {
            err_access = createMemberAccess(res_ident, "err", loc);
        }
        err_access->resolved_type = get_g_type_i32();

        const char* capture_name = catch_expr->error_name;
        Symbol* new_sym = createSymbol(capture_name, get_g_type_i32(), true);

        ASTNode* err_decl = createVarDecl(NULL, get_g_type_i32(), err_access, true);
        err_decl->as.var_decl->name = capture_name;
        err_decl->as.var_decl->symbol = new_sym;
        catch_stmts->append(err_decl);

        updateCaptureSymbols(catch_body, catch_expr->capture_sym, new_sym);
    }

    catch_stmts->append(catch_body);

    transformNode(&catch_lower_block, NULL);

    ASTNode* then_block = catch_lower_block;

    ASTNode* payload_access;
    if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
        ASTNode* data_access = createMemberAccess(res_ident, "data", loc);
        data_access->resolved_type = error_union_type;
        payload_access = createMemberAccess(data_access, "payload", loc);
    } else {
        payload_access = createIntegerLiteral(0, get_g_type_void(), loc);
    }
    payload_access->resolved_type = node->resolved_type;
    void* succ_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    DynamicArray<ASTNode*>* succ_stmts = new (succ_stmts_mem) DynamicArray<ASTNode*>(*arena_);
    ASTNode* else_block_node = createBlock(succ_stmts, loc);
    BlockGuard bguard_else(*this, &else_block_node->as.block_stmt);
    succ_stmts->append(createYieldingStmt(payload_access, temp_ident, loc));
    ASTNode* else_block = else_block_node;

    ASTNode* if_stmt = createIfStmt(is_error_access, then_block, else_block, loc);
    out_stmts.append(if_stmt);
}

void ControlFlowLifter::lowerOrelseExpr(ASTNode* node, Symbol* temp_sym, DynamicArray<ASTNode*>& out_stmts) {
    ASTOrelseExprNode* orelse = node->as.orelse_expr;
    SourceLocation loc = node->loc;
    Type* optional_type = orelse->payload->resolved_type;

    ASTNode* temp_ident = createIdentifier(temp_sym->name, loc, temp_sym);
    temp_ident->resolved_type = node->resolved_type;

    const char* res_name = generateTempName("orelse_res");
    ASTNode* res_decl = createVarDecl(res_name, optional_type, orelse->payload, true);
    out_stmts.append(res_decl);

    ASTNode* res_ident = createIdentifier(res_name, loc, res_decl->as.var_decl->symbol);
    res_ident->resolved_type = optional_type;

    ASTNode* has_value_access = createMemberAccess(res_ident, "has_value", loc);
    has_value_access->resolved_type = get_g_type_bool();

    ASTNode* value_access;
    if (optional_type->as.optional.payload->kind != TYPE_VOID) {
        value_access = createMemberAccess(res_ident, "value", loc);
    } else {
        value_access = createIntegerLiteral(0, get_g_type_void(), loc);
    }
    value_access->resolved_type = node->resolved_type;
    void* has_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    DynamicArray<ASTNode*>* has_stmts = new (has_stmts_mem) DynamicArray<ASTNode*>(*arena_);
    ASTNode* then_block_node = createBlock(has_stmts, loc);
    BlockGuard bguard(*this, &then_block_node->as.block_stmt);
    has_stmts->append(createExpressionStmt(createAssignment(temp_ident, value_access, loc), loc));
    ASTNode* then_block = then_block_node;

    ASTNode* else_block;
    {
        ASTNode* branch_expr = orelse->else_expr;
        if (branch_expr->type == NODE_BLOCK_STMT) {
            else_block = cloneASTNode(branch_expr, arena_);
            BlockGuard bguard_else(*this, &else_block->as.block_stmt);
            DynamicArray<ASTNode*>* stmts = else_block->as.block_stmt.statements;
            if (stmts->length() > 0) {
                (*stmts)[stmts->length() - 1] = createYieldingStmt((*stmts)[stmts->length() - 1], temp_ident, loc);
            }
        } else {
            void* stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
            DynamicArray<ASTNode*>* stmts = new (stmts_mem) DynamicArray<ASTNode*>(*arena_);
            ASTNode* block_node = createBlock(stmts, loc);
            BlockGuard bguard_else(*this, &block_node->as.block_stmt);
            stmts->append(createYieldingStmt(branch_expr, temp_ident, loc));
            else_block = block_node;
        }
    }

    ASTNode* if_stmt = createIfStmt(has_value_access, then_block, else_block, loc);

    transformNode(&then_block, if_stmt);
    transformNode(&else_block, if_stmt);

    out_stmts.append(if_stmt);
}

ASTNode* ControlFlowLifter::createYieldingStmt(ASTNode* expr, ASTNode* temp_ident, SourceLocation loc) {
    if (!expr) return NULL;
    if (allPathsExit(expr)) {
        if (expr->type == NODE_EXPRESSION_STMT) return expr;
        if (expr->type == NODE_RETURN_STMT || expr->type == NODE_BREAK_STMT ||
            expr->type == NODE_CONTINUE_STMT || expr->type == NODE_UNREACHABLE) {
            return expr;
        }
        return createExpressionStmt(expr, loc);
    }

    if (expr->resolved_type && expr->resolved_type->kind == TYPE_VOID) {
        if (expr->type == NODE_EXPRESSION_STMT) return expr;
        return createExpressionStmt(expr, loc);
    }
    return createExpressionStmt(createAssignment(temp_ident, expr, loc), loc);
}

int ControlFlowLifter::findStatementIndex(ASTBlockStmtNode* block, ASTNode* stmt) {
    if (!block || !block->statements || !stmt) return -1;
    for (size_t i = 0; i < block->statements->length(); ++i) {
        if ((*block->statements)[i] == stmt) {
            return (int)i;
        }
    }
    return -1;
}

void ControlFlowLifter::liftNode(ASTNode** node_slot, ASTNode* parent, const char* prefix, bool needs_wrapping) {
    RETR_UNUSED(parent);
    ASTNode* node = *node_slot;
    if (!node) return;

    // Only lift inside functions
    if (fn_stack_.length() == 0) {
        return;
    }

    const char* temp_name = generateTempName(prefix);

    ASTNode* var_decl_node = NULL;
    Type* temp_type = node->resolved_type;
    if (needs_wrapping && current_fn_return_type_) {
        temp_type = current_fn_return_type_;
    }

    Symbol* temp_sym = NULL;
    if (temp_type && temp_type->kind != TYPE_VOID) {
        ASTNode* initializer = NULL;
        if (node->type == NODE_STRUCT_INITIALIZER || node->type == NODE_TUPLE_LITERAL) {
            initializer = node;
        } else if (node->type == NODE_CATCH_EXPR) {
            if (isAggregateType(temp_type)) {
                initializer = createNodeAt(NODE_STRUCT_INITIALIZER, node->loc);
                initializer->as.struct_initializer = (ASTStructInitializerNode*)arena_->alloc(sizeof(ASTStructInitializerNode));
                plat_memset(initializer->as.struct_initializer, 0, sizeof(ASTStructInitializerNode));
                initializer->as.struct_initializer->fields = new (arena_->alloc(sizeof(DynamicArray<ASTNamedInitializer*>))) DynamicArray<ASTNamedInitializer*>(*arena_);
            } else {
                initializer = createIntegerLiteral(0, temp_type, node->loc);
            }
        }
        var_decl_node = createVarDecl(temp_name, temp_type, initializer, false);
        temp_sym = var_decl_node->as.var_decl->symbol;
    } else {
        temp_sym = createSymbol(temp_name, get_g_type_void(), false);
    }

    DynamicArray<ASTNode*> lowering_stmts(*arena_);

    bool is_aggregate = (node->type == NODE_STRUCT_INITIALIZER || node->type == NODE_TUPLE_LITERAL);

    if (!is_aggregate) {
        switch (node->type) {
            case NODE_IF_EXPR:
                lowering_stmts.append(lowerIfExpr(node, temp_sym));
                break;
            case NODE_SWITCH_EXPR:
                lowering_stmts.append(lowerSwitchExpr(node, temp_sym));
                break;
            case NODE_TRY_EXPR:
                lowerTryExpr(node, temp_sym, lowering_stmts, needs_wrapping);
                break;
            case NODE_CATCH_EXPR:
                lowerCatchExpr(node, temp_sym, lowering_stmts);
                break;
            case NODE_ORELSE_EXPR:
                lowerOrelseExpr(node, temp_sym, lowering_stmts);
                break;
            default:
                error_handler_->report(ERR_INTERNAL_ERROR, node->loc, "Unknown expression for lifting", NULL);
                plat_abort();
        }
    }

    if (block_stack_.length() > 0) {
        ASTBlockStmtNode* current_block = block_stack_.back();
        int insert_idx = -1;
        if (stmt_stack_.length() > 0) {
            insert_idx = findStatementIndex(current_block, stmt_stack_.back());
        }

        if (insert_idx == -1) {
            insert_idx = (int)current_block->statements->length();
        }

        size_t offset = 0;
        if (var_decl_node) {
            current_block->statements->insert((size_t)insert_idx, var_decl_node);
            offset = 1;
        }
        for (size_t i = 0; i < lowering_stmts.length(); ++i) {
            current_block->statements->insert((size_t)insert_idx + offset + i, lowering_stmts[i]);
        }
    }

    ASTNode* ident_node = createIdentifier(temp_name, node->loc, temp_sym);
    ident_node->resolved_type = temp_type;

    *node_slot = ident_node;
}

void ControlFlowLifter::formatSourceLocation(SourceLocation loc, char* buf, size_t buf_size) {
    if (buf_size == 0) return;
    buf[0] = '\0';

    char* cur = buf;
    size_t rem = buf_size;

    if (unit_ && loc.file_id != 0) {
        const SourceFile* file = unit_->getSourceManager().getFile(loc.file_id);
        if (file) {
            safe_append(cur, rem, file->filename);
            safe_append(cur, rem, ":");
        }
    }

    char num_buf[32];
    plat_i64_to_string(loc.line, num_buf, sizeof(num_buf));
    safe_append(cur, rem, num_buf);
    safe_append(cur, rem, ":");
    plat_i64_to_string(loc.column, num_buf, sizeof(num_buf));
    safe_append(cur, rem, num_buf);
}

const char* ControlFlowLifter::getPrefixForType(NodeType type) {
    switch (type) {
        case NODE_IF_EXPR:           return "if";
        case NODE_SWITCH_EXPR:       return "switch";
        case NODE_TRY_EXPR:          return "try";
        case NODE_CATCH_EXPR:        return "catch";
        case NODE_ORELSE_EXPR:       return "orelse";
        case NODE_STRUCT_INITIALIZER: return "agg";
        case NODE_TUPLE_LITERAL:      return "tup";
        default:                     return "tmp";
    }
}

const char* ControlFlowLifter::generateTempName(const char* prefix) {
    char buf[64];
    char num_buf[16];
    char depth_buf[16];
    plat_i64_to_string(++tmp_counter_, num_buf, sizeof(num_buf));
    plat_i64_to_string(depth_, depth_buf, sizeof(depth_buf));

    plat_strcpy(buf, "__tmp_");
    plat_strcat(buf, prefix);
    plat_strcat(buf, "_");
    plat_strcat(buf, depth_buf);
    plat_strcat(buf, "_");
    plat_strcat(buf, num_buf);

    if (plat_strlen(buf) > 63) {
        error_handler_->report(ERR_INTERNAL_ERROR, SourceLocation(), "Temp name too long", buf);
        plat_abort();
    }

    return interner_->intern(buf);
}

void ControlFlowLifter::validateLifting(Module* mod) {
    if (!debug_mode_) return;

#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[LIFTER] Validation: %d temp variables registered in module %s\n",
                     (int)registered_temps_.length(), mod->name);
#endif

    for (size_t i = 0; i < registered_temps_.length(); ++i) {
        for (size_t j = i + 1; j < registered_temps_.length(); ++j) {
            if (plat_strcmp(registered_temps_[i], registered_temps_[j]) == 0) {
                error_handler_->report(ERR_INTERNAL_ERROR, SourceLocation(),
                                       "Duplicate temp variable name",
                                       registered_temps_[i]);
            }
        }
    }
}

void ControlFlowLifter::validateASTIntegrity(ASTNode* node, const char* context) {
    if (!debug_mode_ || !node) return;

    if (node->type == NODE_IDENTIFIER ||
        node->type == NODE_BINARY_OP ||
        node->type == NODE_FUNCTION_CALL) {
        if (!node->resolved_type) {
            char loc_buf[128];
            formatSourceLocation(node->loc, loc_buf, sizeof(loc_buf));
#ifdef Z98_ENABLE_DEBUG_LOGS
            plat_printf_debug("[LIFTER] WARNING: Node type=%d has NULL resolved_type at %s context=%s\n",
                             (int)node->type, loc_buf, context);
#endif
        }
    }

    struct ValidateVisitor : ChildVisitor {
        ControlFlowLifter* lifter;
        const char* context;
        ValidateVisitor(ControlFlowLifter* l, const char* c) : lifter(l), context(c) {}
        void visitChild(ASTNode** child_slot) {
            if (*child_slot) {
                lifter->validateASTIntegrity(*child_slot, context);
            }
        }
    };

    ValidateVisitor visitor(this, context);
    forEachChild(node, visitor);
}
