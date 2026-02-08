#include "utils.hpp"
#include "platform.hpp"

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
    size_t len = plat_strlen(src);
    if (len < remaining) {
        plat_strcpy(dest, src);
        dest += len;
        remaining -= len;
    } else if (remaining > 0) {
        plat_strncpy(dest, src, remaining - 1);
        dest[remaining - 1] = '\0';
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
            buffer[i] = '\0';
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

    buffer[i] = '\0';
    reverse(buffer, i);
}

bool strings_equal(const char* a, const char* b) {
    if (a == b) return true;
    if (!a || !b) return false;
    while (*a && *b && *a == *b) {
        a++; b++;
    }
    return *a == *b;
}

bool isCKeyword(const char* str) {
    static const char* keywords[] = {
        "auto", "break", "case", "char", "const", "continue", "default", "do",
        "double", "else", "enum", "extern", "float", "for", "goto", "if",
        "int", "long", "register", "return", "short", "signed", "sizeof", "static",
        "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while",
        NULL
    };

    for (int i = 0; keywords[i]; i++) {
        if (plat_strcmp(str, keywords[i]) == 0) return true;
    }
    return false;
}

bool isCReservedName(const char* str) {
    if (str[0] == '_') {
        // Starts with _ followed by Uppercase or another _
        if ((str[1] >= 'A' && str[1] <= 'Z') || str[1] == '_') {
            return true;
        }
    }
    return false;
}

void sanitizeForC89(char* buffer) {
    if (!buffer || buffer[0] == '\0') return;

    // 1. Replace invalid characters with '_'
    for (char* p = buffer; *p; p++) {
        if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') || (*p >= '0' && *p <= '9') || *p == '_')) {
            *p = '_';
        }
    }

    // 2. Check for reserved names, keywords, or starting with digit
    bool needs_prefix = false;
    if (buffer[0] >= '0' && buffer[0] <= '9') {
        needs_prefix = true;
    } else if (isCKeyword(buffer)) {
        needs_prefix = true;
    } else if (isCReservedName(buffer)) {
        needs_prefix = true;
    }

    if (needs_prefix) {
        char temp[256];
        if (buffer[0] == '_') {
            plat_strcpy(temp, "z");
            plat_strncpy(temp + 1, buffer, 254);
        } else {
            plat_strcpy(temp, "z_");
            plat_strncpy(temp + 2, buffer, 253);
        }
        temp[255] = '\0';
        plat_strcpy(buffer, temp);
    }
}
