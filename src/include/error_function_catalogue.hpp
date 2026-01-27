#ifndef ERROR_FUNCTION_CATALOGUE_HPP
#define ERROR_FUNCTION_CATALOGUE_HPP

#include "common.hpp"
#include "memory.hpp"
#include "lexer.hpp" // For SourceLocation
#include "type_system.hpp"

struct ErrorFunctionInfo {
    const char* name;
    Type* return_type;
    SourceLocation location;
    bool is_generic;
    int param_count;
};

class ErrorFunctionCatalogue {
public:
    ErrorFunctionCatalogue(ArenaAllocator& arena);
    void addErrorFunction(const char* name, Type* return_type, SourceLocation loc, bool is_generic, int param_count);
    int count() const;
    const DynamicArray<ErrorFunctionInfo>* getFunctions() const { return functions_; }

private:
    ArenaAllocator& arena_;
    DynamicArray<ErrorFunctionInfo>* functions_;
};

#endif // ERROR_FUNCTION_CATALOGUE_HPP
