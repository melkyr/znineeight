#include "error_registry.hpp"
#include "platform.hpp"
#include <new>

GlobalErrorRegistry::GlobalErrorRegistry(ArenaAllocator& arena)
    : arena_(arena) {
    void* mem = arena_.alloc(sizeof(DynamicArray<ErrorTag>));
    if (mem == NULL) plat_abort();
    tags_ = new (mem) DynamicArray<ErrorTag>(arena_);
}

int GlobalErrorRegistry::getOrAddTag(const char* name) {
    // Check if tag already exists (linear scan with pointer comparison)
    for (size_t i = 0; i < tags_->length(); ++i) {
        if ((*tags_)[i].name == name) {
            return (*tags_)[i].id;
        }
    }

    // Not found, add it
    ErrorTag new_tag;
    new_tag.name = name;
    new_tag.id = (int)(tags_->length() + 1); // IDs start at 1
    tags_->append(new_tag);
    return new_tag.id;
}

int GlobalErrorRegistry::getTagId(const char* name) const {
    for (size_t i = 0; i < tags_->length(); ++i) {
        if ((*tags_)[i].name == name) {
            return (*tags_)[i].id;
        }
    }
    return 0; // Not found
}
