#ifndef HASH_HPP
#define HASH_HPP

#include "common.hpp"

// FNV-1a hash function constants
const u32 FNV_PRIME = 16777619;
const u32 FNV_OFFSET_BASIS = 2166136261;

// Function to compute the FNV-1a hash of a null-terminated string.
u32 hash_string(const char* str);

#endif // HASH_HPP
