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
