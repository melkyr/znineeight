#ifndef STRING_INTERNER_HPP
#define STRING_INTERNER_HPP

#include <cstddef>
#include "memory.hpp"

class StringInterner {
public:
    StringInterner(ArenaAllocator& allocator);

    const char* intern(const char* str);

private:
    struct StringEntry {
        char* str;
        StringEntry* next;
    };

    static const size_t NUM_BUCKETS = 1024;
    StringEntry* buckets[NUM_BUCKETS];
    ArenaAllocator& allocator;

    static unsigned int hash(const char* str);
};

#endif // STRING_INTERNER_HPP
