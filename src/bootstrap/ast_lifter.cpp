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
}

ControlFlowLifter::BlockGuard::~BlockGuard() {
    lifter_.block_stack_.pop_back();
}

ControlFlowLifter::ParentGuard::ParentGuard(ControlFlowLifter& l, ASTNode* node) : lifter_(l) {
    lifter_.parent_stack_.append(node);
}

ControlFlowLifter::ParentGuard::~ParentGuard() {
    lifter_.parent_stack_.pop_back();
}

ControlFlowLifter::FnGuard::FnGuard(ControlFlowLifter& l, ASTFnDeclNode* fn) : lifter_(l) {
    lifter_.fn_stack_.append(fn);
}

ControlFlowLifter::FnGuard::~FnGuard() {
    lifter_.fn_stack_.pop_back();
}

ControlFlowLifter::ControlFlowLifter(ArenaAllocator* arena, StringInterner* interner, ErrorHandler* error_handler)
    : arena_(arena), interner_(interner), error_handler_(error_handler),
      tmp_counter_(0), depth_(0), MAX_LIFTING_DEPTH(200),
      stmt_stack_(*arena), block_stack_(*arena), parent_stack_(*arena), fn_stack_(*arena) {}

void ControlFlowLifter::lift(CompilationUnit* unit) {
    const DynamicArray<Module*>& modules = unit->getModules();
    for (size_t i = 0; i < modules.length(); ++i) {
        Module* mod = modules[i];
        if (!mod->ast_root) continue;

        // Reset per-module counter
        tmp_counter_ = 0;
        depth_ = 0;

        transformNode(&mod->ast_root, NULL);
    }
}

void ControlFlowLifter::transformNode(ASTNode** node_slot, ASTNode* parent) {
    ASTNode* node = *node_slot;
    if (!node) return;

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
                    node->type == NODE_DEFER_STMT || node->type == NODE_ERRDEFER_STMT);

    bool is_block = (node->type == NODE_BLOCK_STMT);
    bool is_fn = (node->type == NODE_FN_DECL);

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
            Inner::process(this, node);
        } else if (is_stmt) {
            StmtGuard sguard(*this, node);
            Inner::process(this, node);
        } else if (is_block) {
            BlockGuard bguard(*this, &node->as.block_stmt);
            Inner::process(this, node);
        } else if (is_fn) {
            FnGuard fguard(*this, node->as.fn_decl);
            Inner::process(this, node);
        } else {
            Inner::process(this, node);
        }
    }

    // Decision: does THIS node need lifting?
    if (needsLifting(node, parent)) {
        liftNode(node_slot, parent, getPrefixForType(node->type));
    }

    depth_--;
}

bool ControlFlowLifter::needsLifting(ASTNode* node, ASTNode* parent) {
    if (!node) return false;
    if (!parent) return false;

    // Only control-flow expressions can be lifted
    if (!isControlFlowExpr(node->type)) return false;

    // Skip parentheses to get the real semantic parent
    const ASTNode* effective_parent = skipParens(parent);
    if (!effective_parent) return false; // Root is always safe

    // Any control‑flow expression must be lifted for C89 compatibility.
    // We use a switch as requested for clarity and future expansion.
    switch (effective_parent->type) {
        case NODE_EXPRESSION_STMT:
        case NODE_RETURN_STMT:
        case NODE_VAR_DECL:
        case NODE_ASSIGNMENT:
        case NODE_COMPOUND_ASSIGNMENT:
        case NODE_BINARY_OP:
        case NODE_UNARY_OP:
        case NODE_FUNCTION_CALL:
        case NODE_ARRAY_ACCESS:
        case NODE_ARRAY_SLICE:
        case NODE_MEMBER_ACCESS:
        case NODE_STRUCT_INITIALIZER:
        case NODE_TUPLE_LITERAL:
        case NODE_IF_EXPR:
        case NODE_SWITCH_EXPR:
        case NODE_TRY_EXPR:
        case NODE_CATCH_EXPR:
        case NODE_ORELSE_EXPR:
        case NODE_IF_STMT:
        case NODE_WHILE_STMT:
        case NODE_FOR_STMT:
        case NODE_PAREN_EXPR: // already skipped, but left for completeness
            return true;
        default:
            return true; // Conservative: lift if unsure
    }
}

