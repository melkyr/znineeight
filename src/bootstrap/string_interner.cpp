#include "../include/string_interner.hpp"
#include <cstring>

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
    for (size_t i = 0; i < NUM_BUCKETS; ++i) {
        buckets[i] = NULL;
    }
}

const char* StringInterner::intern(const char* str) {
    unsigned int h = hash(str);
    size_t index = h % NUM_BUCKETS;

    for (StringEntry* entry = buckets[index]; entry; entry = entry->next) {
        if (strcmp(entry->str, str) == 0) {
            return entry->str;
        }
    }

    // Not found, create a new entry using the arena allocator
    size_t len = strlen(str);
    char* new_str = static_cast<char*>(allocator.alloc(len + 1));
    if (!new_str) {
        // In a real-world scenario, you'd handle this more gracefully.
        // For this project, we'll keep it simple.
        exit(1);
    }
    strcpy(new_str, str);

    StringEntry* new_entry = static_cast<StringEntry*>(allocator.alloc(sizeof(StringEntry)));
     if (!new_entry) {
        exit(1);
    }

    new_entry->str = new_str;
    new_entry->next = buckets[index];
    buckets[index] = new_entry;

    return new_entry->str;
}
