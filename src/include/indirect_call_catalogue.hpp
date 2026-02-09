#ifndef INDIRECT_CALL_CATALOGUE_HPP
#define INDIRECT_CALL_CATALOGUE_HPP

#include "common.hpp"
#include "memory.hpp"
#include "ast.hpp"
#include "type_system.hpp"

/**
 * @enum IndirectType
 * @brief Categorizes why a call is considered indirect.
 */
enum IndirectType {
    NOT_INDIRECT,
    INDIRECT_VARIABLE,      // f() where f is a variable holding a function pointer
    INDIRECT_MEMBER,        // obj.f() where f is a function pointer field
    INDIRECT_ARRAY,         // funcs[i]()
    INDIRECT_RETURNED,      // get_func()()
    INDIRECT_COMPLEX        // (a ? f1 : f2)()
};

/**
 * @struct IndirectCallInfo
 * @brief Detailed information about an indirect function call.
 */
struct IndirectCallInfo {
    SourceLocation location;
    IndirectType type;
    Type* function_type;
    const char* context;        // Name of the function containing the call, or "global"
    const char* expr_string;    // String representation of the callee expression
    bool could_be_c89;          // True if it can be represented as a C89 function pointer call
};

/**
 * @class IndirectCallCatalogue
 * @brief Catalogues all indirect function calls for documentation and diagnostics.
 */
class IndirectCallCatalogue {
public:
    IndirectCallCatalogue(ArenaAllocator& arena);

    /**
     * @brief Adds an indirect call entry to the catalogue.
     */
    void addIndirectCall(const IndirectCallInfo& info);

    /**
     * @brief Returns the total number of entries.
     */
    int count() const;

    /**
     * @brief Returns a specific entry by its index.
     */
    const IndirectCallInfo& get(int index) const;

    /**
     * @brief Finds an entry by its source location.
     */
    const IndirectCallInfo* findByLocation(SourceLocation loc) const;

    /**
     * @brief Returns a human-readable reason string for a given indirect type.
     */
    static const char* getReasonString(IndirectType type);

private:
    ArenaAllocator& arena_;
    DynamicArray<IndirectCallInfo>* entries_;
};

#endif // INDIRECT_CALL_CATALOGUE_HPP
