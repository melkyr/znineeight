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
