#include "hash.hpp"

u32 hash_string(const char* str) {
    u32 hash = FNV_OFFSET_BASIS;
    while (*str) {
        hash ^= (u8)*str++;
        hash *= FNV_PRIME;
    }
    return hash;
}
