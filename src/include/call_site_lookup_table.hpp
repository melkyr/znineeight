#ifndef CALL_SITE_LOOKUP_TABLE_HPP
#define CALL_SITE_LOOKUP_TABLE_HPP

#include "common.hpp"
#include "memory.hpp"
#include "ast.hpp"

/**
 * @enum CallType
 * @brief Categorizes the type of function call for resolution purposes.
 */
enum CallType {
    CALL_DIRECT,
    CALL_GENERIC,
    CALL_RECURSIVE,
    CALL_INDIRECT
};

/**
 * @enum ResolutionResult
 * @brief Represents the outcome of an attempt to resolve a call site.
 */
enum ResolutionResult {
    RESOLVED,
    UNRESOLVED_SYMBOL,
    UNRESOLVED_GENERIC,
    INDIRECT_REJECTED,
    C89_INCOMPATIBLE,
    BUILTIN_REJECTED,
    FORWARD_REFERENCE
};

/**
 * @struct CallSiteEntry
 * @brief Stores resolution information for a single function call site.
 */
struct CallSiteEntry {
    ASTNode* call_node;        // Pointer to ASTFunctionCallNode
    const char* mangled_name;  // Resolved name (arena-allocated)
    const char* context;       // "function_name" or "global"
    CallType call_type;
    bool resolved;
    const char* error_if_unresolved;
};

/**
 * @class CallSiteLookupTable
 * @brief Tracks all function call sites and their resolved mangled names.
 */
class CallSiteLookupTable {
public:
    CallSiteLookupTable(ArenaAllocator& arena);

    /**
     * @brief Adds a new call site entry to the table.
     * @return The index of the newly added entry.
     */
    int addEntry(ASTNode* call_node, const char* context);

    /**
     * @brief Resolves an entry with its mangled name.
     */
    void resolveEntry(int id, const char* mangled_name, CallType type = CALL_DIRECT);

    /**
     * @brief Marks an entry as unresolved with a specific reason.
     */
    void markUnresolved(int id, const char* reason, CallType type = CALL_INDIRECT);

    /**
     * @brief Returns the total number of entries in the table.
     */
    int count() const;

    /**
     * @brief Returns the number of entries that haven't been resolved yet.
     */
    int getUnresolvedCount() const;

    /**
     * @brief Returns a specific entry by its index.
     */
    const CallSiteEntry& getEntry(int id) const;

    /**
     * @brief Finds an entry by its ASTNode pointer.
     * @return A pointer to the entry, or NULL if not found.
     */
    const CallSiteEntry* findByCallNode(ASTNode* call_node) const;

    /**
     * @brief Prints all unresolved call sites for diagnostic purposes.
     */
    void printUnresolved() const;

private:
    ArenaAllocator& arena_;
    DynamicArray<CallSiteEntry>* entries_;
};

#endif // CALL_SITE_LOOKUP_TABLE_HPP
