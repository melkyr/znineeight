#ifndef MODULE_HPP
#define MODULE_HPP

#include "common.hpp"
#include "memory.hpp"
#include "error_set_catalogue.hpp"
#include "generic_catalogue.hpp"
#include "error_function_catalogue.hpp"
#include "try_expression_catalogue.hpp"
#include "catch_expression_catalogue.hpp"
#include "orelse_expression_catalogue.hpp"
#include "extraction_analysis_catalogue.hpp"
#include "errdefer_catalogue.hpp"
#include "indirect_call_catalogue.hpp"

struct ASTNode;

/**
 * @struct Module
 * @brief Represents a single Zig module (corresponding to a source file).
 */
class SymbolTable;

/**
 * @struct Module
 * @brief Represents a single Zig module (corresponding to a source file).
 */
struct Module {
    const char* name;     /* Interned module name */
    const char* filename; /* Original filename */
    ASTNode* ast_root;    /* Root of the AST for this module */
    u32 file_id;          /* ID in SourceManager */
    SymbolTable* symbols; /* Per-module symbol table */
    DynamicArray<const char*> imports;
    DynamicArray<ASTNode*> import_nodes;
    bool is_analyzed;

    // Per-module catalogues
    ErrorSetCatalogue error_set_catalogue;
    GenericCatalogue generic_catalogue;
    ErrorFunctionCatalogue error_function_catalogue;
    TryExpressionCatalogue try_expression_catalogue;
    CatchExpressionCatalogue catch_expression_catalogue;
    OrelseExpressionCatalogue orelse_expression_catalogue;
    ExtractionAnalysisCatalogue extraction_analysis_catalogue;
    ErrDeferCatalogue errdefer_catalogue;
    IndirectCallCatalogue indirect_call_catalogue;
    DynamicArray<const char*> emitted_types_cache;

    Module(ArenaAllocator& arena)
        : imports(arena),
          import_nodes(arena),
          error_set_catalogue(arena),
          generic_catalogue(arena),
          error_function_catalogue(arena),
          try_expression_catalogue(arena),
          catch_expression_catalogue(arena),
          orelse_expression_catalogue(arena),
          extraction_analysis_catalogue(arena),
          errdefer_catalogue(arena),
          indirect_call_catalogue(arena),
          emitted_types_cache(arena) {
        name = NULL;
        filename = NULL;
        ast_root = NULL;
        file_id = 0;
        symbols = NULL;
        is_analyzed = false;
    }
};

#endif // MODULE_HPP
