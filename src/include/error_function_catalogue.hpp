#ifndef RETROZIG_ERROR_FUNCTION_CATALOGUE_HPP
#define RETROZIG_ERROR_FUNCTION_CATALOGUE_HPP

#include "common.hpp"
#include "source_manager.hpp"
#include "type_system.hpp"

struct ErrorFunctionInfo {
    const char* name;
    SourceLocation location;
    Type* return_type;
    bool is_generic;
};

class ErrorFunctionCatalogue {
public:
    ErrorFunctionCatalogue(class ArenaAllocator& arena);
    void addFunction(const char* name, SourceLocation location, Type* return_type, bool is_generic);
    size_t getCount() const { return count_; }
    const ErrorFunctionInfo& getFunction(size_t index) const;

private:
    class ArenaAllocator& arena_;
    ErrorFunctionInfo* functions_;
    size_t count_;
    size_t capacity_;
};

#endif
