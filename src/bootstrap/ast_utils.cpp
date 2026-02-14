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
        case TOKEN_PLUS2: return "++";
        case TOKEN_MINUS2: return "--";
        case TOKEN_BANG: return "!";
        case TOKEN_TILDE: return "~";
        case TOKEN_AND: return "&&";
        case TOKEN_OR: return "||";
        default: return "unknown";
    }
}
