#include "type_registry.hpp"
#include "memory.hpp"
#include "module.hpp"
#include "type_system.hpp"
#include "utils.hpp"
#include "platform.hpp"

TypeRegistry::TypeRegistry(ArenaAllocator& arena_ref) : arena(arena_ref) {
    for (int i = 0; i < BUCKET_COUNT; ++i) {
        buckets[i] = NULL;
    }
}

u32 TypeRegistry::hash(const char* module_path, const char* name) const {
    u32 h = 2166136261u;
    if (module_path) {
        for (const char* p = module_path; *p; ++p) {
            h = (h ^ (u8)*p) * 16777619u;
        }
    }
    h = (h ^ 0x1F) * 16777619u; // separator byte 0x1F (unit separator)
    if (name) {
        for (const char* p = name; *p; ++p) {
            h = (h ^ (u8)*p) * 16777619u;
        }
    }
    return h % BUCKET_COUNT;
}

Type* TypeRegistry::find(const char* module_path, const char* name) const {
#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("TypeRegistry: Find %s in module path %s\n", name, module_path ? module_path : "NULL");
#endif
    u32 h = hash(module_path, name);
    Entry* entry = buckets[h];
    while (entry) {
        // Since module_path is interned, we can use pointer equality
        if (entry->module_path == module_path && strings_equal(entry->name, name)) {
            return entry->type_ptr;
        }
        entry = entry->next;
    }
    return NULL;
}

TypeRegistry::InsertStatus TypeRegistry::insert(const char* module_path, const char* name, Type* type_ptr, bool verify_structure) {
    u32 h = hash(module_path, name);
    Entry* entry = buckets[h];
    while (entry) {
        if (entry->module_path == module_path && strings_equal(entry->name, name)) {
            if (entry->type_ptr == type_ptr) {
                return DUPLICATE;
            }
            if (verify_structure) {
                // In a more complex implementation, we'd check structural equality here.
                // For now, if pointers differ, it's a mismatch for a named type.
                return MISMATCH;
            }
            return DUPLICATE;
        }
        entry = entry->next;
    }

    Entry* new_entry = (Entry*)arena.alloc(sizeof(Entry));
    new_entry->module_path = module_path;
    new_entry->name = arena.allocString(name);
    new_entry->type_ptr = type_ptr;
    new_entry->next = buckets[h];
    buckets[h] = new_entry;

#ifdef DEBUG
    if (type_ptr->owner_module) {
        Z98_ASSERT(module_path == type_ptr->owner_module->canonical_path);
    }
#endif

    return OK;
}

int TypeRegistry::get_count() const {
    int count = 0;
    for (int i = 0; i < BUCKET_COUNT; ++i) {
        Entry* entry = buckets[i];
        while (entry) {
            count++;
            entry = entry->next;
        }
    }
    return count;
}

void TypeRegistry::clear() {
    for (int i = 0; i < BUCKET_COUNT; ++i) {
        buckets[i] = NULL;
    }
}
