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
    lifter_.pushBlock(block, false);
}

ControlFlowLifter::BlockGuard::~BlockGuard() {
    lifter_.finalizeCurrentBlock();
}

void ControlFlowLifter::addDeclaration(ASTNode* decl) {
    if (block_stack_.length() > 0) {
        block_stack_.back().declarations->append(decl);
    }
}

void ControlFlowLifter::addStatement(ASTNode* stmt) {
    if (block_stack_.length() > 0) {
        block_stack_.back().statements->append(stmt);
    }
}

void ControlFlowLifter::pushBlock(ASTBlockStmtNode* block, bool append_mode) {
    BlockFrame frame;
    frame.init(arena_, block, append_mode);
    block_stack_.append(frame);
}

void ControlFlowLifter::finalizeCurrentBlock() {
    if (block_stack_.length() == 0) return;

    BlockFrame& frame = block_stack_.back();
    if (frame.finalized) {
        block_stack_.pop_back();
        return;
    }
    frame.finalized = true;

    size_t total_len = frame.declarations->length() + frame.statements->length();
    void* mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    DynamicArray<ASTNode*>* new_stmts = new (mem) DynamicArray<ASTNode*>(*arena_);
    new_stmts->ensure_capacity(total_len);

    for (size_t i = 0; i < frame.declarations->length(); ++i) {
        new_stmts->append((*frame.declarations)[i]);
    }
    for (size_t j = 0; j < frame.statements->length(); ++j) {
        new_stmts->append((*frame.statements)[j]);
    }

    frame.block_node->statements = new_stmts;
    block_stack_.pop_back();
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
        postProcessLifting(mod);
        validateReturnStatements(mod->ast_root);
        resolveNameCollisions(mod->ast_root);
    }
}

void ControlFlowLifter::postProcessLifting(Module* mod) {
    if (!mod->ast_root) return;
    splitVarDeclarations(mod->ast_root);
}

void ControlFlowLifter::splitVarDeclarations(ASTNode* node) {
    if (!node) return;

    if (node->type == NODE_BLOCK_STMT) {
        DynamicArray<ASTNode*>* stmts = node->as.block_stmt.statements;
        if (stmts) {
            // We need to be careful about modifying the array during iteration.
            // However, we are only appending or inserting.
            // In C89, we split 'var x = init' into 'var x;' and 'x = init;'.

            // To be safe, we'll collect the changes and apply them.
            // Or we can iterate backwards? No, that messes up order.
            // Let's create a new list.

            DynamicArray<ASTNode*> new_stmts(*arena_);
            bool changed = false;

            for (size_t i = 0; i < stmts->length(); ++i) {
                ASTNode* stmt = (*stmts)[i];
                if (stmt->type == NODE_VAR_DECL) {
                    ASTVarDeclNode* decl = stmt->as.var_decl;
                    if (decl->initializer && decl->initializer->type != NODE_UNDEFINED_LITERAL &&
                        decl->initializer->resolved_type &&
                        decl->initializer->resolved_type->kind != TYPE_TYPE &&
                        decl->initializer->resolved_type->kind != TYPE_MODULE) {

                        // Split it
                        ASTNode* target = createIdentifier(decl->name, stmt->loc);
                        target->as.identifier.symbol = decl->symbol;
                        target->resolved_type = stmt->resolved_type;

                        ASTNode* assignment = createAssignment(target, decl->initializer, stmt->loc);
                        decl->initializer = NULL;

                        new_stmts.append(stmt);
                        new_stmts.append(createExpressionStmt(assignment, stmt->loc));
                        changed = true;
                    } else {
                        new_stmts.append(stmt);
                    }
                } else {
                    new_stmts.append(stmt);
                }
            }

            if (changed) {
                stmts->clear();
                for (size_t i = 0; i < new_stmts.length(); ++i) {
                    stmts->append(new_stmts[i]);
                }
            }
        }
    }

    // Recurse into children
    struct SplitVisitor : ChildVisitor {
        ControlFlowLifter* lifter;
        SplitVisitor(ControlFlowLifter* l) : lifter(l) {}
        void visitChild(ASTNode** child_slot) {
            lifter->splitVarDeclarations(*child_slot);
        }
    };
    SplitVisitor visitor(this);
    forEachChild(node, visitor);
}

