#ifndef NAME_MANGLER_HPP
#define NAME_MANGLER_HPP

#include "common.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "generic_catalogue.hpp"

struct Type;

class CompilationUnit;

class NameMangler {
public:
    NameMangler(ArenaAllocator& arena, StringInterner& interner, CompilationUnit& unit);

    /**
     * @brief Mangles a function name based on its base name and generic parameters.
     */
    const char* mangleFunction(const char* name,
                               DynamicArray<GenericParamInfo>* params,
                               int param_count,
                               Module* mod = NULL);

    /**
     * @brief Mangles a type into a C-safe string representation.
     */
    const char* mangleType(Type* type);

    /**
     * @brief Mangles a named type with a module prefix.
     */
    const char* mangleTypeName(const char* name, Module* mod);

    /**
     * @brief The new core mangling logic.
     */
    const char* mangle(char kind, Module* mod, const char* local_name);

private:
    ArenaAllocator& arena_;
    StringInterner& interner_;
    CompilationUnit& unit_;
};

#endif // NAME_MANGLER_HPP
