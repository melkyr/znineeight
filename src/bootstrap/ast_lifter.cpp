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
      stmt_stack_(*arena), block_stack_(*arena), parent_stack_(*arena), fn_stack_(*arena) {}

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

        transformNode(&mod->ast_root, NULL);
        validateLifting(mod);
    }
    unit_ = NULL;
    module_name_ = NULL;
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
        } else if (is_stmt) {
            StmtGuard sguard(*this, node);
            Inner::process(this, node);
        } else if (is_block) {
            BlockGuard bguard(*this, &node->as.block_stmt);
            ScopeGuard scguard(*this);
            Inner::process(this, node);
        } else if (is_fn) {
            FnGuard fguard(*this, node->as.fn_decl);
            Inner::process(this, node);
        } else {
            Inner::process(this, node);
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
    var_decl_data->name_loc = init ? init->loc : (stmt_stack_.length() > 0 ? stmt_stack_.back()->loc : SourceLocation());
    var_decl_data->initializer = init;
    var_decl_data->is_const = is_const;
    var_decl_data->is_mut = !is_const;

    if (name) {
        Symbol sym_val;
        plat_memset(&sym_val, 0, sizeof(Symbol));
        sym_val.name = name;
        sym_val.symbol_type = type;
        sym_val.kind = SYMBOL_VARIABLE;
        sym_val.flags = SYMBOL_FLAG_LOCAL;
        if (is_const) sym_val.flags |= SYMBOL_FLAG_CONST;

        if (unit_ && module_name_) {
            SymbolTable& table = unit_->getSymbolTable(module_name_);
            sym_val.scope_level = table.getCurrentScopeLevel();
            table.registerTempSymbol(&sym_val);
            // Crucial: Use the pointer to the symbol stored in the table, not our stack copy.
            // This ensures both declaration and identifiers point to the same Symbol object.
            var_decl_data->symbol = table.lookupInCurrentScope(name);

            if (plat_strncmp(name, "__tmp_", 6) == 0) {
                registered_temps_.append(name);
            }
            if (debug_mode_) {
                plat_printf_debug("[LIFTER] Registered symbol: %s at scope level %d\n", name, sym_val.scope_level);
            }
        } else {
            Symbol* sym = (Symbol*)arena_->alloc(sizeof(Symbol));
            *sym = sym_val;
            sym->scope_level = 0;
            var_decl_data->symbol = sym;
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

void ControlFlowLifter::updateCaptureSymbols(ASTNode* node, const char* name, Symbol* new_sym) {
    if (!node) return;

    if (node->type == NODE_IDENTIFIER) {
        if (node->as.identifier.name && plat_strcmp(node->as.identifier.name, name) == 0) {
            node->as.identifier.symbol = new_sym;
        }
    }

    struct UpdateVisitor : ChildVisitor {
        ControlFlowLifter* lifter;
        const char* name;
        Symbol* new_sym;
        UpdateVisitor(ControlFlowLifter* l, const char* n, Symbol* s) : lifter(l), name(n), new_sym(s) {}
        void visitChild(ASTNode** child_slot) {
            lifter->updateCaptureSymbols(*child_slot, name, new_sym);
        }
    };

    UpdateVisitor visitor(this, name, new_sym);
    forEachChild(node, visitor);
}

ASTNode* ControlFlowLifter::lowerIfExpr(ASTNode* node, const char* temp_name) {
    ASTIfExprNode* if_expr = node->as.if_expr;
    SourceLocation loc = node->loc;

    // Use current_module_ instead of looking up in loop if possible,
    // but lookup is safer if we don't have it cached.
    Symbol* temp_sym = (unit_ && module_name_) ? unit_->getSymbolTable(module_name_).lookup(temp_name) : NULL;
    ASTNode* temp_ident = createIdentifier(temp_name, loc, temp_sym);
    temp_ident->resolved_type = node->resolved_type;

    // Then branch
    ASTNode* then_block;
    {
        ASTNode* branch_expr = if_expr->then_expr;
        if (branch_expr->type == NODE_BLOCK_STMT) {
            then_block = cloneASTNode(branch_expr, arena_);
            DynamicArray<ASTNode*>* stmts = then_block->as.block_stmt.statements;
            if (stmts->length() > 0) {
                (*stmts)[stmts->length() - 1] = createYieldingStmt((*stmts)[stmts->length() - 1], temp_ident, loc);
            }
        } else {
            void* stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
            DynamicArray<ASTNode*>* stmts = new (stmts_mem) DynamicArray<ASTNode*>(*arena_);
            stmts->append(createYieldingStmt(branch_expr, temp_ident, loc));
            then_block = createBlock(stmts, loc);
        }
    }

    // Else branch
    ASTNode* else_block;
    {
        ASTNode* branch_expr = if_expr->else_expr;
        if (branch_expr->type == NODE_BLOCK_STMT) {
            else_block = cloneASTNode(branch_expr, arena_);
            DynamicArray<ASTNode*>* stmts = else_block->as.block_stmt.statements;
            if (stmts->length() > 0) {
                (*stmts)[stmts->length() - 1] = createYieldingStmt((*stmts)[stmts->length() - 1], temp_ident, loc);
            }
        } else {
            void* stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
            DynamicArray<ASTNode*>* stmts = new (stmts_mem) DynamicArray<ASTNode*>(*arena_);
            stmts->append(createYieldingStmt(branch_expr, temp_ident, loc));
            else_block = createBlock(stmts, loc);
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

        updateCaptureSymbols(then_block, if_expr->capture_name, new_sym);
    }

    // Transform branches
    transformNode(&then_block, if_stmt_node);
    transformNode(&else_block, if_stmt_node);

    return if_stmt_node;
}

ASTNode* ControlFlowLifter::lowerSwitchExpr(ASTNode* node, const char* temp_name) {
    ASTSwitchExprNode* sw_expr = node->as.switch_expr;
    SourceLocation loc = node->loc;

    Symbol* temp_sym = (unit_ && module_name_) ? unit_->getSymbolTable(module_name_).lookup(temp_name) : NULL;
    ASTNode* temp_ident = createIdentifier(temp_name, loc, temp_sym);
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

        ASTNode* body_node = orig_prong->body;
        if (body_node->type == NODE_BLOCK_STMT) {
            body_node = cloneASTNode(body_node, arena_);
            DynamicArray<ASTNode*>* stmts = body_node->as.block_stmt.statements;
            if (stmts->length() > 0) {
                (*stmts)[stmts->length() - 1] = createYieldingStmt((*stmts)[stmts->length() - 1], temp_ident, loc);
            }
            new_prong->body = body_node;
        } else {
            void* stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
            DynamicArray<ASTNode*>* stmts = new (stmts_mem) DynamicArray<ASTNode*>(*arena_);
            stmts->append(createYieldingStmt(body_node, temp_ident, loc));
            new_prong->body = createBlock(stmts, loc);
        }

        // Parent should be the switch stmt, but it's not created yet.
        // NULL is fine as dummy blocks won't be lifted.
        transformNode(&new_prong->body, NULL);

        if (new_prong->capture_name && new_prong->capture_sym) {
            Symbol* new_sym = (Symbol*)arena_->alloc(sizeof(Symbol));
            plat_memcpy(new_sym, new_prong->capture_sym, sizeof(Symbol));
            new_sym->flags |= SYMBOL_FLAG_LOCAL | SYMBOL_FLAG_CONST;
            new_prong->capture_sym = new_sym;

            updateCaptureSymbols(new_prong->body, new_prong->capture_name, new_sym);
        }

        prongs->append(new_prong);
    }

    return createSwitchStmt(sw_expr->expression, prongs, loc);
}

void ControlFlowLifter::lowerTryExpr(ASTNode* node, const char* temp_name, DynamicArray<ASTNode*>& out_stmts, bool needs_wrapping) {
    ASTTryExprNode& try_expr = node->as.try_expr;
    SourceLocation loc = node->loc;
    Type* error_union_type = try_expr.expression->resolved_type;

    // 1. Create a variable to hold the error union result
    const char* res_name = generateTempName("try_res");
    ASTNode* res_decl = createVarDecl(res_name, error_union_type, try_expr.expression, true);
    out_stmts.append(res_decl);

    ASTNode* res_ident = createIdentifier(res_name, loc, res_decl->as.var_decl->symbol);
    res_ident->resolved_type = error_union_type;

    // 2. Check is_error
    ASTNode* is_error_access = createMemberAccess(res_ident, "is_error", loc);
    is_error_access->resolved_type = get_g_type_bool();

    if (needs_wrapping && current_fn_return_type_) {
        // Full wrapping mode: populate temp_name (which is of current_fn_return_type_)
        Symbol* temp_sym = (unit_ && module_name_) ? unit_->getSymbolTable(module_name_).lookup(temp_name) : NULL;
        ASTNode* temp_ident = createIdentifier(temp_name, loc, temp_sym);
        temp_ident->resolved_type = current_fn_return_type_;

        // If error path
        void* err_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
        DynamicArray<ASTNode*>* err_stmts = new (err_stmts_mem) DynamicArray<ASTNode*>(*arena_);

        // ret_temp.is_error = 1;
        ASTNode* is_error_assign = createAssignment(createMemberAccess(temp_ident, "is_error", loc), createIntegerLiteral(1, get_g_type_i32(), loc), loc);
        err_stmts->append(createExpressionStmt(is_error_assign, loc));

        // ret_temp.data.err = operand_temp.data.err; (or .err if void payload)
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

        ASTNode* then_block = createBlock(err_stmts, loc);

        // Success path
        void* succ_stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
        DynamicArray<ASTNode*>* succ_stmts = new (succ_stmts_mem) DynamicArray<ASTNode*>(*arena_);

        // ret_temp.is_error = 0;
        ASTNode* is_error_succ_assign = createAssignment(createMemberAccess(temp_ident, "is_error", loc), createIntegerLiteral(0, get_g_type_i32(), loc), loc);
        succ_stmts->append(createExpressionStmt(is_error_succ_assign, loc));

        // ret_temp.data.payload = operand_temp.data.payload; (if not void)
        if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
             ASTNode* src_payload = createMemberAccess(createMemberAccess(res_ident, "data", loc), "payload", loc);
             ASTNode* dest_payload = createMemberAccess(createMemberAccess(temp_ident, "data", loc), "payload", loc);
             dest_payload->resolved_type = src_payload->resolved_type = error_union_type->as.error_union.payload;
             succ_stmts->append(createExpressionStmt(createAssignment(dest_payload, src_payload, loc), loc));
        }

        ASTNode* else_block = createBlock(succ_stmts, loc);

        out_stmts.append(createIfStmt(is_error_access, then_block, else_block, loc));
    } else {
        // Normal early return mode
        // 3. Early return block
        // We need to return the error union with the error code.
        Type* ret_type = current_fn_return_type_ ? current_fn_return_type_ : get_g_type_void();

        ASTNode* ret_val;
        if (areTypesEqual(ret_type, error_union_type)) {
            ret_val = res_ident;
        } else {
            // Wrap the error from res_ident into ret_type
            ASTNode* err_access;
            if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
                ASTNode* data_access = createMemberAccess(res_ident, "data", loc);
                data_access->resolved_type = error_union_type;
                err_access = createMemberAccess(data_access, "err", loc);
            } else {
                err_access = createMemberAccess(res_ident, "err", loc);
            }
            err_access->resolved_type = get_g_type_i32();
            
            // Build a synthetic wrapper for the return type
            void* array_mem = arena_->alloc(sizeof(DynamicArray<ASTNamedInitializer*>));
            DynamicArray<ASTNamedInitializer*>* fields = new (array_mem) DynamicArray<ASTNamedInitializer*>(*arena_);
            
            if (ret_type->as.error_union.payload->kind == TYPE_VOID) {
                ASTNamedInitializer* err_init = (ASTNamedInitializer*)arena_->alloc(sizeof(ASTNamedInitializer));
                err_init->field_name = "err";
                err_init->value = err_access;
                err_init->loc = loc;
                fields->append(err_init);
            } else {
                // .{ .data = .{ .err = err_access } }
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
                // Type of 'data' is a union, but we can use any non-null type for now as emitter handles it
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
        ret_stmts->append(ret_stmt);
        ASTNode* then_block = createBlock(ret_stmts, loc);

        ASTNode* if_stmt = createIfStmt(is_error_access, then_block, NULL, loc);
        out_stmts.append(if_stmt);

        // 4. Assign payload to temp_name (skip if void)
        if (node->resolved_type && node->resolved_type->kind != TYPE_VOID) {
            Symbol* temp_sym = (unit_ && module_name_) ? unit_->getSymbolTable(module_name_).lookup(temp_name) : NULL;
            ASTNode* temp_ident = createIdentifier(temp_name, loc, temp_sym);
            temp_ident->resolved_type = node->resolved_type;

            ASTNode* payload_access;
            if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
                ASTNode* data_access = createMemberAccess(res_ident, "data", loc);
                data_access->resolved_type = error_union_type; // actually it's a union but we just need a non-null type
                payload_access = createMemberAccess(data_access, "payload", loc);
            } else {
                payload_access = createIntegerLiteral(0, get_g_type_void(), loc);
                // Important: ensure the expression stmt gets emitted as a dummy 0; for void payloads
                // that are being lifted into a void temp (which is then skipped).
            }
            payload_access->resolved_type = node->resolved_type;

            out_stmts.append(createYieldingStmt(payload_access, temp_ident, loc));
        }
    }
}

void ControlFlowLifter::lowerCatchExpr(ASTNode* node, const char* temp_name, DynamicArray<ASTNode*>& out_stmts) {
    ASTCatchExprNode* catch_expr = node->as.catch_expr;
    SourceLocation loc = node->loc;
    Type* error_union_type = catch_expr->payload->resolved_type;

    Symbol* temp_sym = (unit_ && module_name_) ? unit_->getSymbolTable(module_name_).lookup(temp_name) : NULL;
    ASTNode* temp_ident = createIdentifier(temp_name, loc, temp_sym);
    temp_ident->resolved_type = node->resolved_type;

    const char* res_name = generateTempName("catch_res");
    ASTNode* res_decl = createVarDecl(res_name, error_union_type, catch_expr->payload, true);
    out_stmts.append(res_decl);

    ASTNode* res_ident = createIdentifier(res_name, loc, res_decl->as.var_decl->symbol);
    res_ident->resolved_type = error_union_type;

    ASTNode* is_error_access = createMemberAccess(res_ident, "is_error", loc);
    is_error_access->resolved_type = get_g_type_bool();

    // Catch branch (error)
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
        // Capture error: var err = res.data.err;
        ASTNode* err_access;
        if (error_union_type->as.error_union.payload->kind != TYPE_VOID) {
            ASTNode* data_access = createMemberAccess(res_ident, "data", loc);
            data_access->resolved_type = error_union_type;
            err_access = createMemberAccess(data_access, "err", loc);
        } else {
            err_access = createMemberAccess(res_ident, "err", loc);
        }
        err_access->resolved_type = get_g_type_i32(); // ErrorSet is i32

        // Use plain name, but create a new unique Symbol for this scope
        const char* capture_name = catch_expr->error_name;
        Symbol* new_sym = (Symbol*)arena_->alloc(sizeof(Symbol));
        plat_memset(new_sym, 0, sizeof(Symbol));
        new_sym->name = capture_name;
        new_sym->symbol_type = get_g_type_i32();
        new_sym->kind = SYMBOL_VARIABLE;
        new_sym->flags = SYMBOL_FLAG_LOCAL | SYMBOL_FLAG_CONST;

        // Create VarDecl but skip registration in the main table to avoid collisions
        ASTNode* err_decl = createVarDecl(NULL, get_g_type_i32(), err_access, true);
        err_decl->as.var_decl->name = capture_name;
        err_decl->as.var_decl->symbol = new_sym;
        catch_stmts->append(err_decl);

        // Update symbols in the catch body to point to the new declaration
        updateCaptureSymbols(catch_body, capture_name, new_sym);
    }

    catch_stmts->append(catch_body);

    // Transform the prepared lowering block
    transformNode(&catch_lower_block, NULL);

    ASTNode* then_block = catch_lower_block;

    // Success branch
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
    succ_stmts->append(createYieldingStmt(payload_access, temp_ident, loc));
    ASTNode* else_block = createBlock(succ_stmts, loc);

    ASTNode* if_stmt = createIfStmt(is_error_access, then_block, else_block, loc);
    out_stmts.append(if_stmt);
}

void ControlFlowLifter::lowerOrelseExpr(ASTNode* node, const char* temp_name, DynamicArray<ASTNode*>& out_stmts) {
    ASTOrelseExprNode* orelse = node->as.orelse_expr;
    SourceLocation loc = node->loc;
    Type* optional_type = orelse->payload->resolved_type;

    Symbol* temp_sym = (unit_ && module_name_) ? unit_->getSymbolTable(module_name_).lookup(temp_name) : NULL;
    ASTNode* temp_ident = createIdentifier(temp_name, loc, temp_sym);
    temp_ident->resolved_type = node->resolved_type;

    const char* res_name = generateTempName("orelse_res");
    ASTNode* res_decl = createVarDecl(res_name, optional_type, orelse->payload, true);
    out_stmts.append(res_decl);

    ASTNode* res_ident = createIdentifier(res_name, loc, res_decl->as.var_decl->symbol);
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
    {
        ASTNode* branch_expr = orelse->else_expr;
        if (branch_expr->type == NODE_BLOCK_STMT) {
            else_block = cloneASTNode(branch_expr, arena_);
            DynamicArray<ASTNode*>* stmts = else_block->as.block_stmt.statements;
            if (stmts->length() > 0) {
                (*stmts)[stmts->length() - 1] = createYieldingStmt((*stmts)[stmts->length() - 1], temp_ident, loc);
            }
        } else {
            void* stmts_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
            DynamicArray<ASTNode*>* stmts = new (stmts_mem) DynamicArray<ASTNode*>(*arena_);
            stmts->append(createYieldingStmt(branch_expr, temp_ident, loc));
            else_block = createBlock(stmts, loc);
        }
    }

    ASTNode* if_stmt = createIfStmt(has_value_access, then_block, else_block, loc);

    // Transform branches
    transformNode(&then_block, if_stmt);
    transformNode(&else_block, if_stmt);

    out_stmts.append(if_stmt);
}

ASTNode* ControlFlowLifter::createYieldingStmt(ASTNode* expr, ASTNode* temp_ident, SourceLocation loc) {
    if (!expr) return NULL;
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

    // Otherwise, assign to temp (skip if void)
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
    ASTNode* node = *node_slot;
    if (!node) return;

    if (debug_mode_) {
        char loc_buf[128];
        formatSourceLocation(node->loc, loc_buf, sizeof(loc_buf));
        plat_printf_debug("[LIFTER] Lifting node type=%d prefix=%s at %s needs_wrapping=%d\n",
                         (int)node->type, prefix, loc_buf, needs_wrapping ? 1 : 0);
    }

    // 1. Generate unique temp name
    const char* temp_name = generateTempName(prefix);

    if (debug_mode_) {
        plat_printf_debug("[LIFTER] Generated temp name: %s\n", temp_name);
    }

    // 2. Create variable declaration (initially NULL, or simple default)
    // C89 requires local variables to be declared at the top, but we insert them
    // just before the current statement for now, which our emitter handles.
    // Skip VarDecl if the type is void.
    ASTNode* var_decl_node = NULL;
    Type* temp_type = node->resolved_type;
    if (needs_wrapping && current_fn_return_type_) {
        temp_type = current_fn_return_type_;
    }

    if (temp_type && temp_type->kind != TYPE_VOID) {
        var_decl_node = createVarDecl(temp_name, temp_type, NULL, false);
    }

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
            lowerTryExpr(node, temp_name, lowering_stmts, needs_wrapping);
            break;
        case NODE_CATCH_EXPR:
            lowerCatchExpr(node, temp_name, lowering_stmts);
            break;
        case NODE_ORELSE_EXPR:
            lowerOrelseExpr(node, temp_name, lowering_stmts);
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
            size_t offset = 0;
            if (var_decl_node) {
                current_block->statements->insert((size_t)insert_idx, var_decl_node);
                offset = 1;
            }
            for (size_t i = 0; i < lowering_stmts.length(); ++i) {
                current_block->statements->insert((size_t)insert_idx + offset + i, lowering_stmts[i]);
            }
        }
    }

    // 5. Replace node with identifier referencing the temp (or dummy if void)
    ASTNode* ident_node = createIdentifier(temp_name, node->loc, var_decl_node ? var_decl_node->as.var_decl->symbol : NULL);
    ident_node->resolved_type = temp_type;

    if (debug_mode_) {
        plat_printf_debug("[LIFTER] Replaced node with identifier: %s\n", temp_name);
    }

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

    const char* interned = interner_->intern(buf);
    /* plat_printf_debug("[LIFTER] generateTempName counter=%d name=%s depth=%d\n", tmp_counter_, interned, depth_); */
    return interned;
}

void ControlFlowLifter::validateLifting(Module* mod) {
    if (!debug_mode_) return;

    plat_printf_debug("[LIFTER] Validation: %d temp variables registered in module %s\n",
                     (int)registered_temps_.length(), mod->name);

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
            plat_printf_debug("[LIFTER] WARNING: Node type=%d has NULL resolved_type at %s context=%s\n",
                             (int)node->type, loc_buf, context);
        }
    }

    if (node->type == NODE_IDENTIFIER) {
        if (!node->as.identifier.symbol &&
            (!node->as.identifier.name ||
             plat_strncmp(node->as.identifier.name, "__tmp_", 6) != 0)) {
            char loc_buf[128];
            formatSourceLocation(node->loc, loc_buf, sizeof(loc_buf));
            plat_printf_debug("[LIFTER] WARNING: Identifier has no symbol and is not temp at %s\n", loc_buf);
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
