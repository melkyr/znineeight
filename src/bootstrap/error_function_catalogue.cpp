#include "error_function_catalogue.hpp"
#include "memory.hpp"
#include <string.h>

ErrorFunctionCatalogue::ErrorFunctionCatalogue(ArenaAllocator& arena)
    : arena_(arena), functions_(NULL), count_(0), capacity_(0) {}

void ErrorFunctionCatalogue::addFunction(const char* name, SourceLocation location, Type* return_type, bool is_generic) {
    if (count_ >= capacity_) {
        size_t new_capacity = (capacity_ == 0) ? 8 : capacity_ * 2;
        ErrorFunctionInfo* new_functions = (ErrorFunctionInfo*)arena_.alloc(sizeof(ErrorFunctionInfo) * new_capacity);
        if (functions_) {
            memcpy(new_functions, functions_, sizeof(ErrorFunctionInfo) * count_);
        }
        functions_ = new_functions;
        capacity_ = new_capacity;
    }

    functions_[count_].name = name;
    functions_[count_].location = location;
    functions_[count_].return_type = return_type;
    functions_[count_].is_generic = is_generic;
    count_++;
}

const ErrorFunctionInfo& ErrorFunctionCatalogue::getFunction(size_t index) const {
    return functions_[index];
}
