#include "c_variable_allocator.hpp"
#include "symbol_table.hpp"
#include "platform.hpp"
#include "utils.hpp"

// Hardcoded C89 keyword list (32 keywords) sorted alphabetically for binary search.
static const char* c89_keywords[] = {
    "auto", "break", "case", "char", "const", "continue", "default", "do",
    "double", "else", "enum", "extern", "float", "for", "goto", "if",
    "int", "long", "register", "return", "short", "signed", "sizeof", "static",
    "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while"
};
static const int c89_keyword_count = 32;

static bool is_c89_keyword(const char* name) {
    int low = 0;
    int high = c89_keyword_count - 1;
    while (low <= high) {
        int mid = low + (high - low) / 2;
        int cmp = plat_strcmp(name, c89_keywords[mid]);
        if (cmp == 0) return true;
        if (cmp < 0) high = mid - 1;
        else low = mid + 1;
    }
    return false;
}

static bool is_c_reserved_name(const char* name) {
    if (name[0] == '_') {
        // Starts with _ followed by Uppercase or another _
        if ((name[1] >= 'A' && name[1] <= 'Z') || name[1] == '_') {
            return true;
        }
    }
    return false;
}

CVariableAllocator::CVariableAllocator(ArenaAllocator& arena)
    : arena_(arena), assigned_names_(arena) {}

void CVariableAllocator::reset() {
    assigned_names_.clear();
}

const char* CVariableAllocator::allocate(Symbol* sym) {
    const char* desired;
    if (sym->mangled_name && sym->mangled_name[0] != '\0') {
        desired = sym->mangled_name;
    } else {
        desired = sym->name;
    }
    return makeUnique(desired);
}

const char* CVariableAllocator::generate(const char* base) {
    return makeUnique(base);
}

const char* CVariableAllocator::makeUnique(const char* desired) {
    char base_buffer[256];
    size_t i;
    size_t len = plat_strlen(desired);
    if (len > 255) len = 255;

    // 1. Sanitize characters and copy to buffer
    for (i = 0; i < len; ++i) {
        char c = desired[i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_') {
            base_buffer[i] = c;
        } else {
            base_buffer[i] = '_';
        }
    }
    base_buffer[len] = '\0';

    // 2. Keyword/Reserved/Digit-start prefixing
    bool needs_prefix = false;
    if (base_buffer[0] >= '0' && base_buffer[0] <= '9') {
        needs_prefix = true;
    } else if (is_c89_keyword(base_buffer) || is_c_reserved_name(base_buffer)) {
        needs_prefix = true;
    }

    char mangled_buffer[256];
    if (needs_prefix) {
        if (base_buffer[0] == '_') {
            plat_strcpy(mangled_buffer, "z");
            plat_strncpy(mangled_buffer + 1, base_buffer, 254);
        } else {
            plat_strcpy(mangled_buffer, "z_");
            plat_strncpy(mangled_buffer + 2, base_buffer, 253);
        }
        mangled_buffer[255] = '\0';
    } else {
        plat_strcpy(mangled_buffer, base_buffer);
    }

    // 3. Truncate to 31 initially
    if (plat_strlen(mangled_buffer) > 31) {
        mangled_buffer[31] = '\0';
    }

    // 4. Uniquify
    char final_buffer[32]; // Max 31 chars + null
    plat_strcpy(final_buffer, mangled_buffer);

    if (isAssigned(final_buffer)) {
        int suffix_num = 1;
        while (true) {
            char suffix_str[16];
            simple_itoa((long)suffix_num, suffix_str, sizeof(suffix_str));
            size_t suffix_len = plat_strlen(suffix_str) + 1; // +1 for '_'

            size_t base_len = plat_strlen(mangled_buffer);
            if (base_len + suffix_len > 31) {
                base_len = 31 - suffix_len;
            }

            plat_strncpy(final_buffer, mangled_buffer, base_len);
            final_buffer[base_len] = '\0';

            // Manual concatenation
            char* p = final_buffer + base_len;
            *p++ = '_';
            plat_strcpy(p, suffix_str);

            if (!isAssigned(final_buffer)) {
                break;
            }
            suffix_num++;
        }
    }

    char* interned = arena_.allocString(final_buffer);
    assigned_names_.append(interned);
    return interned;
}

bool CVariableAllocator::isAssigned(const char* name) const {
    for (size_t i = 0; i < assigned_names_.length(); ++i) {
        if (plat_strcmp(assigned_names_[i], name) == 0) {
            return true;
        }
    }
    return false;
}
