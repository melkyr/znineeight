#ifndef TYPE_REGISTRY_HPP
#define TYPE_REGISTRY_HPP

#include "common.hpp"
#include "module.hpp"
#include "utils.hpp"
#include "platform.hpp"

// Forward declarations
class ArenaAllocator;
struct Module;
struct Type;

/**
 * @struct TypeRegistry
 * @brief A registry to track and deduplicate named types across modules.
 */
struct TypeRegistry {
    struct Entry {
        struct Module* owner;
        const char* name;
        struct Type* type_ptr;
        Entry* next;
    };

    static const int BUCKET_COUNT = 256;
    Entry* buckets[BUCKET_COUNT];
    ArenaAllocator& arena;

    static inline bool sameModule(Module* a, Module* b) {
        if (!a || !b) return false;
        if (a == b) return true;
        // If pointers differ but names match, it's a problem
        if (a->name && b->name && strings_equal(a->name, b->name)) {
            plat_printf_debug("WARNING: Module name collision detected!\n");
            plat_printf_debug("  Module A: %s at %p\n", a->name, (void*)a);
            plat_printf_debug("  Module B: %s at %p\n", b->name, (void*)b);
        }
        return a == b;
    }

    TypeRegistry(ArenaAllocator& arena_ref);

    /**
     * @brief Hashes a module and name pair.
     */
    u32 hash(struct Module* owner, const char* name) const;

    /**
     * @brief Finds a type in the registry.
     */
    struct Type* find(struct Module* owner, const char* name) const;

    enum InsertStatus { OK, DUPLICATE, MISMATCH };

    /**
     * @brief Inserts a type into the registry.
     * @param owner The module that owns the type.
     * @param name The name of the type.
     * @param type_ptr The pointer to the type.
     * @param verify_structure If true, verifies that the type's structure matches if it's a duplicate.
     */
    InsertStatus insert(struct Module* owner, const char* name, struct Type* type_ptr, bool verify_structure = false);

    /**
     * @brief Returns the total number of entries in the registry.
     */
    int get_count() const;

    /**
     * @brief Clears the registry (mainly for testing).
     */
    void clear();
};

#endif // TYPE_REGISTRY_HPP
