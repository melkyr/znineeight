#include "debug_helpers.hpp"
#include "platform.hpp"

/**
 * @brief Prints a human-readable representation of an AST node to the debug output.
 * @param node The AST node to print.
 */
void plat_print_ast_node(const ASTNode* node) {
    char buf[128];
    if (!node) {
#ifdef Z98_ENABLE_DEBUG_LOGS
        plat_print_debug("ASTNode: NULL\n");
#endif
        return;
    }

#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_print_debug("ASTNode: ");
#endif
#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_print_debug(AST_NODE_TYPE_NAME(node->type));
#endif

#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_print_debug(" (Loc: ");
#endif
    plat_u64_to_string((u64)node->loc.line, buf, sizeof(buf));
#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_print_debug(buf);
#endif
#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_print_debug(":");
#endif
    plat_u64_to_string((u64)node->loc.column, buf, sizeof(buf));
#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_print_debug(buf);
#endif
#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_print_debug(")\n");
#endif
}