const ASTNode* ControlFlowLifter::skipParens(const ASTNode* parent) {
    if (!parent) return NULL;
    const ASTNode* cur = parent;

    // We expect the parent to be at the top of the stack when needsLifting is called
    // (because ParentGuard for 'node' was just popped).
    // If 'cur' is a Paren, we need to go higher in the stack.

    int idx = (int)parent_stack_.length() - 1;
    // Verify top of stack is indeed our parent
    if (idx < 0 || parent_stack_[idx] != parent) {
        // Fallback: search for it if stack isn't what we expect
        idx = -1;
        for (int i = (int)parent_stack_.length() - 1; i >= 0; --i) {
            if (parent_stack_[i] == parent) {
                idx = i;
                break;
            }
        }
    }

    if (idx < 0) return parent; // Should not happen

    while (cur && cur->type == NODE_PAREN_EXPR) {
        if (idx > 0) {
            idx--;
            cur = parent_stack_[idx];
        } else {
            return NULL; // Reached root and it was a paren
        }
    }

    return cur;
}

ASTNode* ControlFlowLifter::createVarDecl(const char* name, Type* type, ASTNode* init, bool is_const) {
    ASTVarDeclNode* var_decl_data = (ASTVarDeclNode*)arena_->alloc(sizeof(ASTVarDeclNode));
    plat_memset(var_decl_data, 0, sizeof(ASTVarDeclNode));
    var_decl_data->name = name;
    var_decl_data->name_loc = init ? init->loc : SourceLocation();
    var_decl_data->initializer = init;
    var_decl_data->is_const = is_const;
    var_decl_data->is_mut = !is_const;

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(node, 0, sizeof(ASTNode));
    node->type = NODE_VAR_DECL;
    node->loc = var_decl_data->name_loc;
    node->resolved_type = type;
    node->as.var_decl = var_decl_data;
    return node;
}

