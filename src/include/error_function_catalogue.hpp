#ifndef ERROR_FUNCTION_CATALOGUE_HPP
#define ERROR_FUNCTION_CATALOGUE_HPP

#include "common.hpp"
#include "memory.hpp"
#include "lexer.hpp" // For SourceLocation
#include "type_system.hpp"

struct ErrorFunctionInfo {
    const char* name;
    Type* return_type;
    Type* payload_type;
    SourceLocation location;
    bool is_generic;
    int param_count;
    size_t error_union_size;
    bool msvc6_stack_safe;
};

class ErrorFunctionCatalogue {
public:
    ErrorFunctionCatalogue(ArenaAllocator& arena);
    void addErrorFunction(const char* name, Type* return_type, Type* payload_type, SourceLocation loc, bool is_generic, int param_count, size_t error_union_size, bool msvc6_stack_safe);
    int count() const;
    const DynamicArray<ErrorFunctionInfo>* getFunctions() const { return functions_; }

private:
    ArenaAllocator& arena_;
    DynamicArray<ErrorFunctionInfo>* functions_;
};

#endif // ERROR_FUNCTION_CATALOGUE_HPP
