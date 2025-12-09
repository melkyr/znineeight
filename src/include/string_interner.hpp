#ifndef STRING_INTERNER_HPP
#define STRING_INTERNER_HPP

#include <cstddef>
#include "memory.hpp"

/**
 * @class StringInterner
 * @brief Manages a pool of unique strings to save memory and allow for fast comparisons.
 *
 * When the same string literal (e.g., an identifier name) appears multiple times
 * in the source code, the StringInterner stores it only once. Subsequent requests
 * for the same string will return a pointer to the existing copy. This allows for
 * string equality checks to be performed with a simple pointer comparison instead
 * of a character-by-character comparison.
 */
class StringInterner {
public:
    /**
     * @brief Constructs a StringInterner.
     * @param allocator The ArenaAllocator to be used for storing the strings.
     */
    StringInterner(ArenaAllocator& allocator);

    /**
     * @brief Interns a string, returning a pointer to the unique copy.
     * @param str The null-terminated string to intern.
     * @return A const pointer to the unique, interned string.
     */
    const char* intern(const char* str);

private:
    /**
     * @struct StringEntry
     * @brief A node in the hash table's linked list.
     */
    struct StringEntry {
        char* str;
        StringEntry* next;
    };

    /** @brief The number of buckets in the hash table. */
    static const size_t NUM_BUCKETS = 1024;
    /** @brief The hash table, implemented as an array of buckets. */
    StringEntry* buckets[NUM_BUCKETS];
    /** @brief The arena allocator used for all memory allocations. */
    ArenaAllocator& allocator;

    /**
     * @brief Hashes a string using the FNV-1a algorithm.
     * @param str The string to hash.
     * @return The calculated hash value.
     */
    static unsigned int hash(const char* str);
};

#endif // STRING_INTERNER_HPP
