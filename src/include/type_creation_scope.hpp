#ifndef TYPE_CREATION_SCOPE_HPP
#define TYPE_CREATION_SCOPE_HPP

#include "type_registry.hpp"
#include "platform.hpp"

/**
 * @class TypeCreationScope
 * @brief RAII guard to ensure type registration safety.
 */
class TypeCreationScope {
    TypeRegistry& registry_ref;
    struct Module* owner;
    const char* name;
    struct Type* created_type;
    bool committed;

public:
    TypeCreationScope(TypeRegistry& reg, struct Module* own, const char* n)
        : registry_ref(reg), owner(own), name(n), created_type(NULL), committed(false) {}

    ~TypeCreationScope() {
        if (!committed && created_type != NULL) {
            // Log warning: Type creation aborted
            plat_print_debug("Type creation aborted for ");
            plat_print_debug(name);
            plat_print_debug("\n");
        }
    }

    void set_type(struct Type* t) {
        created_type = t;
    }

    bool try_commit() {
        if (created_type == NULL) return false;

        TypeRegistry::InsertStatus status = registry_ref.insert(owner, name, created_type, true);
        if (status == TypeRegistry::OK) {
            committed = true;
            return true;
        } else if (status == TypeRegistry::DUPLICATE) {
            // Return existing one instead
            created_type = registry_ref.find(owner, name);
            committed = true;
            return true;
        } else {
            return false; // Mismatch error
        }
    }

    struct Type* get_final_type() {
        return created_type;
    }
};

#endif // TYPE_CREATION_SCOPE_HPP
