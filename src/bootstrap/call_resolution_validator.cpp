#include "call_resolution_validator.hpp"
#include "ast_utils.hpp"
#include "platform.hpp"

bool CallResolutionValidator::validate(CompilationUnit& unit, ASTNode* root) {
    plat_print_debug("Running CallResolutionValidator...\n");
    if (!root) return true;

    Context ctx(unit);
    traverse(root, ctx);

    return ctx.success;
}

void CallResolutionValidator::traverse(ASTNode* node, Context& ctx) {
    if (!node) return;

    if (node->type == NODE_FUNCTION_CALL) {
        checkCall(node, ctx);
    }

    // Use AST utilities for traversal if available, or manual switch
    // For Task 168, we'll do a simple recursive traversal
    switch (node->type) {
        case NODE_BLOCK_STMT:
            if (node->as.block_stmt.statements) {
                for (size_t i = 0; i < node->as.block_stmt.statements->length(); ++i) {
                    traverse((*node->as.block_stmt.statements)[i], ctx);
                }
            }
            break;
        case NODE_FN_DECL:
            if (node->as.fn_decl) {
                traverse(node->as.fn_decl->body, ctx);
            }
            break;
        case NODE_IF_STMT:
            traverse(node->as.if_stmt->condition, ctx);
            traverse(node->as.if_stmt->then_block, ctx);
            if (node->as.if_stmt->else_block) traverse(node->as.if_stmt->else_block, ctx);
            break;
        case NODE_WHILE_STMT:
            traverse(node->as.while_stmt.condition, ctx);
            traverse(node->as.while_stmt.body, ctx);
            break;
        case NODE_RETURN_STMT:
            if (node->as.return_stmt.expression) traverse(node->as.return_stmt.expression, ctx);
            break;
        case NODE_VAR_DECL:
            if (node->as.var_decl->initializer) traverse(node->as.var_decl->initializer, ctx);
            break;
        case NODE_BINARY_OP:
            traverse(node->as.binary_op->left, ctx);
            traverse(node->as.binary_op->right, ctx);
            break;
        case NODE_UNARY_OP:
            traverse(node->as.unary_op.operand, ctx);
            break;
        case NODE_FUNCTION_CALL:
            if (node->as.function_call) {
                traverse(node->as.function_call->callee, ctx);
                if (node->as.function_call->args) {
                    for (size_t i = 0; i < node->as.function_call->args->length(); ++i) {
                        traverse((*node->as.function_call->args)[i], ctx);
                    }
                }
            }
            break;
        case NODE_EXPRESSION_STMT:
            traverse(node->as.expression_stmt.expression, ctx);
            break;
        case NODE_DEFER_STMT:
            traverse(node->as.defer_stmt.statement, ctx);
            break;
        case NODE_ERRDEFER_STMT:
            traverse(node->as.errdefer_stmt.statement, ctx);
            break;
        case NODE_STRUCT_INITIALIZER:
            if (node->as.struct_initializer && node->as.struct_initializer->fields) {
                for (size_t i = 0; i < node->as.struct_initializer->fields->length(); ++i) {
                    traverse((*node->as.struct_initializer->fields)[i]->value, ctx);
                }
            }
            break;
        case NODE_ARRAY_ACCESS:
            traverse(node->as.array_access->array, ctx);
            traverse(node->as.array_access->index, ctx);
            break;
        case NODE_MEMBER_ACCESS:
            traverse(node->as.member_access->base, ctx);
            break;
        case NODE_SWITCH_EXPR:
            if (node->as.switch_expr) {
                traverse(node->as.switch_expr->expression, ctx);
                if (node->as.switch_expr->prongs) {
                    for (size_t i = 0; i < node->as.switch_expr->prongs->length(); ++i) {
                        ASTSwitchProngNode* prong = (*node->as.switch_expr->prongs)[i];
                        if (prong) {
                            if (!prong->is_else && prong->cases) {
                                for (size_t j = 0; j < prong->cases->length(); ++j) {
                                    traverse((*prong->cases)[j], ctx);
                                }
                            }
                            traverse(prong->body, ctx);
                        }
                    }
                }
            }
            break;
        // ... other nodes that can contain expressions ...
        default: break;
    }
}

void CallResolutionValidator::checkCall(ASTNode* node, Context& ctx) {
    ASTFunctionCallNode* call = node->as.function_call;

    // Check if it's an indirect call
    const IndirectCallInfo* indirect = ctx.unit.getIndirectCallCatalogue().findByLocation(call->callee->loc);
    if (indirect) {
        // Indirect calls are catalogued, which is correct for Milestone 4
        return;
    }

    // If not indirect, it MUST be in CallSiteLookupTable
    const CallSiteEntry* entry = ctx.unit.getCallSiteLookupTable().findByCallNode(node);
    if (!entry) {
        char msg[256];
        char* cur = msg;
        size_t rem = sizeof(msg);
        safe_append(cur, rem, "Call resolution validation failed: call site not found in lookup table for '");
        if (call->callee->type == NODE_IDENTIFIER) {
            safe_append(cur, rem, call->callee->as.identifier.name);
        } else {
            safe_append(cur, rem, "<complex>");
        }
        safe_append(cur, rem, "'");

        ctx.unit.getErrorHandler().report(ERR_INTERNAL_ERROR, node->loc, msg, ctx.unit.getArena());
        ctx.success = false;
        return;
    }

    // If it's a direct call (and not a builtin), it should be resolved
    if (call->callee->type == NODE_IDENTIFIER) {
        const char* name = call->callee->as.identifier.name;
        if (name[0] != '@') {
            if (!entry->resolved) {
                // For now, builtins starting with @ are expected to be unresolved.
                // But regular functions should be resolved if they exist.
                Symbol* sym = ctx.unit.getSymbolTable().lookup(name);
                if (sym && sym->kind == SYMBOL_FUNCTION) {
                    // Should be resolved!
                    char msg[256];
                    char* cur = msg;
                    size_t rem = sizeof(msg);
                    safe_append(cur, rem, "Call resolution validation failed: direct function call remains unresolved for '");
                    safe_append(cur, rem, name);
                    safe_append(cur, rem, "'");

                    ctx.unit.getErrorHandler().report(ERR_INTERNAL_ERROR, node->loc, msg, ctx.unit.getArena());
                    ctx.success = false;
                }
            }
        }
    }
}
