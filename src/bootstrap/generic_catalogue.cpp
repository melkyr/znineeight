#include "generic_catalogue.hpp"
#include "type_system.hpp"
#include "platform.hpp"
#include <new>

GenericCatalogue::GenericCatalogue(ArenaAllocator& arena)
    : arena_(arena) {
    void* mem = arena_.alloc(sizeof(DynamicArray<GenericInstantiation>));
    if (!mem) plat_abort();
    instantiations_ = new (mem) DynamicArray<GenericInstantiation>(arena_);

    void* def_mem = arena_.alloc(sizeof(DynamicArray<GenericDefinitionInfo>));
    if (!def_mem) plat_abort();
    definitions_ = new (def_mem) DynamicArray<GenericDefinitionInfo>(arena_);
}

void GenericCatalogue::addInstantiation(const char* name, const char* mangled_name, GenericParamInfo* params, Type** arg_types, int count, SourceLocation loc, const char* module, bool is_explicit, u32 param_hash) {
    if (!name) name = "anonymous";
    if (!module) module = "unknown";

    // Deduplication using hash and name
    for (size_t i = 0; i < instantiations_->length(); ++i) {
        const GenericInstantiation& existing = (*instantiations_)[i];
        if (existing.param_hash == param_hash && plat_strcmp(existing.function_name, name) == 0 &&
            existing.param_count == count && plat_strcmp(existing.module, module) == 0) {
            return;
        }
    }

    GenericInstantiation inst;
    inst.function_name = name;
    inst.mangled_name = mangled_name;
    inst.param_count = (count > 4) ? 4 : count;
    for (int i = 0; i < inst.param_count; ++i) {
        inst.params[i] = params[i];
        if (arg_types) {
            inst.arg_types[i] = arg_types[i];
        } else {
            inst.arg_types[i] = NULL;
        }
    }
    inst.location = loc;
    inst.module = module;
    inst.is_explicit = is_explicit;
    inst.param_hash = param_hash;
    inst.specialization_id = (int)instantiations_->length();

    instantiations_->append(inst);
}

void GenericCatalogue::addDefinition(const char* name, SourceLocation loc, GenericDefinitionKind kind) {
    if (!name) name = "anonymous";

    // Deduplication
    for (size_t i = 0; i < definitions_->length(); ++i) {
        if (plat_strcmp((*definitions_)[i].function_name, name) == 0) {
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

void GenericCatalogue::mergeFrom(const GenericCatalogue& other, const char* module_prefix) {
    // For instantiations
    const DynamicArray<GenericInstantiation>* other_insts = other.getInstantiations();
    for (size_t i = 0; i < other_insts->length(); ++i) {
        const GenericInstantiation& other_inst = (*other_insts)[i];

        // In a real merge, we might prefix the name if module_prefix is provided
        // For now, we just add them to our own list, deduplicating
        addInstantiation(other_inst.function_name, other_inst.mangled_name,
                         (GenericParamInfo*)other_inst.params,
                         (Type**)other_inst.arg_types,
                         other_inst.param_count, other_inst.location,
                         other_inst.module, other_inst.is_explicit, other_inst.param_hash);
    }

    // For definitions
    const DynamicArray<GenericDefinitionInfo>* other_defs = other.getDefinitions();
    for (size_t i = 0; i < other_defs->length(); ++i) {
        const GenericDefinitionInfo& other_def = (*other_defs)[i];
        addDefinition(other_def.function_name, other_def.location, other_def.kind);
    }
}

bool GenericCatalogue::isFunctionGeneric(const char* name) const {
    if (!name) return false;
    for (size_t i = 0; i < definitions_->length(); ++i) {
        if (plat_strcmp((*definitions_)[i].function_name, name) == 0) {
            return true;
        }
    }
    return false;
}

const GenericInstantiation* GenericCatalogue::findInstantiation(const char* name, SourceLocation loc) const {
    if (!name) return NULL;

    for (size_t i = 0; i < instantiations_->length(); ++i) {
        const GenericInstantiation& inst = (*instantiations_)[i];

        if (plat_strcmp(inst.function_name, name) == 0) {
            if (inst.location.line == loc.line &&
                inst.location.column == loc.column &&
                inst.location.file_id == loc.file_id) {
                return &inst;
            }
        }
    }
    return NULL;
}

int GenericCatalogue::count() const {
    return (int)instantiations_->length();
}
