#include "generic_catalogue.hpp"
#include "type_system.hpp"
#include "platform.hpp"
#include <new>

GenericCatalogue::GenericCatalogue(ArenaAllocator& arena)
    : arena_(arena) {
    void* mem = arena_.alloc(sizeof(DynamicArray<GenericInstantiation>));
    if (mem == NULL) plat_abort();
    instantiations_ = new (mem) DynamicArray<GenericInstantiation>(arena_);

    void* def_mem = arena_.alloc(sizeof(DynamicArray<GenericDefinitionInfo>));
    if (def_mem == NULL) plat_abort();
    definitions_ = new (def_mem) DynamicArray<GenericDefinitionInfo>(arena_);
}

static bool areGenericParamsEqual(DynamicArray<GenericParamInfo>* a, DynamicArray<GenericParamInfo>* b) {
    if (!a && !b) return true;
    if (!a || !b) return false;
    if (a->length() != b->length()) return false;

    for (size_t i = 0; i < a->length(); ++i) {
        const GenericParamInfo& pa = (*a)[i];
        const GenericParamInfo& pb = (*b)[i];

        if (pa.kind != pb.kind) return false;
        switch (pa.kind) {
            case GENERIC_PARAM_TYPE:
                if (!areTypesEqual(pa.type_value, pb.type_value)) return false;
                break;
            case GENERIC_PARAM_COMPTIME_INT:
                if (pa.int_value != pb.int_value) return false;
                break;
            case GENERIC_PARAM_COMPTIME_FLOAT:
                if (pa.float_value != pb.float_value) return false;
                break;
            default:
                break;
        }
    }
    return true;
}

void GenericCatalogue::addInstantiation(const char* name, const char* mangled_name, DynamicArray<GenericParamInfo>* params, DynamicArray<Type*>* arg_types, int count, SourceLocation loc, const char* module, bool is_explicit, u32 param_hash) {
    if (!name) name = "anonymous";
    if (!module) module = "unknown";

    // Deduplication using hash, name, and deep comparison of params
    for (size_t i = 0; i < instantiations_->length(); ++i) {
        const GenericInstantiation& existing = (*instantiations_)[i];
        if (existing.param_hash == param_hash &&
            existing.param_count == count &&
            plat_strcmp(existing.function_name, name) == 0 &&
            plat_strcmp(existing.module, module) == 0) {

            if (areGenericParamsEqual(existing.params, params)) {
                return;
            }
        }
    }

    GenericInstantiation inst;
    inst.function_name = name;
    inst.mangled_name = mangled_name;
    inst.param_count = count;

    void* params_mem = arena_.alloc(sizeof(DynamicArray<GenericParamInfo>));
    if (!params_mem) plat_abort();
    inst.params = new (params_mem) DynamicArray<GenericParamInfo>(arena_);

    void* args_mem = arena_.alloc(sizeof(DynamicArray<Type*>));
    if (!args_mem) plat_abort();
    inst.arg_types = new (args_mem) DynamicArray<Type*>(arena_);

    for (int i = 0; i < count; ++i) {
        if (params) {
            inst.params->append((*params)[i]);
        }
        if (arg_types) {
            inst.arg_types->append((*arg_types)[i]);
        } else {
            inst.arg_types->append(NULL);
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
                         other_inst.params,
                         other_inst.arg_types,
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
