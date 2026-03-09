#ifndef METADATA_PREPARATION_PASS_HPP
#define METADATA_PREPARATION_PASS_HPP

#include "compilation_unit.hpp"

/**
 * @class MetadataPreparationPass
 * @brief Performs a post-typechecking pass to compute and cache metadata needed for codegen.
 *
 * This pass:
 * 1. Transitively collects all types reachable from public symbols in each module.
 * 2. Ensures mangled names (c_name) are computed and MSVC 6.0 compatible (31 chars).
 * 3. Verifies that all types have fully computed sizes and alignments.
 * 4. Populates module->header_types for use during C header emission.
 */
class MetadataPreparationPass {
public:
    MetadataPreparationPass(CompilationUnit& unit);

    /**
     * @brief Executes the pass across all modules in the compilation unit.
     */
    void run();

private:
    CompilationUnit& unit_;

    /**
     * @brief Collects all types reachable from a starting type and adds them to a module's header_types.
     */
    void collectReachableTypes(Module* mod, Type* type, DynamicArray<Type*>& visited);

    /**
     * @brief Ensures a type has a valid mangled name and computed layout.
     */
    void prepareTypeMetadata(Module* mod, Type* type);

    /**
     * @brief Checks if a type should be included in the header type list.
     */
    bool isHeaderType(Type* type);

    /**
     * @brief Collects static functions that need forward declarations in the .c file.
     */
    void collectStaticFunctions(Module* mod);
};

#endif // METADATA_PREPARATION_PASS_HPP