ASTNode* ControlFlowLifter::createIdentifier(const char* name, SourceLocation loc) {
    ASTNode* ident_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(ident_node, 0, sizeof(ASTNode));
    ident_node->type = NODE_IDENTIFIER;
    ident_node->loc = loc;
    ident_node->as.identifier.name = name;
    return ident_node;
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

ASTNode* ControlFlowLifter::lowerIfExpr(ASTNode* node, const char* temp_name) {
    ASTIfExprNode* if_expr = node->as.if_expr;
    SourceLocation loc = node->loc;

    ASTNode* temp_ident = createIdentifier(temp_name, loc);
    temp_ident->resolved_type = node->resolved_type;

    // Then branch
    ASTNode* then_block;
    if (if_expr->then_expr->type == NODE_BLOCK_STMT) {
        then_block = cloneASTNode(if_expr->then_expr, arena_);
        DynamicArray<ASTNode*>* stmts = then_block->as.block_stmt.statements;
        if (stmts->length() > 0) {
            ASTNode* last = (*stmts)[stmts->length() - 1];
            (*stmts)[stmts->length() - 1] = createYieldingStmt(last, temp_ident, loc);
        }
    } else {
        void* then_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
        DynamicArray<ASTNode*>* then_stmts = new (then_stmts_mem) DynamicArray<ASTNode*>(*arena_);
        then_stmts->append(createYieldingStmt(if_expr->then_expr, temp_ident, loc));
        then_block = createBlock(then_stmts, loc);
    }

    // Else branch
    ASTNode* else_block;
    if (if_expr->else_expr->type == NODE_BLOCK_STMT) {
        else_block = cloneASTNode(if_expr->else_expr, arena_);
        DynamicArray<ASTNode*>* stmts = else_block->as.block_stmt.statements;
        if (stmts->length() > 0) {
            ASTNode* last = (*stmts)[stmts->length() - 1];
            (*stmts)[stmts->length() - 1] = createYieldingStmt(last, temp_ident, loc);
        }
    } else {
        void* else_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
        DynamicArray<ASTNode*>* else_stmts = new (else_stmts_mem) DynamicArray<ASTNode*>(*arena_);
        else_stmts->append(createYieldingStmt(if_expr->else_expr, temp_ident, loc));
        else_block = createBlock(else_stmts, loc);
    }

    return createIfStmt(if_expr->condition, then_block, else_block, loc);
}

ASTNode* ControlFlowLifter::lowerSwitchExpr(ASTNode* node, const char* temp_name) {
    ASTSwitchExprNode* sw_expr = node->as.switch_expr;
    SourceLocation loc = node->loc;

    ASTNode* temp_ident = createIdentifier(temp_name, loc);
    temp_ident->resolved_type = node->resolved_type;

    void* prongs_mem = arena_->alloc(sizeof(DynamicArray<ASTSwitchStmtProngNode*>));
    DynamicArray<ASTSwitchStmtProngNode*>* prongs = new (prongs_mem) DynamicArray<ASTSwitchStmtProngNode*>(*arena_);

    for (size_t i = 0; i < sw_expr->prongs->length(); ++i) {
        ASTSwitchProngNode* orig_prong = (*sw_expr->prongs)[i];
        ASTSwitchStmtProngNode* new_prong = (ASTSwitchStmtProngNode*)arena_->alloc(sizeof(ASTSwitchStmtProngNode));
        plat_memset(new_prong, 0, sizeof(ASTSwitchStmtProngNode));

        new_prong->items = orig_prong->items;
        new_prong->is_else = orig_prong->is_else;
        new_prong->capture_name = orig_prong->capture_name;
        new_prong->capture_sym = orig_prong->capture_sym;

        if (orig_prong->body->type == NODE_BLOCK_STMT) {
            new_prong->body = cloneASTNode(orig_prong->body, arena_);
            DynamicArray<ASTNode*>* stmts = new_prong->body->as.block_stmt.statements;
            if (stmts->length() > 0) {
                ASTNode* last = (*stmts)[stmts->length() - 1];
                (*stmts)[stmts->length() - 1] = createYieldingStmt(last, temp_ident, loc);
            }
        } else {
            new_prong->body = createYieldingStmt(orig_prong->body, temp_ident, loc);
        }

        prongs->append(new_prong);
    }

    return createSwitchStmt(sw_expr->expression, prongs, loc);
}

void ControlFlowLifter::lowerTryExpr(ASTNode* node, const char* temp_name, DynamicArray<ASTNode*>& out_stmts) {
    ASTTryExprNode& try_expr = node->as.try_expr;
    SourceLocation loc = node->loc;
    Type* error_union_type = try_expr.expression->resolved_type;

    // 1. Create a variable to hold the error union result
    const char* res_name = generateTempName("try_res");
    ASTNode* res_decl = createVarDecl(res_name, error_union_type, try_expr.expression, true);
    out_stmts.append(res_decl);

    ASTNode* res_ident = createIdentifier(res_name, loc);
    res_ident->resolved_type = error_union_type;

    // 2. Check is_error
    ASTNode* is_error_access = createMemberAccess(res_ident, "is_error", loc);
    is_error_access->resolved_type = get_g_type_bool();

    // 3. Early return block
    // We need to return the error union with the error code.
    Type* ret_type = get_g_type_void();
    if (fn_stack_.length() > 0) {
        ASTFnDeclNode* current_fn = fn_stack_.back();
        if (current_fn->return_type) {
            ret_type = current_fn->return_type->resolved_type;
        }
    }

    ASTNode* ret_val = res_ident;
    if (ret_type->kind == TYPE_ERROR_UNION && error_union_type->kind == TYPE_ERROR_UNION) {
        // Simple case: both are error unions.
        // If they have same payload, we can just return res_ident.
        // Otherwise, we might need wrapping if we support implicit error union coercion.
        // For now, assume they are compatible enough for return if type checked.
    }

    ASTNode* ret_stmt = createReturn(ret_val, loc);
    void* ret_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    DynamicArray<ASTNode*>* ret_stmts = new (ret_stmts_mem) DynamicArray<ASTNode*>(*arena_);
    ret_stmts->append(ret_stmt);
    ASTNode* then_block = createBlock(ret_stmts, loc);

    ASTNode* if_stmt = createIfStmt(is_error_access, then_block, NULL, loc);
    out_stmts.append(if_stmt);

    // 4. Assign payload to temp_name
    ASTNode* temp_ident = createIdentifier(temp_name, loc);
    temp_ident->resolved_type = node->resolved_type;

    ASTNode* payload_access;
    if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
        ASTNode* data_access = createMemberAccess(res_ident, "data", loc);
        payload_access = createMemberAccess(data_access, "payload", loc);
    } else {
        payload_access = createIntegerLiteral(0, get_g_type_void(), loc);
    }
    payload_access->resolved_type = node->resolved_type;

    out_stmts.append(createYieldingStmt(payload_access, temp_ident, loc));
}

