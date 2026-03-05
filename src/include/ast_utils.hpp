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

/**
 * @brief Returns the string representation of a token type, typically for operators.
 * @param op The token type.
 * @return The string representation.
 */
const char* getTokenSpelling(TokenType op);

/**
 * @brief Checks if a node and its sub-paths are guaranteed to exit the current block.
 * @param node The node to check.
 * @return True if the node is guaranteed to exit (return, break, continue).
 */
bool allPathsExit(const ASTNode* node);

/**
 * @brief Visitor interface for AST child traversal.
 *
 * This interface is used by forEachChild to visit each child pointer
 * within an AST node. The visitor receives a pointer to the slot
 * (ASTNode**), allowing it to modify the child in-place if needed.
 */
struct ChildVisitor {
    virtual ~ChildVisitor() {}
    virtual void visitChild(ASTNode** child_slot) = 0;
};

/**
 * @brief Iterates over all children of an AST node and calls the visitor for each child slot.
 *
 * This function provides a uniform way to traverse the AST tree structure.
 * It visits every syntactic and semantic ASTNode pointer within the given node,
 * including those nested in intermediate structures like DynamicArrays.
 *
 * @param node The node whose children should be visited.
 * @param visitor The visitor to call for each child slot.
 */
void forEachChild(ASTNode* node, ChildVisitor& visitor);

/**
 * @brief Deep-clones an AST node and all its children.
 *
 * This function creates a deep copy of the AST structure starting from the given node.
 * Semantic information (resolved_type, symbol pointers) is shared via shallow copy.
 * Intermediate structures like DynamicArrays are also deep-cloned.
 *
 * @param node The node to clone.
 * @param arena The arena allocator to use for new nodes and structures.
 * @return A pointer to the newly cloned ASTNode, or NULL if the input was NULL.
 */
ASTNode* cloneASTNode(ASTNode* node, ArenaAllocator* arena);

#endif // AST_UTILS_HPP
