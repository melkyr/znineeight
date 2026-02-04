#include "generic_catalogue.hpp"
#include "type_system.hpp"
#include <new>
#include <cstring>

GenericCatalogue::GenericCatalogue(ArenaAllocator& arena)
    : arena_(arena) {
    void* mem = arena_.alloc(sizeof(DynamicArray<GenericInstantiation>));
    instantiations_ = new (mem) DynamicArray<GenericInstantiation>(arena_);

    void* def_mem = arena_.alloc(sizeof(DynamicArray<GenericDefinitionInfo>));
    definitions_ = new (def_mem) DynamicArray<GenericDefinitionInfo>(arena_);
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

void GenericCatalogue::addDefinition(const char* name, SourceLocation loc, GenericParamKind kind) {
    if (!name) name = "anonymous";

    // Deduplication
    for (size_t i = 0; i < definitions_->length(); ++i) {
        if (strcmp((*definitions_)[i].function_name, name) == 0) {
            // If already present, maybe we update the kind if it's more "generic"?
            // For now, first one wins or we don't care about multiple generic params of different kinds.
            return;
        }
    }

    GenericDefinitionInfo info;
    info.function_name = name;
    info.location = loc;
    info.kind = kind;
    definitions_->append(info);
}

bool GenericCatalogue::isFunctionGeneric(const char* name) const {
    if (!name) return false;
    for (size_t i = 0; i < definitions_->length(); ++i) {
        if (strcmp((*definitions_)[i].function_name, name) == 0) {
            return true;
        }
    }
    return false;
}

int GenericCatalogue::count() const {
    return (int)instantiations_->length();
}
