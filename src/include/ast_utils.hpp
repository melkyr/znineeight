#ifndef AST_UTILS_HPP
#define AST_UTILS_HPP

#include "ast.hpp"

class SymbolTable;

/**
 * @brief Checks if an AST node represents a type expression.
 * @param node The node to check.
 * @param symbols The symbol table for looking up identifiers.
 * @return True if the node represents a type, false otherwise.
 */
bool isTypeExpression(ASTNode* node, SymbolTable& symbols);

#endif // AST_UTILS_HPP
