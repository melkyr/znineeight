#include "../include/string_interner.hpp"
#include <cstring>
#include <cstdlib> // For exit

// FNV-1a hash constants
static const unsigned int FNV_PRIME = 16777619;
static const unsigned int FNV_OFFSET_BASIS = 2166136261;

unsigned int StringInterner::hash(const char* str) {
    unsigned int hash = FNV_OFFSET_BASIS;
    const char* p = str;
    while (*p) {
        hash ^= static_cast<unsigned int>(*p++);
        hash *= FNV_PRIME;
    }
    return hash;
}

StringInterner::StringInterner(ArenaAllocator& allocator) : allocator(allocator) {
    // Initialize all buckets to NULL.
    for (size_t i = 0; i < NUM_BUCKETS; ++i) {
        buckets[i] = NULL;
    }
}

const char* StringInterner::intern(const char* str) {
    // Hash the string to find the correct bucket.
    unsigned int h = hash(str);
    size_t index = h % NUM_BUCKETS;

    // Check if the string already exists in the bucket's linked list.
    for (StringEntry* entry = buckets[index]; entry; entry = entry->next) {
        if (strcmp(entry->str, str) == 0) {
            // Found it, return the existing pointer.
            return entry->str;
        }
    }

    // The string was not found, so we need to create a new entry for it.
    size_t len = strlen(str);
    char* new_str = static_cast<char*>(allocator.alloc(len + 1));
    if (!new_str) {
        // Allocation failure is considered a fatal error for this project.
        exit(1);
    }
    strcpy(new_str, str);

    // Create the new entry in the hash table.
    StringEntry* new_entry = static_cast<StringEntry*>(allocator.alloc(sizeof(StringEntry)));
     if (!new_entry) {
        exit(1);
    }

    // Add the new entry to the front of the bucket's linked list.
    new_entry->str = new_str;
    new_entry->next = buckets[index];
    buckets[index] = new_entry;

    return new_entry->str;
}
