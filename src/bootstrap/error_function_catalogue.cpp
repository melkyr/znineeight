#include "error_function_catalogue.hpp"
#include <new>

ErrorFunctionCatalogue::ErrorFunctionCatalogue(ArenaAllocator& arena) : arena_(arena) {
    void* mem = arena_.alloc(sizeof(DynamicArray<ErrorFunctionInfo>));
    functions_ = new (mem) DynamicArray<ErrorFunctionInfo>(arena_);
}

void ErrorFunctionCatalogue::addErrorFunction(const char* name, Type* return_type, SourceLocation loc, bool is_generic, int param_count) {
    ErrorFunctionInfo info;
    info.name = name; // Assume it's interned or we'll copy it later
    info.return_type = return_type;
    info.location = loc;
    info.is_generic = is_generic;
    info.param_count = param_count;
    functions_->append(info);
}

int ErrorFunctionCatalogue::count() const {
    return (int)functions_->length();
}
