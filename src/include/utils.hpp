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
 * @brief A simple integer-to-string conversion function (itoa).
 *
 * This function is C++98 compatible and avoids using std::string or sprintf.
 *
 * @param value The integer value to convert.
 * @param buffer The character buffer to write the string into.
 * @param buffer_size The size of the character buffer.
 */
void simple_itoa(long value, char* buffer, size_t buffer_size);

/**
 * @brief Converts a 64-bit unsigned integer to a decimal string.
 *
 * This function is stack-based and avoids heap allocations.
 *
 * @param value The u64 value to convert.
 * @param buffer The character buffer to write the string into.
 * @param buffer_size The size of the character buffer.
 */
void u64_to_decimal(u64 value, char* buffer, size_t buffer_size);

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

#endif // UTILS_HPP
