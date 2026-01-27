#include "generic_catalogue.hpp"
#include "type_system.hpp"
#include <new>
#include <cstring>

GenericCatalogue::GenericCatalogue(ArenaAllocator& arena)
    : arena_(arena) {
    void* mem = arena_.alloc(sizeof(DynamicArray<GenericInstantiation>));
    instantiations_ = new (mem) DynamicArray<GenericInstantiation>(arena_);
}

void GenericCatalogue::addInstantiation(const char* name, Type** types, int count, SourceLocation loc) {
    if (!name) name = "anonymous";

    // Deduplication
    for (size_t i = 0; i < instantiations_->length(); ++i) {
        const GenericInstantiation& existing = (*instantiations_)[i];
        if (strcmp(existing.function_name, name) == 0 && existing.type_count == count) {
            bool match = true;
            for (int j = 0; j < count; ++j) {
                if (existing.type_arguments[j] != types[j]) {
                    match = false;
                    break;
                }
            }
            if (match) return;
        }
    }

    GenericInstantiation inst;
    inst.function_name = name;
    inst.type_count = (count > 4) ? 4 : count;
    for (int i = 0; i < inst.type_count; ++i) {
        inst.type_arguments[i] = types[i];
    }
    inst.location = loc;
    instantiations_->append(inst);
}

int GenericCatalogue::count() const {
    return (int)instantiations_->length();
}
