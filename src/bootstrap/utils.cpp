#include "utils.hpp"
#include <cstring> // For strlen, strcpy, strncat

// Helper to reverse a string
static void reverse(char* str, int length) {
    int start = 0;
    int end = length - 1;
    while (start < end) {
        char temp = str[start];
        str[start] = str[end];
        str[end] = temp;
        start++;
        end--;
    }
}

void safe_append(char*& dest, size_t& remaining, const char* src) {
    if (!src) return;
    size_t len = strlen(src);
    if (len < remaining) {
        strcpy(dest, src);
        dest += len;
        remaining -= len;
    } else if (remaining > 0) {
        strncpy(dest, src, remaining - 1);
        dest[remaining - 1] = '\\0';
        dest += (remaining - 1);
        remaining = 0;
    }
}

void simple_itoa(long value, char* buffer, size_t buffer_size) {
    if (buffer_size == 0) return;

    long n = value;
    int i = 0;
    bool is_negative = false;

    if (n == 0) {
        if (buffer_size > 1) {
            buffer[i++] = '0';
            buffer[i] = '\\0';
        }
        return;
    }

    if (n < 0) {
        is_negative = true;
        n = -n;
    }

    while (n != 0 && i < (int)buffer_size - (is_negative ? 2 : 1)) {
        int rem = n % 10;
        buffer[i++] = rem + '0';
        n = n / 10;
    }

    if (is_negative && i < (int)buffer_size - 1) {
        buffer[i++] = '-';
    }

    buffer[i] = '\\0';
    reverse(buffer, i);
}
