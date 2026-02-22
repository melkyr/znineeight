#ifndef ERROR_REGISTRY_HPP
#define ERROR_REGISTRY_HPP

#include "common.hpp"
#include "memory.hpp"

/**
 * @struct ErrorTag
 * @brief Represents a single error tag in the global registry.
 */
struct ErrorTag {
    const char* name; // interned string
    int id;
};

/**
 * @class GlobalErrorRegistry
 * @brief Manages a global mapping of error tag names to unique integer IDs.
 */
class GlobalErrorRegistry {
public:
    GlobalErrorRegistry(ArenaAllocator& arena);

    /**
     * @brief Gets the ID for a tag name, adding it if not already present.
     * @param name The interned string name of the tag.
     * @return The unique integer ID for the tag (starts at 1).
     */
    int getOrAddTag(const char* name);

    /**
     * @brief Returns the ID for a tag name, or 0 if not present.
     */
    int getTagId(const char* name) const;

    /**
     * @brief Returns all registered tags.
     */
    const DynamicArray<ErrorTag>& getTags() const { return *tags_; }

private:
    ArenaAllocator& arena_;
    DynamicArray<ErrorTag>* tags_;
};

#endif // ERROR_REGISTRY_HPP
