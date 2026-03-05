#include "ast_utils.hpp"
#include "symbol_table.hpp"
#include "type_system.hpp"

bool isTypeExpression(ASTNode* node, SymbolTable& symbols) {
    if (!node) return false;
    switch (node->type) {
        case NODE_TYPE_NAME:
        case NODE_POINTER_TYPE:
        case NODE_ARRAY_TYPE:
        case NODE_STRUCT_DECL:
        case NODE_ENUM_DECL:
        case NODE_UNION_DECL:
        case NODE_ERROR_UNION_TYPE:
        case NODE_OPTIONAL_TYPE:
        case NODE_ERROR_SET_DEFINITION:
        case NODE_ERROR_SET_MERGE:
            return true;
        case NODE_IDENTIFIER: {
            // Check builtin types first
            if (resolvePrimitiveTypeName(node->as.identifier.name)) {
                return true;
            }
            // Then check symbol table
            Symbol* sym = symbols.lookup(node->as.identifier.name);
            return sym && sym->kind == SYMBOL_TYPE;
        }
        default:
            return false;
    }
}

void forEachChild(ASTNode* node, ChildVisitor& visitor) {
    if (!node) return;

    switch (node->type) {
        // ~~~~~~~~~~~~~~~~~~~~~~ Expressions ~~~~~~~~~~~~~~~~~~~~~~
        case NODE_ASSIGNMENT:
            if (node->as.assignment) {
                visitor.visitChild(&node->as.assignment->lvalue);
                visitor.visitChild(&node->as.assignment->rvalue);
            }
            break;
        case NODE_COMPOUND_ASSIGNMENT:
            if (node->as.compound_assignment) {
                visitor.visitChild(&node->as.compound_assignment->lvalue);
                visitor.visitChild(&node->as.compound_assignment->rvalue);
            }
            break;
        case NODE_UNARY_OP:
            visitor.visitChild(&node->as.unary_op.operand);
            break;
        case NODE_BINARY_OP:
            if (node->as.binary_op) {
                visitor.visitChild(&node->as.binary_op->left);
                visitor.visitChild(&node->as.binary_op->right);
            }
            break;
        case NODE_FUNCTION_CALL:
            if (node->as.function_call) {
                visitor.visitChild(&node->as.function_call->callee);
                if (node->as.function_call->args) {
                    for (size_t i = 0; i < node->as.function_call->args->length(); ++i) {
                        visitor.visitChild(&(*node->as.function_call->args)[i]);
                    }
                }
            }
            break;
        case NODE_ARRAY_ACCESS:
            if (node->as.array_access) {
                visitor.visitChild(&node->as.array_access->array);
                visitor.visitChild(&node->as.array_access->index);
            }
            break;
        case NODE_ARRAY_SLICE:
            if (node->as.array_slice) {
                visitor.visitChild(&node->as.array_slice->array);
                visitor.visitChild(&node->as.array_slice->start);
                visitor.visitChild(&node->as.array_slice->end);
                visitor.visitChild(&node->as.array_slice->base_ptr);
                visitor.visitChild(&node->as.array_slice->len);
            }
            break;
        case NODE_MEMBER_ACCESS:
            if (node->as.member_access) {
                visitor.visitChild(&node->as.member_access->base);
            }
            break;
        case NODE_STRUCT_INITIALIZER:
            if (node->as.struct_initializer) {
                visitor.visitChild(&node->as.struct_initializer->type_expr);
                if (node->as.struct_initializer->fields) {
                    for (size_t i = 0; i < node->as.struct_initializer->fields->length(); ++i) {
                        visitor.visitChild(&(*node->as.struct_initializer->fields)[i]->value);
                    }
                }
            }
            break;
        case NODE_TUPLE_LITERAL:
            if (node->as.tuple_literal && node->as.tuple_literal->elements) {
                for (size_t i = 0; i < node->as.tuple_literal->elements->length(); ++i) {
                    visitor.visitChild(&(*node->as.tuple_literal->elements)[i]);
                }
            }
            break;

        // ~~~~~~~~~~~~~~~~~~~~~~~ Literals ~~~~~~~~~~~~~~~~~~~~~~~~
        case NODE_BOOL_LITERAL:
        case NODE_NULL_LITERAL:
        case NODE_UNDEFINED_LITERAL:
        case NODE_INTEGER_LITERAL:
        case NODE_FLOAT_LITERAL:
        case NODE_CHAR_LITERAL:
        case NODE_STRING_LITERAL:
        case NODE_ERROR_LITERAL:
        case NODE_IDENTIFIER:
        case NODE_UNREACHABLE:
            break; // No children

        // ~~~~~~~~~~~~~~~~~~~~~~ Statements ~~~~~~~~~~~~~~~~~~~~~~~
        case NODE_BLOCK_STMT:
            if (node->as.block_stmt.statements) {
                for (size_t i = 0; i < node->as.block_stmt.statements->length(); ++i) {
                    visitor.visitChild(&(*node->as.block_stmt.statements)[i]);
                }
            }
            break;
        case NODE_EMPTY_STMT:
            break; // No children
        case NODE_IF_STMT:
            if (node->as.if_stmt) {
                visitor.visitChild(&node->as.if_stmt->condition);
                visitor.visitChild(&node->as.if_stmt->then_block);
                visitor.visitChild(&node->as.if_stmt->else_block);
            }
            break;
        case NODE_IF_EXPR:
            if (node->as.if_expr) {
                visitor.visitChild(&node->as.if_expr->condition);
                visitor.visitChild(&node->as.if_expr->then_expr);
                visitor.visitChild(&node->as.if_expr->else_expr);
            }
            break;
        case NODE_WHILE_STMT:
            if (node->as.while_stmt) {
                visitor.visitChild(&node->as.while_stmt->condition);
                visitor.visitChild(&node->as.while_stmt->body);
                visitor.visitChild(&node->as.while_stmt->iter_expr);
            }
            break;
        case NODE_BREAK_STMT:
        case NODE_CONTINUE_STMT:
            break; // No children
        case NODE_RETURN_STMT:
            visitor.visitChild(&node->as.return_stmt.expression);
            break;
        case NODE_DEFER_STMT:
            visitor.visitChild(&node->as.defer_stmt.statement);
            break;
        case NODE_FOR_STMT:
            if (node->as.for_stmt) {
                visitor.visitChild(&node->as.for_stmt->iterable_expr);
                visitor.visitChild(&node->as.for_stmt->body);
            }
            break;
        case NODE_EXPRESSION_STMT:
            visitor.visitChild(&node->as.expression_stmt.expression);
            break;
        case NODE_PAREN_EXPR:
            visitor.visitChild(&node->as.paren_expr.expr);
            break;
        case NODE_RANGE:
            visitor.visitChild(&node->as.range.start);
            visitor.visitChild(&node->as.range.end);
            break;

        // ~~~~~~~~~~~~~~~~~~~ Expressions ~~~~~~~~~~~~~~~~~~~~~
        case NODE_SWITCH_EXPR:
            if (node->as.switch_expr) {
                visitor.visitChild(&node->as.switch_expr->expression);
                if (node->as.switch_expr->prongs) {
                    for (size_t i = 0; i < node->as.switch_expr->prongs->length(); ++i) {
                        ASTSwitchProngNode* prong = (*node->as.switch_expr->prongs)[i];
                        if (prong->items) {
                            for (size_t j = 0; j < prong->items->length(); ++j) {
                                visitor.visitChild(&(*prong->items)[j]);
                            }
                        }
                        visitor.visitChild(&prong->body);
                    }
                }
            }
            break;
        case NODE_PTR_CAST:
            if (node->as.ptr_cast) {
                visitor.visitChild(&node->as.ptr_cast->target_type);
                visitor.visitChild(&node->as.ptr_cast->expr);
            }
            break;
        case NODE_INT_CAST:
        case NODE_FLOAT_CAST:
            if (node->as.numeric_cast) {
                visitor.visitChild(&node->as.numeric_cast->target_type);
                visitor.visitChild(&node->as.numeric_cast->expr);
            }
            break;
        case NODE_OFFSET_OF:
            if (node->as.offset_of) {
                visitor.visitChild(&node->as.offset_of->type_expr);
            }
            break;

        // ~~~~~~~~~~~~~~~~~~~~ Declarations ~~~~~~~~~~~~~~~~~~~~~~~
        case NODE_VAR_DECL:
            if (node->as.var_decl) {
                visitor.visitChild(&node->as.var_decl->type);
                visitor.visitChild(&node->as.var_decl->initializer);
            }
            break;
        case NODE_PARAM_DECL:
            visitor.visitChild(&node->as.param_decl.type);
            break;
        case NODE_FN_DECL:
            if (node->as.fn_decl) {
                if (node->as.fn_decl->params) {
                    for (size_t i = 0; i < node->as.fn_decl->params->length(); ++i) {
                        visitor.visitChild(&(*node->as.fn_decl->params)[i]);
                    }
                }
                visitor.visitChild(&node->as.fn_decl->return_type);
                visitor.visitChild(&node->as.fn_decl->body);
            }
            break;
        case NODE_STRUCT_FIELD:
            if (node->as.struct_field) {
                visitor.visitChild(&node->as.struct_field->type);
            }
            break;

        // ~~~~~~~~~~~~~~ Container Declarations ~~~~~~~~~~~~~~~~~
        case NODE_STRUCT_DECL:
            if (node->as.struct_decl && node->as.struct_decl->fields) {
                for (size_t i = 0; i < node->as.struct_decl->fields->length(); ++i) {
                    visitor.visitChild(&(*node->as.struct_decl->fields)[i]);
                }
            }
            break;
        case NODE_UNION_DECL:
            if (node->as.union_decl) {
                if (node->as.union_decl->fields) {
                    for (size_t i = 0; i < node->as.union_decl->fields->length(); ++i) {
                        visitor.visitChild(&(*node->as.union_decl->fields)[i]);
                    }
                }
                visitor.visitChild(&node->as.union_decl->tag_type_expr);
            }
            break;
        case NODE_ENUM_DECL:
            if (node->as.enum_decl) {
                visitor.visitChild(&node->as.enum_decl->backing_type);
                if (node->as.enum_decl->fields) {
                    for (size_t i = 0; i < node->as.enum_decl->fields->length(); ++i) {
                        visitor.visitChild(&(*node->as.enum_decl->fields)[i]);
                    }
                }
            }
            break;
        case NODE_ERROR_SET_DEFINITION:
            break; // No children (just strings)
        case NODE_ERROR_SET_MERGE:
            if (node->as.error_set_merge) {
                visitor.visitChild(&node->as.error_set_merge->left);
                visitor.visitChild(&node->as.error_set_merge->right);
            }
            break;

        // ~~~~~~~~~~~~~~~~~~~~~~ Statements ~~~~~~~~~~~~~~~~~~~~~~~
        case NODE_IMPORT_STMT:
            break; // No children

        // ~~~~~~~~~~~~~~~~~~~ Type Expressions ~~~~~~~~~~~~~~~~~~~~
        case NODE_TYPE_NAME:
            break; // No children
        case NODE_POINTER_TYPE:
            visitor.visitChild(&node->as.pointer_type.base);
            break;
        case NODE_ARRAY_TYPE:
            visitor.visitChild(&node->as.array_type.element_type);
            visitor.visitChild(&node->as.array_type.size);
            break;
        case NODE_ERROR_UNION_TYPE:
            if (node->as.error_union_type) {
                visitor.visitChild(&node->as.error_union_type->error_set);
                visitor.visitChild(&node->as.error_union_type->payload_type);
            }
            break;
        case NODE_OPTIONAL_TYPE:
            if (node->as.optional_type) {
                visitor.visitChild(&node->as.optional_type->payload_type);
            }
            break;
        case NODE_FUNCTION_TYPE:
            if (node->as.function_type) {
                if (node->as.function_type->params) {
                    for (size_t i = 0; i < node->as.function_type->params->length(); ++i) {
                        visitor.visitChild(&(*node->as.function_type->params)[i]);
                    }
                }
                visitor.visitChild(&node->as.function_type->return_type);
            }
            break;

        // ~~~~~~~~~~~~~~~~ Error Handling ~~~~~~~~~~~~~~~~~
        case NODE_TRY_EXPR:
            visitor.visitChild(&node->as.try_expr.expression);
            break;
        case NODE_CATCH_EXPR:
            if (node->as.catch_expr) {
                visitor.visitChild(&node->as.catch_expr->payload);
                visitor.visitChild(&node->as.catch_expr->else_expr);
            }
            break;
        case NODE_ORELSE_EXPR:
            if (node->as.orelse_expr) {
                visitor.visitChild(&node->as.orelse_expr->payload);
                visitor.visitChild(&node->as.orelse_expr->else_expr);
            }
            break;
        case NODE_ERRDEFER_STMT:
            visitor.visitChild(&node->as.errdefer_stmt.statement);
            break;

        // ~~~~~~~~~~~~~~~~ Async Operations ~~~~~~~~~~~~~~~~~
        case NODE_ASYNC_EXPR:
            visitor.visitChild(&node->as.async_expr.expression);
            break;
        case NODE_AWAIT_EXPR:
            visitor.visitChild(&node->as.await_expr.expression);
            break;

        // ~~~~~~~~~~~~~~~~ Compile-Time Operations ~~~~~~~~~~~~~~~~~
        case NODE_COMPTIME_BLOCK:
            visitor.visitChild(&node->as.comptime_block.expression);
            break;
    }
}

