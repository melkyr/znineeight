#ifndef NAME_MANGLER_HPP
#define NAME_MANGLER_HPP

#include "common.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "generic_catalogue.hpp"

struct Type;

class NameMangler {
public:
    NameMangler(ArenaAllocator& arena, StringInterner& interner);

    /**
     * @brief Mangles a function name based on its base name and generic parameters.
     */
    const char* mangleFunction(const char* name,
                               const GenericParamInfo* params,
                               int param_count,
                               const char* module = NULL);

    /**
     * @brief Mangles a type into a C-safe string representation.
     */
    const char* mangleType(Type* type);

private:
    ArenaAllocator& arena_;
    StringInterner& interner_;

    void sanitizeForC89(char* buffer);
    bool isCKeyword(const char* str);
    bool isReservedName(const char* str);
};

#endif // NAME_MANGLER_HPP
