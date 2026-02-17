#include "utils.hpp"
#include "platform.hpp"

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

void join_paths(const char* base_dir, const char* rel_path, char* buffer, size_t buffer_size) {
    if (buffer_size == 0) return;
    buffer[0] = '\0';

    if (!base_dir || base_dir[0] == '\0' || plat_strcmp(base_dir, ".") == 0 || (rel_path && (rel_path[0] == '/' || rel_path[0] == '\\'))) {
        // rel_path is absolute or base_dir is empty or current dir
        if (rel_path) {
            plat_strncpy(buffer, rel_path, buffer_size - 1);
            buffer[buffer_size - 1] = '\0';
        }
        return;
    }

    plat_strncpy(buffer, base_dir, buffer_size - 1);
    buffer[buffer_size - 1] = '\0';

    size_t len = plat_strlen(buffer);
    if (len > 0 && buffer[len - 1] != '/' && buffer[len - 1] != '\\') {
        if (len < buffer_size - 1) {
            buffer[len] = '/';
            buffer[len + 1] = '\0';
            len++;
        }
    }

    if (rel_path && len < buffer_size - 1) {
        plat_strncpy(buffer + len, rel_path, buffer_size - 1 - len);
        buffer[buffer_size - 1] = '\0';
    }
}

void get_directory(const char* path, char* buffer, size_t buffer_size) {
    if (buffer_size == 0) return;
    buffer[0] = '\0';

    const char* last_slash = plat_strrchr(path, '/');
    const char* last_backslash = plat_strrchr(path, '\\');
    const char* sep = (last_slash > last_backslash) ? last_slash : last_backslash;

    if (sep) {
        size_t len = sep - path;
        if (len >= buffer_size) len = buffer_size - 1;
        plat_strncpy(buffer, path, len);
        buffer[len] = '\0';
    } else {
        plat_strcpy(buffer, ".");
    }
}
