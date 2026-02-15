#ifndef MODULE_HPP
#define MODULE_HPP

#include "common.hpp"

struct ASTNode;

/**
 * @struct Module
 * @brief Represents a single Zig module (corresponding to a source file).
 */
struct Module {
    const char* name;     /* Interned module name */
    const char* filename; /* Original filename */
    ASTNode* ast_root;    /* Root of the AST for this module */
    u32 file_id;          /* ID in SourceManager */
};

#endif // MODULE_HPP