const char* getTokenSpelling(TokenType op) {
    switch (op) {
        case TOKEN_PLUS: return "+";
        case TOKEN_MINUS: return "-";
        case TOKEN_STAR: return "*";
        case TOKEN_SLASH: return "/";
        case TOKEN_PERCENT: return "%";
        case TOKEN_EQUAL_EQUAL: return "==";
        case TOKEN_BANG_EQUAL: return "!=";
        case TOKEN_LESS: return "<";
        case TOKEN_LESS_EQUAL: return "<=";
        case TOKEN_GREATER: return ">";
        case TOKEN_GREATER_EQUAL: return ">=";
        case TOKEN_AMPERSAND: return "&";
        case TOKEN_PIPE: return "|";
        case TOKEN_CARET: return "^";
        case TOKEN_LARROW2: return "<<";
        case TOKEN_RARROW2: return ">>";
        case TOKEN_BANG: return "!";
        case TOKEN_TILDE: return "~";
        case TOKEN_AND: return "&&";
        case TOKEN_OR: return "||";
        case TOKEN_DOT_ASTERISK: return "*";
        case TOKEN_PLUS_EQUAL: return "+=";
        case TOKEN_MINUS_EQUAL: return "-=";
        case TOKEN_STAR_EQUAL: return "*=";
        case TOKEN_SLASH_EQUAL: return "/=";
        case TOKEN_PERCENT_EQUAL: return "%=";
        case TOKEN_AMPERSAND_EQUAL: return "&=";
        case TOKEN_PIPE_EQUAL: return "|=";
        case TOKEN_CARET_EQUAL: return "^=";
        case TOKEN_LARROW2_EQUAL: return "<<=";
        case TOKEN_RARROW2_EQUAL: return ">>=";
        case TOKEN_PLUSPERCENT: return "+";
        case TOKEN_MINUSPERCENT: return "-";
        case TOKEN_STARPERCENT: return "*";
        default: return "unknown";
    }
}

