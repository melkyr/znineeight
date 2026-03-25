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

bool isInternalCompilerIdentifier(const char* name) {
    if (!name) return false;
    if (plat_strncmp(name, "__tmp_", 6) == 0) return true;
    if (plat_strncmp(name, "__return_", 9) == 0) return true;
    if (plat_strncmp(name, "__bootstrap_", 12) == 0) return true;
    if (plat_strncmp(name, "__zig_label_", 12) == 0) return true;
    if (plat_strncmp(name, "__loop_", 7) == 0) return true;
    if (plat_strncmp(name, "__for_", 6) == 0) return true;
    if (plat_strncmp(name, "__make_slice_", 13) == 0) return true;
    if (plat_strncmp(name, "__implicit_ret", 14) == 0) return true;
    if (plat_strncmp(name, "__rz_", 5) == 0) return true;

    static const char* exact_names[] = {
        "Arena",
        "ArenaBlock",
        "zig_default_arena",
        "arena_create",
        "arena_alloc",
        "arena_reset",
        "arena_destroy",
        "arena_alloc_default",
        "arena_free"
    };
    for (size_t i = 0; i < sizeof(exact_names)/sizeof(exact_names[0]); ++i) {
        if (plat_strcmp(name, exact_names[i]) == 0) return true;
    }

    return false;
}

u32 fnv1a_32(const char* str) {
    if (!str) return 0;
    u32 hash = 2166136261U;
    while (*str) {
        hash ^= (u32)(unsigned char)*str++;
        hash *= 16777619U;
    }
    return hash;
}

void sanitizeForC89(char* buffer) {
    if (!buffer || buffer[0] == '\0') return;

    // 1. Replace invalid characters with '_'
    for (char* p = buffer; *p; p++) {
        if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') || (*p >= '0' && *p <= '9') || *p == '_')) {
            *p = '_';
        }
    }

    // 2. Check for internal compiler identifiers (bypass mangling)
    if (isInternalCompilerIdentifier(buffer)) return;

    // 3. Check for reserved names, keywords, or starting with digit
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
    const char* sep = NULL;
    if (last_slash && last_backslash) {
        sep = (last_slash > last_backslash) ? last_slash : last_backslash;
    } else {
        sep = last_slash ? last_slash : last_backslash;
    }

    if (sep) {
        size_t len = sep - path;
        if (len >= buffer_size) len = buffer_size - 1;
        plat_strncpy(buffer, path, len);
        buffer[len] = '\0';
    } else {
        plat_strcpy(buffer, ".");
    }
}

void normalize_path(char* path) {
    if (!path) return;
    for (char* p = path; *p; ++p) if (*p == '\\') *p = '/';

    char* dst = path;
    char* src = path;

    while (*src) {
        if (src[0] == '.' && (src[1] == '/' || src[1] == '\0')) {
            src += (src[1] == '/') ? 2 : 1;
        } else if (src[0] == '.' && src[1] == '.' && (src[2] == '/' || src[2] == '\0')) {
            src += (src[2] == '/') ? 3 : 2;
            if (dst > path) {
                if (dst[-1] == '/') dst--;
                while (dst > path && dst[-1] != '/') dst--;
            }
        } else {
            while (*src && *src != '/') *dst++ = *src++;
            if (*src == '/') *dst++ = *src++;
        }
    }
    // Remove trailing slash
    if (dst > path + 1 && dst[-1] == '/') dst--;
    *dst = '\0';
    if (path[0] == '\0') plat_strcpy(path, ".");
}

void get_relative_path(const char* target, const char* base, char* buffer, size_t buffer_size) {
    if (buffer_size == 0) return;
    buffer[0] = '\0';

    char target_norm[1024];
    char base_norm[1024];

    plat_strncpy(target_norm, target, sizeof(target_norm) - 1);
    target_norm[sizeof(target_norm) - 1] = '\0';
    normalize_path(target_norm);

    plat_strncpy(base_norm, base, sizeof(base_norm) - 1);
    base_norm[sizeof(base_norm) - 1] = '\0';
    normalize_path(base_norm);

    // If base is ".", just return target_norm
    if (plat_strcmp(base_norm, ".") == 0) {
        plat_strncpy(buffer, target_norm, buffer_size - 1);
        buffer[buffer_size - 1] = '\0';
        return;
    }

    // Find common prefix
    const char* t = target_norm;
    const char* b = base_norm;
    const char* last_common_sep = NULL;

    while (*t && *b && *t == *b) {
        if (*t == '/') last_common_sep = t;
        t++;
        b++;
    }

    if ((*t == '/' || *t == '\0') && (*b == '/' || *b == '\0')) {
        // Exact match or match up to a separator
        if (*t == '\0' && *b == '\0') {
            plat_strcpy(buffer, ".");
            return;
        }
        
        // Check if one is a prefix of another's directory
        if (*b == '\0' && *t == '/') {
            const char* rel = t + 1;
            plat_strncpy(buffer, rel, buffer_size - 1);
            buffer[buffer_size - 1] = '\0';
            return;
        }
    }

    // Fallback: search for last common separator
    t = target_norm;
    b = base_norm;
    const char* t_match = t;
    const char* b_match = b;
    
    while (*t && *b && *t == *b) {
        if (*t == '/') {
            t_match = t + 1;
            b_match = b + 1;
        }
        t++; b++;
    }
    
    // If mismatch happens after a separator or at start
    char result[1024];
    result[0] = '\0';
    char* r_ptr = result;
    size_t r_rem = sizeof(result);

    // Add ../ for each remaining level in base
    const char* b_rem = b_match;
    while (*b_rem) {
        if (*b_rem == '/') {
            safe_append(r_ptr, r_rem, "../");
        }
        b_rem++;
    }
    // Handle the last component of base if it's not empty
    if (b_match[0] != '\0') {
         safe_append(r_ptr, r_rem, "../");
    }

    // Add remaining part of target
    safe_append(r_ptr, r_rem, t_match);

    plat_strncpy(buffer, result, buffer_size - 1);
    buffer[buffer_size - 1] = '\0';
}
