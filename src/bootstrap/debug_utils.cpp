#include "debug_helpers.hpp"
#include "platform.hpp"

/**
 * @brief Prints a human-readable representation of an AST node to the debug output.
 * @param node The AST node to print.
 */
void plat_print_ast_node(const ASTNode* node) {
    char buf[128];
    if (!node) {
        plat_print_debug("ASTNode: NULL\n");
        return;
    }

    plat_print_debug("ASTNode: ");
    plat_print_debug(AST_NODE_TYPE_NAME(node->type));

    plat_print_debug(" (Loc: ");
    plat_u64_to_string((u64)node->loc.line, buf, sizeof(buf));
    plat_print_debug(buf);
    plat_print_debug(":");
    plat_u64_to_string((u64)node->loc.column, buf, sizeof(buf));
    plat_print_debug(buf);
    plat_print_debug(")\n");
}