ASTNode* ControlFlowLifter::lowerCatchExpr(ASTNode* node, const char* temp_name) {
    ASTCatchExprNode* catch_expr = node->as.catch_expr;
    SourceLocation loc = node->loc;
    Type* error_union_type = catch_expr->payload->resolved_type;

    ASTNode* temp_ident = createIdentifier(temp_name, loc);
    temp_ident->resolved_type = node->resolved_type;

    // 1. Evaluate payload once (handled by C89Emitter::emitCatchExpr for now, but we should do it here)
    // Actually, we can just transform it to:
    // var res = payload;
    // if (res.is_error) { temp = else_expr; } else { temp = res.data.payload; }

    const char* res_name = generateTempName("catch_res");
    ASTNode* res_decl = createVarDecl(res_name, error_union_type, catch_expr->payload, true);

    ASTNode* res_ident = createIdentifier(res_name, loc);
    res_ident->resolved_type = error_union_type;

    ASTNode* is_error_access = createMemberAccess(res_ident, "is_error", loc);
    is_error_access->resolved_type = get_g_type_bool();

    // Catch branch (error)
    void* catch_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    DynamicArray<ASTNode*>* catch_stmts = new (catch_stmts_mem) DynamicArray<ASTNode*>(*arena_);
    if (catch_expr->error_name) {
        // Capture error: var err = res.data.err;
        ASTNode* err_access;
        if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
            ASTNode* data_access = createMemberAccess(res_ident, "data", loc);
            err_access = createMemberAccess(data_access, "err", loc);
        } else {
            err_access = createMemberAccess(res_ident, "err", loc);
        }
        err_access->resolved_type = get_g_type_i32(); // ErrorSet is i32
        catch_stmts->append(createVarDecl(catch_expr->error_name, get_g_type_i32(), err_access, true));
    }
    if (catch_expr->else_expr->type == NODE_BLOCK_STMT) {
        ASTNode* else_block_inner = cloneASTNode(catch_expr->else_expr, arena_);
        DynamicArray<ASTNode*>* inner_stmts = else_block_inner->as.block_stmt.statements;
        if (inner_stmts->length() > 0) {
            ASTNode* last = (*inner_stmts)[inner_stmts->length() - 1];
            (*inner_stmts)[inner_stmts->length() - 1] = createYieldingStmt(last, temp_ident, loc);
        }
        catch_stmts->append(else_block_inner);
    } else {
        catch_stmts->append(createYieldingStmt(catch_expr->else_expr, temp_ident, loc));
    }
    ASTNode* then_block = createBlock(catch_stmts, loc);

    // Success branch
    ASTNode* payload_access;
    if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
        ASTNode* data_access = createMemberAccess(res_ident, "data", loc);
        payload_access = createMemberAccess(data_access, "payload", loc);
    } else {
        payload_access = createIntegerLiteral(0, get_g_type_void(), loc);
    }
    payload_access->resolved_type = node->resolved_type;
    void* succ_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    DynamicArray<ASTNode*>* succ_stmts = new (succ_stmts_mem) DynamicArray<ASTNode*>(*arena_);
    succ_stmts->append(createYieldingStmt(payload_access, temp_ident, loc));
    ASTNode* else_block = createBlock(succ_stmts, loc);

    ASTNode* if_stmt = createIfStmt(is_error_access, then_block, else_block, loc);

    void* outer_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    DynamicArray<ASTNode*>* outer_stmts = new (outer_stmts_mem) DynamicArray<ASTNode*>(*arena_);
    outer_stmts->append(res_decl);
    outer_stmts->append(if_stmt);

    return createBlock(outer_stmts, loc);
}

