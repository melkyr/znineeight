#ifndef UTILS_HPP
#define UTILS_HPP

#include "common.hpp"
#include <cstddef> // For size_t

/**
 * @brief Appends a source string to a destination buffer, ensuring no overflow.
 *
 * This function updates the destination pointer and the remaining size counter.
 *
 * @param dest A reference to the current position in the destination buffer.
 * @param remaining A reference to the remaining size in the buffer.
 * @param src The source string to append.
 */
void safe_append(char*& dest, size_t& remaining, const char* src);

/**
 * @brief Checks if two C-style strings are equal.
 * @param a The first string.
 * @param b The second string.
 * @return True if the strings are equal, false otherwise.
 */
bool strings_equal(const char* a, const char* b);

/**
 * @brief Checks if two interned identifiers are equal using pointer comparison.
 *
 * Since identifiers are interned in the StringInterner, we can use pointer equality
 * for O(1) comparison instead of O(n) string comparison.
 *
 * @param a The first identifier.
 * @param b The second identifier.
 * @return True if the identifiers are equal, false otherwise.
 */
inline bool identifiers_equal(const char* a, const char* b) {
    return a == b;
}

/**
 * @brief Checks if a string is a C language keyword.
 * @param str The string to check.
 * @return True if the string is a C keyword, false otherwise.
 */
bool isCKeyword(const char* str);

/**
 * @brief Checks if a string is a reserved name in C (e.g., starts with _[A-Z] or __).
 * @param str The string to check.
 * @return True if the string is reserved, false otherwise.
 */
bool isCReservedName(const char* str);

/**
 * @brief Sanitizes a string for use as a C89 identifier.
 *
 * This function replaces invalid characters with underscores and prefixes
 * the string with 'z_' if it starts with a digit or matches a C keyword/reserved name.
 *
 * @param buffer The character buffer to sanitize (must be large enough to hold prefix).
 */
void sanitizeForC89(char* buffer);

/**
 * @brief Checks if a string is an internal identifier used by the compiler.
 * @param name The name to check.
 * @return True if the name is an internal identifier, false otherwise.
 */
bool isInternalCompilerIdentifier(const char* name);

/**
 * @brief Computes a 32-bit FNV-1a hash for a string.
 * @param str The string to hash.
 * @return The 32-bit hash.
 */
u32 fnv1a_32(const char* str);

/**
 * @brief Joins a base directory and a relative path.
 * @param base_dir The base directory.
 * @param rel_path The relative path.
 * @param buffer The buffer to store the joined path.
 * @param buffer_size The size of the buffer.
 */
void join_paths(const char* base_dir, const char* rel_path, char* buffer, size_t buffer_size);

/**
 * @brief Gets the directory portion of a file path.
 * @param path The full file path.
 * @param buffer The buffer to store the directory.
 * @param buffer_size The size of the buffer.
 */
void get_directory(const char* path, char* buffer, size_t buffer_size);

/**
 * @brief Normalizes a file path by converting backslashes to forward slashes
 *        and resolving '.' and '..' components.
 * @param path The path to normalize (modified in place).
 */
void normalize_path(char* path);

/**
 * @brief Computes the path of target relative to base.
 * @param target The target path.
 * @param base The base path.
 * @param buffer The buffer to store the relative path.
 * @param buffer_size The size of the buffer.
 */
void get_relative_path(const char* target, const char* base, char* buffer, size_t buffer_size);

#endif // UTILS_HPP
