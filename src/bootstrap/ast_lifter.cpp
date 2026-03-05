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

ControlFlowLifter::ControlFlowLifter(ArenaAllocator* arena, StringInterner* interner, ErrorHandler* error_handler)
    : arena_(arena), interner_(interner), error_handler_(error_handler),
      tmp_counter_(0), depth_(0), MAX_LIFTING_DEPTH(200),
      stmt_stack_(*arena), block_stack_(*arena) {}

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

    // Inner function to handle the rest of transformation after potentially setting guards
    // Using a local helper struct or just a block of code.
    // In C++98, we can't have member functions inside member functions, but we can have local classes.
    struct Inner {
        static void process(ControlFlowLifter* lifter, ASTNode** node_slot, ASTNode* node, ASTNode* parent) {
            // Post-order: transform children first
            struct TransformVisitor : ChildVisitor {
                ControlFlowLifter* lifter;
                ASTNode* parent;
                TransformVisitor(ControlFlowLifter* l, ASTNode* p) : lifter(l), parent(p) {}

                void visitChild(ASTNode** child_slot) {
                    lifter->transformNode(child_slot, parent);
                }
            };
            TransformVisitor visitor(lifter, node);
            forEachChild(node, visitor);

            // Decision: does THIS node need lifting?
            if (lifter->needsLifting(node, parent)) {
                lifter->liftNode(node_slot, parent, lifter->getPrefixForType(node->type));
            }
        }
    };

    if (is_stmt && is_block) {
        StmtGuard sguard(*this, node);
        BlockGuard bguard(*this, &node->as.block_stmt);
        Inner::process(this, node_slot, node, parent);
    } else if (is_stmt) {
        StmtGuard sguard(*this, node);
        Inner::process(this, node_slot, node, parent);
    } else if (is_block) {
        BlockGuard bguard(*this, &node->as.block_stmt);
        Inner::process(this, node_slot, node, parent);
    } else {
        Inner::process(this, node_slot, node, parent);
    }

    depth_--;
}

bool ControlFlowLifter::needsLifting(ASTNode* node, ASTNode* parent) {
    if (!node) return false;
    if (!parent) return false;

    // Only control-flow expressions can be lifted
    bool is_cf = (node->type == NODE_IF_EXPR || node->type == NODE_SWITCH_EXPR ||
                  node->type == NODE_TRY_EXPR || node->type == NODE_CATCH_EXPR ||
                  node->type == NODE_ORELSE_EXPR);
    if (!is_cf) return false;

    // Decision based on parent context
    switch (parent->type) {
        case NODE_EXPRESSION_STMT:
        case NODE_RETURN_STMT:
        case NODE_VAR_DECL:
            return false; // Safe: already in statement-like position

        case NODE_ASSIGNMENT: {
            // Safe if simple assignment to identifier
            if (parent->as.assignment->rvalue == node &&
                parent->as.assignment->lvalue->type == NODE_IDENTIFIER) {
                return false;
            }
            return true; // Complex lvalue or not the rvalue
        }

        case NODE_BINARY_OP:
        case NODE_UNARY_OP:
        case NODE_FUNCTION_CALL:
        case NODE_ARRAY_ACCESS:
        case NODE_ARRAY_SLICE:
        case NODE_MEMBER_ACCESS:
        case NODE_IF_EXPR:
        case NODE_SWITCH_EXPR:
        case NODE_TRY_EXPR:
        case NODE_CATCH_EXPR:
        case NODE_ORELSE_EXPR:
            return true; // Unsafe: nested in expression

        case NODE_PAREN_EXPR:
            // This is tricky without a full parent pointer in ASTNode.
            // For now, we'll be conservative and lift if it's parenthesized.
            return true;

        default:
            return true; // Conservative: lift if unsure
    }
}

void ControlFlowLifter::liftNode(ASTNode** node_slot, ASTNode* parent, const char* prefix) {
    ASTNode* node = *node_slot;
    if (!node) return;

    // 1. Generate unique temp name
    const char* temp_name = generateTempName(prefix);

    // 2. Clone node (children already transformed)
    ASTNode* init_expr = cloneASTNode(node, arena_);

    // 3. Create variable declaration
    ASTVarDeclNode* var_decl_data = (ASTVarDeclNode*)arena_->alloc(sizeof(ASTVarDeclNode));
    plat_memset(var_decl_data, 0, sizeof(ASTVarDeclNode));
    var_decl_data->name = temp_name;
    var_decl_data->name_loc = node->loc;
    var_decl_data->initializer = init_expr;
    var_decl_data->is_const = true;
    var_decl_data->is_mut = false;

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

        if (current_block->statements) {
            // Find index of current_stmt
            size_t insert_idx = 0;
            bool found = false;
            for (size_t i = 0; i < current_block->statements->length(); ++i) {
                if ((*current_block->statements)[i] == current_stmt) {
                    insert_idx = i;
                    found = true;
                    break;
                }
            }

            if (found) {
                // Insert BEFORE current statement to preserve side-effect order
                size_t old_len = current_block->statements->length();
                current_block->statements->append(NULL); // Increment length

                // Shift elements right
                for (size_t j = old_len; j > insert_idx; --j) {
                    (*current_block->statements)[j] = (*current_block->statements)[j-1];
                }
                (*current_block->statements)[insert_idx] = var_decl_node;
            }
        }
    }

    // 5. Replace node with identifier referencing the temp
    ASTNode* ident_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    plat_memset(ident_node, 0, sizeof(ASTNode));
    ident_node->type = NODE_IDENTIFIER;
    ident_node->loc = node->loc;
    ident_node->resolved_type = node->resolved_type;
    ident_node->as.identifier.name = temp_name;

    *node_slot = ident_node;
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

const char* ControlFlowLifter::getPrefixForType(NodeType type) {
    switch (type) {
        case NODE_IF_EXPR:     return "if";
        case NODE_SWITCH_EXPR: return "sw";
        case NODE_TRY_EXPR:    return "try";
        case NODE_CATCH_EXPR:  return "catch";
        case NODE_ORELSE_EXPR: return "orelse";
        default:               return "lift";
    }
}