ASTNode* ControlFlowLifter::lowerOrelseExpr(ASTNode* node, const char* temp_name) {
    ASTOrelseExprNode* orelse = node->as.orelse_expr;
    SourceLocation loc = node->loc;
    Type* optional_type = orelse->payload->resolved_type;

    ASTNode* temp_ident = createIdentifier(temp_name, loc);
    temp_ident->resolved_type = node->resolved_type;

    const char* res_name = generateTempName("orelse_res");
    ASTNode* res_decl = createVarDecl(res_name, optional_type, orelse->payload, true);

    ASTNode* res_ident = createIdentifier(res_name, loc);
    res_ident->resolved_type = optional_type;

    ASTNode* has_value_access = createMemberAccess(res_ident, "has_value", loc);
    has_value_access->resolved_type = get_g_type_bool();

    // Has value branch
    ASTNode* value_access;
    if (optional_type->as.optional.payload->kind != TYPE_VOID) {
        value_access = createMemberAccess(res_ident, "value", loc);
    } else {
        value_access = createIntegerLiteral(0, get_g_type_void(), loc);
    }
    value_access->resolved_type = node->resolved_type;
    void* has_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    DynamicArray<ASTNode*>* has_stmts = new (has_stmts_mem) DynamicArray<ASTNode*>(*arena_);
    has_stmts->append(createExpressionStmt(createAssignment(temp_ident, value_access, loc), loc));
    ASTNode* then_block = createBlock(has_stmts, loc);

    // Null branch
    ASTNode* else_block;
    if (orelse->else_expr->type == NODE_BLOCK_STMT) {
        else_block = cloneASTNode(orelse->else_expr, arena_);
        DynamicArray<ASTNode*>* stmts = else_block->as.block_stmt.statements;
        if (stmts->length() > 0) {
            ASTNode* last = (*stmts)[stmts->length() - 1];
            (*stmts)[stmts->length() - 1] = createYieldingStmt(last, temp_ident, loc);
        }
    } else {
        void* null_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
        DynamicArray<ASTNode*>* null_stmts = new (null_stmts_mem) DynamicArray<ASTNode*>(*arena_);
        null_stmts->append(createYieldingStmt(orelse->else_expr, temp_ident, loc));
        else_block = createBlock(null_stmts, loc);
    }

    ASTNode* if_stmt = createIfStmt(has_value_access, then_block, else_block, loc);

    void* outer_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    DynamicArray<ASTNode*>* outer_stmts = new (outer_stmts_mem) DynamicArray<ASTNode*>(*arena_);
    outer_stmts->append(res_decl);
    outer_stmts->append(if_stmt);

    return createBlock(outer_stmts, loc);
}