void ControlFlowLifter::validateReturnStatements(ASTNode* node) {
    if (!node) return;

    if (node->type == NODE_RETURN_STMT) {
        if (!node->as.return_stmt.expression) {
            // Check if function return type is void
            // This requires current_fn but we can at least log
            plat_printf("VALIDATE: Return statement has NULL expression at %d:%d\n",
                        node->loc.line, node->loc.column);
        } else if (node->as.return_stmt.expression->type == NODE_IDENTIFIER) {
            plat_printf("VALIDATE: Return uses temp '%s'\n",
                       node->as.return_stmt.expression->as.identifier.name);
        }
    }

    // Recurse
    struct ValidateVisitor : ChildVisitor {
        ControlFlowLifter* lifter;
        ValidateVisitor(ControlFlowLifter* l) : lifter(l) {}
        void visitChild(ASTNode** child_slot) {
            lifter->validateReturnStatements(*child_slot);
        }
    };
    ValidateVisitor visitor(this);
    forEachChild(node, visitor);
}

void ControlFlowLifter::transformNode(ASTNode** node_slot, ASTNode* parent) {
    ASTNode* node = *node_slot;
    if (!node) return;

    // Log entry
    plat_printf("transformNode: type=%d, parent=%p, depth=%d\n", node->type, (void*)parent, depth_);

    depth_++;
    if (depth_ > MAX_LIFTING_DEPTH) {
        error_handler_->report(ERR_INTERNAL_ERROR, node->loc, "AST lifting recursion depth exceeded", NULL);
        plat_abort();
    }

    bool is_block = (node->type == NODE_BLOCK_STMT);
    bool root_block = (parent == NULL && is_block);
    bool is_fn = (node->type == NODE_FN_DECL);

    // If this is a control-flow expression that needs lifting, let its specific
    // lowerer handle it (including recursive transformation of its children).
    if (isControlFlowExpr(node->type) && parent && needsLifting(node, parent)) {
        ParentGuard pguard(*this, node);
        liftNode(node_slot, parent, getPrefixForType(node->type));

        // After lifting, if we are in a block, the result assignment was just added
        // to the statement list. We need to make sure it stays there.
        return;
    }

    {
        ParentGuard pguard(*this, node);

        if (root_block || is_block) {
            pushBlock(&node->as.block_stmt, false);
            
            struct TransformVisitor : ChildVisitor {
                ControlFlowLifter* lifter;
                ASTNode* current_node;
                TransformVisitor(ControlFlowLifter* l, ASTNode* n) : lifter(l), current_node(n) {}
                void visitChild(ASTNode** child_slot) {
                    lifter->transformNode(child_slot, current_node);
                }
            };
            TransformVisitor visitor(this, node);
            forEachChild(node, visitor);

            finalizeCurrentBlock();

            // Nested blocks must be added to their parent block's statement list
            if (!root_block && parent && parent->type == NODE_BLOCK_STMT) {
                addStatement(node);
            }
        } else {
            struct Inner {
                static void process(ControlFlowLifter* lifter, ASTNode* node) {
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

            if (is_fn) {
                FnGuard fguard(*this, node->as.fn_decl);
                Inner::process(this, node);
            } else if (node->type == NODE_RETURN_STMT) {
                ASTNode** expr_slot = &node->as.return_stmt.expression;
                if (*expr_slot) {
                    transformNode(expr_slot, node);
                }
            } else {
                Inner::process(this, node);
            }

            if (parent && parent->type == NODE_BLOCK_STMT) {
                if (node->type == NODE_VAR_DECL) {
                    addDeclaration(node);
                } else {
                    addStatement(node);
                }
            }
        }
    }

    depth_--;
    // Log exit
    plat_printf("transformNode exit: type=%d\n", node->type);
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
    if (parent_stack_.length() == 0) return parent;

    const ASTNode* cur = parent;

    // We expect the parent to be at the top of the stack when needsLifting is called
    // (because ParentGuard for 'node' was just popped).
    // If 'cur' is a Paren, we need to go higher in the stack.

    int idx = (int)parent_stack_.length() - 1;

    // Validate index before access
    if (idx < 0 || idx >= (int)parent_stack_.length()) {
        return parent;
    }

    // Verify top of stack is indeed our parent
    if (parent_stack_[idx] != parent) {
        // Fallback: search for it if stack isn't what we expect
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
    if (!node || node->type != NODE_IF_EXPR) return NULL;
    ASTIfExprNode* if_expr = node->as.if_expr;
    SourceLocation loc = node->loc;

    transformNode(&if_expr->condition, node);

    ASTNode* temp_ident = createIdentifier(temp_name, loc);
    temp_ident->resolved_type = node->resolved_type;

    // Then branch
    ASTNode* then_block_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(then_block_node, 0, sizeof(ASTNode));
    then_block_node->type = NODE_BLOCK_STMT;
    then_block_node->loc = if_expr->then_expr->loc;
    
    pushBlock(&then_block_node->as.block_stmt, true);
    block_stack_.back().yield_target = temp_ident;

    if (if_expr->capture_name && if_expr->capture_sym) {
        ASTNode* capture_val;
        Type* cond_type = if_expr->condition->resolved_type;
        if (cond_type->kind == TYPE_OPTIONAL) {
            capture_val = createMemberAccess(if_expr->condition, "value", loc);
            capture_val->resolved_type = cond_type->as.optional.payload;
        } else {
            capture_val = if_expr->condition;
        }

        ASTNode* capture_decl = createVarDecl(if_expr->capture_name, if_expr->capture_sym->symbol_type, NULL, true);
        capture_decl->as.var_decl->symbol = if_expr->capture_sym;
        addDeclaration(capture_decl);

        ASTNode* cap_assign = createAssignment(createIdentifier(if_expr->capture_name, loc), capture_val, loc);
        addStatement(createExpressionStmt(cap_assign, loc));
    }
    
    transformNode(&if_expr->then_expr, node);
    addStatement(createYieldingStmt(if_expr->then_expr, temp_ident, loc));
    finalizeCurrentBlock();

    // Else branch
    ASTNode* else_block_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(else_block_node, 0, sizeof(ASTNode));
    else_block_node->type = NODE_BLOCK_STMT;
    else_block_node->loc = if_expr->else_expr->loc;

    pushBlock(&else_block_node->as.block_stmt, true);
    block_stack_.back().yield_target = temp_ident;

    transformNode(&if_expr->else_expr, node);
    addStatement(createYieldingStmt(if_expr->else_expr, temp_ident, loc));
    finalizeCurrentBlock();

    ASTNode* if_stmt = createIfStmt(if_expr->condition, then_block_node, else_block_node, loc);
    addStatement(if_stmt);
    return if_stmt;
}

ASTNode* ControlFlowLifter::lowerSwitchExpr(ASTNode* node, const char* temp_name) {
    if (!node || node->type != NODE_SWITCH_EXPR) return NULL;
    ASTSwitchExprNode* sw_expr = node->as.switch_expr;
    SourceLocation loc = node->loc;

    transformNode(&sw_expr->expression, node);

    ASTNode* temp_ident = createIdentifier(temp_name, loc);
    temp_ident->resolved_type = node->resolved_type;

    void* prongs_mem = arena_->alloc(sizeof(DynamicArray<ASTSwitchStmtProngNode*>));
    DynamicArray<ASTSwitchStmtProngNode*>* prongs = new (prongs_mem) DynamicArray<ASTSwitchStmtProngNode*>(*arena_);

    bool has_noreturn_prong = false;
    bool has_returning_prong = false;

    for (size_t i = 0; i < sw_expr->prongs->length(); ++i) {
        ASTSwitchProngNode* orig_prong = (*sw_expr->prongs)[i];
        ASTSwitchStmtProngNode* new_prong = (ASTSwitchStmtProngNode*)arena_->alloc(sizeof(ASTSwitchStmtProngNode));
        plat_memset(new_prong, 0, sizeof(ASTSwitchStmtProngNode));

        new_prong->items = orig_prong->items;
        new_prong->is_else = orig_prong->is_else;

        ASTNode* prong_body_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
        plat_memset(prong_body_node, 0, sizeof(ASTNode));
        prong_body_node->type = NODE_BLOCK_STMT;
        prong_body_node->loc = orig_prong->body->loc;

        pushBlock(&prong_body_node->as.block_stmt, true);
        block_stack_.back().yield_target = temp_ident;

        if (allPathsExit(orig_prong->body)) {
            has_noreturn_prong = true;
        } else {
            has_returning_prong = true;
        }

        if (orig_prong->capture_name && orig_prong->capture_sym) {
            ASTNode* capture_val;
            Type* cond_type = sw_expr->expression->resolved_type;
            if (cond_type->kind == TYPE_UNION && cond_type->as.struct_details.is_tagged) {
                ASTNode* data_access = createMemberAccess(sw_expr->expression, "data", loc);
                data_access->resolved_type = cond_type; // Simplified

                const char* field_name = "payload";
                if (orig_prong->items->length() > 0) {
                    ASTNode* item = (*orig_prong->items)[0];
                    if (item->type == NODE_INTEGER_LITERAL && item->as.integer_literal.original_name) {
                        field_name = item->as.integer_literal.original_name;
                    }
                }
                capture_val = createMemberAccess(data_access, field_name, loc);
                capture_val->resolved_type = orig_prong->capture_sym->symbol_type;
            } else {
                capture_val = sw_expr->expression;
            }

            ASTNode* capture_decl = createVarDecl(orig_prong->capture_name, orig_prong->capture_sym->symbol_type, NULL, true);
            capture_decl->as.var_decl->symbol = orig_prong->capture_sym;
            addDeclaration(capture_decl);

            ASTNode* cap_assign = createAssignment(createIdentifier(orig_prong->capture_name, loc), capture_val, loc);
            addStatement(createExpressionStmt(cap_assign, loc));
        }

        transformNode(&orig_prong->body, node);

        // CRITICAL: Verify yield_target is still set
        if (block_stack_.length() > 0 && !block_stack_.back().yield_target) {
            block_stack_.back().yield_target = temp_ident;
        }

        addStatement(createYieldingStmt(orig_prong->body, temp_ident, loc));
        finalizeCurrentBlock();
        new_prong->body = prong_body_node;

        prongs->append(new_prong);
    }

    // Validation log
    if (has_returning_prong && has_noreturn_prong) {
        plat_printf("LIFT: Switch expression has mixed returning and noreturn prongs\n");
    }

    ASTNode* switch_stmt = createSwitchStmt(sw_expr->expression, prongs, loc);
    addStatement(switch_stmt);
    return switch_stmt;
}

void ControlFlowLifter::lowerTryExpr(ASTNode* node, const char* temp_name) {
    if (!node || node->type != NODE_TRY_EXPR) return;
    ASTTryExprNode& try_expr = node->as.try_expr;
    SourceLocation loc = node->loc;

    transformNode(&try_expr.expression, node);
    Type* error_union_type = try_expr.expression->resolved_type;

    // 1. Create a variable to hold the error union result
    const char* res_name = generateTempName("__try_res");
    ASTNode* res_decl = createVarDecl(res_name, error_union_type, NULL, true);
    addDeclaration(res_decl);

    ASTNode* res_ident = createIdentifier(res_name, loc);
    res_ident->resolved_type = error_union_type;

    ASTNode* res_assign = createAssignment(res_ident, try_expr.expression, loc);
    addStatement(createExpressionStmt(res_assign, loc));

    res_ident = createIdentifier(res_name, loc);
    res_ident->resolved_type = error_union_type;

    // 2. Check is_error
    ASTNode* is_error_access = createMemberAccess(res_ident, "is_error", loc);
    is_error_access->resolved_type = get_g_type_bool();

    // 3. Early return block
    // We need to return the error union with the error code.
    ASTNode* ret_val = res_ident;
    ASTNode* ret_stmt = createReturn(ret_val, loc);
    
    ASTNode* then_block_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(then_block_node, 0, sizeof(ASTNode));
    then_block_node->type = NODE_BLOCK_STMT;
    then_block_node->loc = loc;
    pushBlock(&then_block_node->as.block_stmt, true);
    addStatement(ret_stmt);
    finalizeCurrentBlock();

    ASTNode* if_stmt = createIfStmt(is_error_access, then_block_node, NULL, loc);
    addStatement(if_stmt);

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

    addStatement(createYieldingStmt(payload_access, temp_ident, loc));
}

ASTNode* ControlFlowLifter::lowerCatchExpr(ASTNode* node, const char* temp_name) {
    ASTCatchExprNode* catch_expr = node->as.catch_expr;
    SourceLocation loc = node->loc;

    // STEP 1: Process payload FIRST (outside any new scope)
    transformNode(&catch_expr->payload, node);
    Type* error_union_type = catch_expr->payload->resolved_type;

    ASTNode* temp_ident = createIdentifier(temp_name, loc);
    temp_ident->resolved_type = node->resolved_type;

    // 1. Create a variable to hold the error union result
    const char* res_name = generateTempName("__catch_res");
    ASTNode* res_decl = createVarDecl(res_name, error_union_type, NULL, true);
    addDeclaration(res_decl);

    ASTNode* res_ident = createIdentifier(res_name, loc);
    res_ident->resolved_type = error_union_type;

    ASTNode* res_assign = createAssignment(res_ident, catch_expr->payload, loc);
    addStatement(createExpressionStmt(res_assign, loc));

    res_ident = createIdentifier(res_name, loc);
    res_ident->resolved_type = error_union_type;

    // 2. Check is_error
    ASTNode* is_error_access = createMemberAccess(res_ident, "is_error", loc);
    is_error_access->resolved_type = get_g_type_bool();

    // 3. Create a NEW block for the error-handling branch
    ASTNode* catch_block_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(catch_block_node, 0, sizeof(ASTNode));
    catch_block_node->type = NODE_BLOCK_STMT;
    catch_block_node->loc = catch_expr->else_expr->loc;
    
    pushBlock(&catch_block_node->as.block_stmt, true);
    block_stack_.back().yield_target = temp_ident;

    // STEP 4: Handle capture variable declaration
    if (catch_expr->error_name && catch_expr->error_sym) {
        ASTNode* err_access;
        if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
            ASTNode* data_access = createMemberAccess(res_ident, "data", loc);
            err_access = createMemberAccess(data_access, "err", loc);
        } else {
            err_access = createMemberAccess(res_ident, "err", loc);
        }
        
        Type* error_set_type = error_union_type->as.error_union.error_set;
        if (!error_set_type) error_set_type = get_g_type_i32();
        err_access->resolved_type = error_set_type;

        ASTNode* err_decl = createVarDecl(catch_expr->error_name, error_set_type, err_access, true);
        err_decl->as.var_decl->symbol = catch_expr->error_sym;
        addDeclaration(err_decl);
    }
    
    // STEP 5: Transform the branch body
    transformNode(&catch_expr->else_expr, node);
    addStatement(createYieldingStmt(catch_expr->else_expr, temp_ident, loc));
    finalizeCurrentBlock();

    // Success branch
    ASTNode* succ_block_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(succ_block_node, 0, sizeof(ASTNode));
    succ_block_node->type = NODE_BLOCK_STMT;
    succ_block_node->loc = loc;
    pushBlock(&succ_block_node->as.block_stmt, true);
    block_stack_.back().yield_target = temp_ident;
    
    ASTNode* payload_access;
    if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
        ASTNode* data_access = createMemberAccess(res_ident, "data", loc);
        payload_access = createMemberAccess(data_access, "payload", loc);
    } else {
        payload_access = createIntegerLiteral(0, get_g_type_void(), loc);
    }
    payload_access->resolved_type = node->resolved_type;
    addStatement(createYieldingStmt(payload_access, temp_ident, loc));
    finalizeCurrentBlock();

    ASTNode* if_stmt = createIfStmt(is_error_access, catch_block_node, succ_block_node, loc);
    addStatement(if_stmt);

    return if_stmt;
}

ASTNode* ControlFlowLifter::lowerOrelseExpr(ASTNode* node, const char* temp_name) {
    if (!node || node->type != NODE_ORELSE_EXPR) return NULL;
    ASTOrelseExprNode* orelse = node->as.orelse_expr;
    SourceLocation loc = node->loc;

    transformNode(&orelse->payload, node);
    Type* optional_type = orelse->payload->resolved_type;

    ASTNode* temp_ident = createIdentifier(temp_name, loc);
    temp_ident->resolved_type = node->resolved_type;

    const char* res_name = generateTempName("__orelse_res");
    ASTNode* res_decl = createVarDecl(res_name, optional_type, NULL, true);
    addDeclaration(res_decl);

    ASTNode* res_ident = createIdentifier(res_name, loc);
    res_ident->resolved_type = optional_type;

    ASTNode* res_assign = createAssignment(res_ident, orelse->payload, loc);
    addStatement(createExpressionStmt(res_assign, loc));

    res_ident = createIdentifier(res_name, loc);
    res_ident->resolved_type = optional_type;

    ASTNode* has_value_access = createMemberAccess(res_ident, "has_value", loc);
    has_value_access->resolved_type = get_g_type_bool();

    // Has value branch
    ASTNode* has_val_block_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(has_val_block_node, 0, sizeof(ASTNode));
    has_val_block_node->type = NODE_BLOCK_STMT;
    has_val_block_node->loc = loc;
    pushBlock(&has_val_block_node->as.block_stmt, true);
    block_stack_.back().yield_target = temp_ident;

    ASTNode* value_access;
    if (optional_type->as.optional.payload->kind != TYPE_VOID) {
        value_access = createMemberAccess(res_ident, "value", loc);
    } else {
        value_access = createIntegerLiteral(0, get_g_type_void(), loc);
    }
    value_access->resolved_type = node->resolved_type;
    addStatement(createExpressionStmt(createAssignment(temp_ident, value_access, loc), loc));
    finalizeCurrentBlock();

    // Null branch
    ASTNode* null_block_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(null_block_node, 0, sizeof(ASTNode));
    null_block_node->type = NODE_BLOCK_STMT;
    null_block_node->loc = orelse->else_expr->loc;
    pushBlock(&null_block_node->as.block_stmt, true);
    block_stack_.back().yield_target = temp_ident;

    transformNode(&orelse->else_expr, node);
    addStatement(createYieldingStmt(orelse->else_expr, temp_ident, loc));
    finalizeCurrentBlock();

    ASTNode* if_stmt = createIfStmt(has_value_access, has_val_block_node, null_block_node, loc);
    addStatement(if_stmt);

    return if_stmt;
}

ASTNode* ControlFlowLifter::createYieldingStmt(ASTNode* node, ASTNode* temp_ident, SourceLocation loc) {
    if (!node) return NULL;

    if (node->type == NODE_BLOCK_STMT) {
        ASTBlockStmtNode& block = node->as.block_stmt;
        if (block.statements && block.statements->length() > 0) {
            size_t last_idx = block.statements->length() - 1;
            ASTNode* last = (*block.statements)[last_idx];
            (*block.statements)[last_idx] = createYieldingStmt(last, temp_ident, last->loc);
        }
        return node;
    }

    if (allPathsExit(node)) {
        return isStatement(node->type) ? node : createExpressionStmt(node, loc);
    }

    ASTNode* target = NULL;
    if (block_stack_.length() > 0) {
        target = block_stack_.back().yield_target;
    }
    if (!target) {
        target = temp_ident;
    }

    if (!target) {
        error_handler_->report(ERR_INTERNAL_ERROR, loc, "yield_target not set for block", NULL);
        return node;
    }

    plat_printf("YIELD: Creating assignment to '%s'\n", target->as.identifier.name);

    ASTNode* expr = node;
    if (node->type == NODE_EXPRESSION_STMT) {
        expr = node->as.expression_stmt.expression;
    }

    if (expr->type == NODE_ASSIGNMENT || expr->type == NODE_COMPOUND_ASSIGNMENT ||
        expr->type == NODE_VAR_DECL || expr->type == NODE_RETURN_STMT ||
        expr->type == NODE_BREAK_STMT || expr->type == NODE_CONTINUE_STMT) {
        return node;
    }

    return createExpressionStmt(createAssignment(target, expr, loc), loc);
}

void ControlFlowLifter::liftNode(ASTNode** node_slot, ASTNode* parent, const char* prefix) {
    ASTNode* node = *node_slot;
    if (!node) return;

    // 1. Generate unique temp name
    const char* temp_name = generateTempName(prefix);
    plat_printf("LIFT: Creating temp '%s' for node type %d\n", temp_name, node->type);

    // 2. Create variable declaration (initially NULL, or simple default)
    ASTNode* var_decl_node = createVarDecl(temp_name, node->resolved_type, NULL, false);
    addDeclaration(var_decl_node);
    plat_printf("LIFT: Added var decl to block (declarations count: %zu)\n",
                block_stack_.back().declarations->length());

    // 3. Lower the expression into statements (now they use addStatement/addDeclaration)
    switch (node->type) {
        case NODE_IF_EXPR:
            lowerIfExpr(node, temp_name);
            break;
        case NODE_SWITCH_EXPR:
            lowerSwitchExpr(node, temp_name);
            break;
        case NODE_TRY_EXPR:
            lowerTryExpr(node, temp_name);
            break;
        case NODE_CATCH_EXPR:
            lowerCatchExpr(node, temp_name);
            break;
        case NODE_ORELSE_EXPR:
            lowerOrelseExpr(node, temp_name);
            break;
        default:
            error_handler_->report(ERR_INTERNAL_ERROR, node->loc, "Unknown control-flow expression for lifting", NULL);
            plat_abort();
    }

    // 5. Replace node with identifier referencing the temp
    ASTNode* ident_node = createIdentifier(temp_name, node->loc);
    ident_node->resolved_type = node->resolved_type;

    *node_slot = ident_node;
    plat_printf("LIFT: Replaced node with identifier '%s'\n", temp_name);
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

void ControlFlowLifter::resolveNameCollisions(ASTNode* node) {
    if (!node) return;

    if (node->type == NODE_BLOCK_STMT) {
        DynamicArray<NameEntry> names(*arena_);

        DynamicArray<ASTNode*>* stmts = node->as.block_stmt.statements;
        if (stmts) {
            for (size_t i = 0; i < stmts->length(); ++i) {
                ASTNode* stmt = (*stmts)[i];
                if (stmt->type == NODE_VAR_DECL) {
                    const char* name = stmt->as.var_decl->name;
                    bool found = false;
                    for (size_t j = 0; j < names.length(); ++j) {
                        if (plat_strcmp(names[j].name, name) == 0) {
                            names[j].count++;
                            char buf[256];
                            char num_buf[16];
                            plat_i64_to_string(names[j].count - 1, num_buf, sizeof(num_buf));
                            plat_strcpy(buf, name);
                            plat_strcat(buf, "_");
                            plat_strcat(buf, num_buf);
                            stmt->as.var_decl->name = interner_->intern(buf);
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        NameEntry entry = {name, 1};
                        names.append(entry);
                    }
                }
            }
        }
    }

    struct CollisionVisitor : ChildVisitor {
        ControlFlowLifter* lifter;
        CollisionVisitor(ControlFlowLifter* l) : lifter(l) {}
        void visitChild(ASTNode** child_slot) {
            lifter->resolveNameCollisions(*child_slot);
        }
    };
    CollisionVisitor visitor(this);
    forEachChild(node, visitor);
}
