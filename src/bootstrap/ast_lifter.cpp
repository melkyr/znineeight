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

ControlFlowLifter::ControlFlowLifter(ArenaAllocator* arena, StringInterner* interner, ErrorHandler* error_handler)
    : arena_(arena), interner_(interner), error_handler_(error_handler),
      tmp_counter_(0), depth_(0), MAX_LIFTING_DEPTH(200),
      stmt_stack_(*arena), block_stack_(*arena), parent_stack_(*arena) {}

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

ASTVarDeclNode* ControlFlowLifter::createVarDecl(const char* name, Type* type, ASTNode* init, bool is_const) {
    ASTVarDeclNode* var_decl_data = (ASTVarDeclNode*)arena_->alloc(sizeof(ASTVarDeclNode));
    plat_memset(var_decl_data, 0, sizeof(ASTVarDeclNode));
    var_decl_data->name = name;
    var_decl_data->name_loc = init->loc;
    var_decl_data->initializer = init;
    var_decl_data->is_const = is_const;
    var_decl_data->is_mut = !is_const;
    return var_decl_data;
}

ASTNode* ControlFlowLifter::createIdentifier(const char* name, SourceLocation loc) {
    ASTNode* ident_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(ident_node, 0, sizeof(ASTNode));
    ident_node->type = NODE_IDENTIFIER;
    ident_node->loc = loc;
    ident_node->as.identifier.name = name;
    return ident_node;
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

    // 2. Clone node (children already transformed)
    ASTNode* init_expr = cloneASTNode(node, arena_);

    // 3. Create variable declaration
    ASTVarDeclNode* var_decl_data = createVarDecl(temp_name, node->resolved_type, init_expr, true);
    ASTNode* var_decl_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(var_decl_node, 0, sizeof(ASTNode));
    var_decl_node->type = NODE_VAR_DECL;
    var_decl_node->loc = node->loc;
    var_decl_node->resolved_type = node->resolved_type;
    var_decl_node->as.var_decl = var_decl_data;

    // 4. Find insertion point in current block
    if (block_stack_.length() > 0 && stmt_stack_.length() > 0) {
        ASTBlockStmtNode* current_block = block_stack_.back();
        ASTNode* current_stmt = stmt_stack_.back();
        int insert_idx = findStatementIndex(current_block, current_stmt);

        if (insert_idx != -1) {
            // Insert BEFORE current statement to preserve side-effect order
            current_block->statements->insert((size_t)insert_idx, var_decl_node);
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