ASTNode* ControlFlowLifter::createYieldingStmt(ASTNode* expr, ASTNode* temp_ident, SourceLocation loc) {
    if (allPathsExit(expr)) {
        // If the expression always exits (return, break, continue, unreachable),
        // we emit it as a statement directly.
        if (expr->type == NODE_EXPRESSION_STMT) return expr;
        if (expr->type == NODE_RETURN_STMT || expr->type == NODE_BREAK_STMT ||
            expr->type == NODE_CONTINUE_STMT || expr->type == NODE_UNREACHABLE) {
            return expr;
        }
        return createExpressionStmt(expr, loc);
    }

    // Otherwise, assign to temp
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

void ControlFlowLifter::liftNode(ASTNode** node_slot, ASTNode* parent, const char* prefix) {
    ASTNode* node = *node_slot;
    if (!node) return;

    // 1. Generate unique temp name
    const char* temp_name = generateTempName(prefix);

    // 2. Create variable declaration (initially NULL, or simple default)
    // C89 requires local variables to be declared at the top, but we insert them
    // just before the current statement for now, which our emitter handles.
    ASTNode* var_decl_node = createVarDecl(temp_name, node->resolved_type, NULL, false);

    // 3. Lower the expression into statements
    DynamicArray<ASTNode*> lowering_stmts(*arena_);

    switch (node->type) {
        case NODE_IF_EXPR:
            lowering_stmts.append(lowerIfExpr(node, temp_name));
            break;
        case NODE_SWITCH_EXPR:
            lowering_stmts.append(lowerSwitchExpr(node, temp_name));
            break;
        case NODE_TRY_EXPR:
            lowerTryExpr(node, temp_name, lowering_stmts);
            break;
        case NODE_CATCH_EXPR:
            lowering_stmts.append(lowerCatchExpr(node, temp_name));
            break;
        case NODE_ORELSE_EXPR:
            lowering_stmts.append(lowerOrelseExpr(node, temp_name));
            break;
        default:
            // Should not happen for isControlFlowExpr
            error_handler_->report(ERR_INTERNAL_ERROR, node->loc, "Unknown control-flow expression for lifting", NULL);
            plat_abort();
    }

    // 4. Find insertion point in current block
    if (block_stack_.length() > 0 && stmt_stack_.length() > 0) {
        ASTBlockStmtNode* current_block = block_stack_.back();
        ASTNode* current_stmt = stmt_stack_.back();
        int insert_idx = findStatementIndex(current_block, current_stmt);

        if (insert_idx != -1) {
            // Insert VarDecl and then lowering statements BEFORE current statement
            current_block->statements->insert((size_t)insert_idx, var_decl_node);
            for (size_t i = 0; i < lowering_stmts.length(); ++i) {
                current_block->statements->insert((size_t)insert_idx + 1 + i, lowering_stmts[i]);
            }
        }
    }

    // 5. Replace node with identifier referencing the temp
    ASTNode* ident_node = createIdentifier(temp_name, node->loc);
    ident_node->resolved_type = node->resolved_type;

    *node_slot = ident_node;
}

const char* ControlFlowLifter::getPrefixForType(NodeType type) {
    switch (type) {
        case NODE_IF_EXPR:     return "if";
        case NODE_SWITCH_EXPR: return "switch";
        case NODE_TRY_EXPR:    return "try";
        case NODE_CATCH_EXPR:  return "catch";
        case NODE_ORELSE_EXPR: return "orelse";
        default:               return "tmp";
    }
}

const char* ControlFlowLifter::generateTempName(const char* prefix) {
    char buf[64];
    char num_buf[16];
    plat_i64_to_string(++tmp_counter_, num_buf, sizeof(num_buf));

    plat_strcpy(buf, "__tmp_");
    plat_strcat(buf, prefix);
    plat_strcat(buf, "_");
    plat_strcat(buf, num_buf);

    return interner_->intern(buf);
}
