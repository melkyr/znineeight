#ifndef UTILS_HPP
#define UTILS_HPP

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

#endif // UTILS_HPP