bool allPathsExit(const ASTNode* node) {
    if (!node) return false;
    switch (node->type) {
        case NODE_RETURN_STMT:
        case NODE_BREAK_STMT:
        case NODE_CONTINUE_STMT:
        case NODE_UNREACHABLE:
            return true;
        case NODE_BLOCK_STMT: {
            const ASTBlockStmtNode& block = node->as.block_stmt;
            if (!block.statements) return false;
            for (size_t i = 0; i < block.statements->length(); ++i) {
                if (allPathsExit((*block.statements)[i])) return true;
            }
            return false;
        }
        case NODE_IF_STMT: {
            const ASTIfStmtNode* if_stmt = node->as.if_stmt;
            if (!if_stmt->else_block) return false;
            return allPathsExit(if_stmt->then_block) && allPathsExit(if_stmt->else_block);
        }
        case NODE_IF_EXPR: {
            const ASTIfExprNode* if_expr = node->as.if_expr;
            if (!if_expr->else_expr) return false;
            return allPathsExit(if_expr->then_expr) && allPathsExit(if_expr->else_expr);
        }
        case NODE_SWITCH_EXPR: {
            const ASTSwitchExprNode* sw = node->as.switch_expr;
            if (!sw->prongs || sw->prongs->length() == 0) return false;
            bool has_else = false;
            for (size_t i = 0; i < sw->prongs->length(); ++i) {
                if ((*sw->prongs)[i]->is_else) has_else = true;
                if (!allPathsExit((*sw->prongs)[i]->body)) return false;
            }
            return has_else; /* Exhaustive switch with all paths exiting */
        }
        case NODE_TRY_EXPR:
            /* try expression exits only on error path, but it doesn't always exit.
               However, if used as a statement 'try ...', it might be considered divergent?
               No, it only returns on error. */
            return false;
        case NODE_CATCH_EXPR:
            return allPathsExit(node->as.catch_expr->payload) && allPathsExit(node->as.catch_expr->else_expr);
        case NODE_ORELSE_EXPR:
            return allPathsExit(node->as.orelse_expr->payload) && allPathsExit(node->as.orelse_expr->else_expr);
        case NODE_EXPRESSION_STMT:
            return allPathsExit(node->as.expression_stmt.expression);
        case NODE_PAREN_EXPR:
            return allPathsExit(node->as.paren_expr.expr);
        default:
            return false;
    }
}
