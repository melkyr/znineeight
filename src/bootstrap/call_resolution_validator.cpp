#include "call_resolution_validator.hpp"
#include "ast_utils.hpp"
#include "platform.hpp"
#include "utils.hpp"

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
            if (node->as.if_stmt) {
                traverse(node->as.if_stmt->condition, ctx);
                traverse(node->as.if_stmt->then_block, ctx);
                if (node->as.if_stmt->else_block) traverse(node->as.if_stmt->else_block, ctx);
            }
            break;
        case NODE_WHILE_STMT:
            traverse(node->as.while_stmt->condition, ctx);
            traverse(node->as.while_stmt->body, ctx);
            break;
        case NODE_FOR_STMT:
            if (node->as.for_stmt) {
                traverse(node->as.for_stmt->iterable_expr, ctx);
                traverse(node->as.for_stmt->body, ctx);
            }
            break;
        case NODE_RETURN_STMT:
            if (node->as.return_stmt.expression) traverse(node->as.return_stmt.expression, ctx);
            break;
        case NODE_VAR_DECL:
            if (node->as.var_decl && node->as.var_decl->initializer) {
                traverse(node->as.var_decl->initializer, ctx);
            }
            break;
        case NODE_ASSIGNMENT:
            if (node->as.assignment) {
                traverse(node->as.assignment->lvalue, ctx);
                traverse(node->as.assignment->rvalue, ctx);
            }
            break;
        case NODE_BINARY_OP:
            if (node->as.binary_op) {
                traverse(node->as.binary_op->left, ctx);
                traverse(node->as.binary_op->right, ctx);
            }
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
            if (node->as.array_access) {
                traverse(node->as.array_access->array, ctx);
                traverse(node->as.array_access->index, ctx);
            }
            break;
        case NODE_MEMBER_ACCESS:
            if (node->as.member_access) {
                traverse(node->as.member_access->base, ctx);
            }
            break;
        case NODE_SWITCH_EXPR:
            if (node->as.switch_expr) {
                traverse(node->as.switch_expr->expression, ctx);
                if (node->as.switch_expr->prongs) {
                    for (size_t i = 0; i < node->as.switch_expr->prongs->length(); ++i) {
                        ASTSwitchProngNode* prong = (*node->as.switch_expr->prongs)[i];
                        if (prong) {
                            if (!prong->is_else && prong->items) {
                                for (size_t j = 0; j < prong->items->length(); ++j) {
                                    traverse((*prong->items)[j], ctx);
                                }
                            }
                            traverse(prong->body, ctx);
                        }
                    }
                }
            }
            break;
        case NODE_PTR_CAST:
            if (node->as.ptr_cast) {
                traverse(node->as.ptr_cast->target_type, ctx);
                traverse(node->as.ptr_cast->expr, ctx);
            }
            break;
        case NODE_INT_CAST:
        case NODE_FLOAT_CAST:
            if (node->as.numeric_cast) {
                traverse(node->as.numeric_cast->target_type, ctx);
                traverse(node->as.numeric_cast->expr, ctx);
            }
            break;
        case NODE_OFFSET_OF:
            if (node->as.offset_of) {
                traverse(node->as.offset_of->type_expr, ctx);
            }
            break;
        case NODE_PAREN_EXPR:
            traverse(node->as.paren_expr.expr, ctx);
            break;
        case NODE_TRY_EXPR:
            traverse(node->as.try_expr.expression, ctx);
            break;
        case NODE_CATCH_EXPR:
            if (node->as.catch_expr) {
                traverse(node->as.catch_expr->payload, ctx);
                traverse(node->as.catch_expr->else_expr, ctx);
            }
            break;
        case NODE_ORELSE_EXPR:
            if (node->as.orelse_expr) {
                traverse(node->as.orelse_expr->payload, ctx);
                traverse(node->as.orelse_expr->else_expr, ctx);
            }
            break;
        // ... other nodes that can contain expressions ...
        default: break;
    }
}

void CallResolutionValidator::checkCall(ASTNode* node, Context& ctx) {
    if (!node || !node->as.function_call || !node->as.function_call->callee) return;
    ASTFunctionCallNode* call = node->as.function_call;

    // Skip built-ins (Task 168/209)
    if (call->callee->type == NODE_IDENTIFIER) {
        const char* name = call->callee->as.identifier.name;
        if (name && name[0] == '@') {
            return;
        }
    }

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

        ctx.unit.getErrorHandler().report(ERR_INTERNAL_ERROR, node->loc, ErrorHandler::getMessage(ERR_INTERNAL_ERROR), ctx.unit.getArena(), msg);
        ctx.success = false;
        return;
    }

    // If it's a direct call (and not a builtin), it should be resolved
    if (call->callee->type == NODE_IDENTIFIER) {
        const char* name = call->callee->as.identifier.name;
        if (name[0] != '@') {
            if (!entry->resolved) {
                // If it's explicitly marked with a reason, it's accounted for.
                if (entry->error_if_unresolved) {
                    return;
                }

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

                    ctx.unit.getErrorHandler().report(ERR_INTERNAL_ERROR, node->loc, ErrorHandler::getMessage(ERR_INTERNAL_ERROR), ctx.unit.getArena(), msg);
                    ctx.success = false;
                }
            }
        }
    }
}
