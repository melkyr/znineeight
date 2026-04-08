#include "type_registry.hpp"
#include "memory.hpp"
#include "module.hpp"
#include "type_system.hpp"
#include "utils.hpp"

TypeRegistry::TypeRegistry(ArenaAllocator& arena_ref) : arena(arena_ref) {
    for (int i = 0; i < BUCKET_COUNT; ++i) {
        buckets[i] = NULL;
    }
}

u32 TypeRegistry::hash(Module* owner, const char* name) const {
    u32 h = (u32)((size_t)owner);
    if (name) {
        for (const char* p = name; *p; ++p) {
            h = h * 31 + (u32)(*p);
        }
    }
    return h % BUCKET_COUNT;
}

Type* TypeRegistry::find(Module* owner, const char* name) const {
#ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("TypeRegistry: Find %s in module %s (%p)\n", name, owner ? owner->name : "NULL", (void*)owner);
#endif
    u32 h = hash(owner, name);
    Entry* entry = buckets[h];
    while (entry) {
        if (sameModule(entry->owner, owner) && strings_equal(entry->name, name)) {
            return entry->type_ptr;
        }
        entry = entry->next;
    }
    return NULL;
}

TypeRegistry::InsertStatus TypeRegistry::insert(Module* owner, const char* name, Type* type_ptr, bool verify_structure) {
    u32 h = hash(owner, name);
    Entry* entry = buckets[h];
    while (entry) {
        if (entry->owner == owner && strings_equal(entry->name, name)) {
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
    new_entry->owner = owner;
    new_entry->name = arena.allocString(name);
    new_entry->type_ptr = type_ptr;
    new_entry->next = buckets[h];
    buckets[h] = new_entry;

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
