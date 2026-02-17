#include "error_function_catalogue.hpp"
#include <new>

ErrorFunctionCatalogue::ErrorFunctionCatalogue(ArenaAllocator& arena) : arena_(arena) {
    void* mem = arena_.alloc(sizeof(DynamicArray<ErrorFunctionInfo>));
    if (mem == NULL) plat_abort();
   functions_ = new (mem) DynamicArray<ErrorFunctionInfo>(arena_);
}

void ErrorFunctionCatalogue::addErrorFunction(const char* name, Type* return_type, Type* payload_type, SourceLocation loc, bool is_generic, int param_count, size_t error_union_size, bool msvc6_stack_safe) {
    ErrorFunctionInfo info;
    info.name = name; // Assume it's interned or we'll copy it later
    info.return_type = return_type;
    info.payload_type = payload_type;
    info.location = loc;
    info.is_generic = is_generic;
    info.param_count = param_count;
    info.error_union_size = error_union_size;
    info.msvc6_stack_safe = msvc6_stack_safe;
    functions_->append(info);
}

int ErrorFunctionCatalogue::count() const {
    return (int)functions_->length();
}
