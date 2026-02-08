#include "name_mangler.hpp"
#include "type_system.hpp"
#include "platform.hpp"
#include "utils.hpp"

NameMangler::NameMangler(ArenaAllocator& arena, StringInterner& interner)
    : arena_(arena), interner_(interner) {}

const char* NameMangler::mangleFunction(const char* name,
                                       const GenericParamInfo* params,
                                       int param_count,
                                       const char* module) {
    char buffer[256];
    char* ptr = buffer;
    size_t remaining = sizeof(buffer);

    // TODO: Handle module prefix in Milestone 6
    (void)module;

    // Start with function name
    size_t name_len = plat_strlen(name);
    if (name_len >= remaining) name_len = remaining - 1;
    plat_strncpy(ptr, (char*)name, name_len);
    ptr[name_len] = '\0';
    ptr += name_len;
    remaining -= name_len;

    // Append generic parameters
    if (param_count > 0) {
        if (remaining > 2) {
            plat_strncpy(ptr, "__", 2);
            ptr[2] = '\0';
            ptr += 2;
            remaining -= 2;
        }

        for (int i = 0; i < param_count; i++) {
            if (i > 0) {
                if (remaining > 1) {
                    *ptr++ = '_';
                    *ptr = '\0';
                    remaining--;
                }
            }
            const char* type_str = "";
            if (params[i].kind == GENERIC_PARAM_TYPE) {
                type_str = mangleType(params[i].type_value);
            } else if (params[i].kind == GENERIC_PARAM_ANYTYPE) {
                type_str = "any";
            } else {
                // TODO: Handle comptime values
                type_str = "val";
            }

            size_t t_len = plat_strlen(type_str);
            if (t_len >= remaining) t_len = remaining - 1;
            plat_strncpy(ptr, (char*)type_str, t_len);
            ptr[t_len] = '\0';
            ptr += t_len;
            remaining -= t_len;
        }
    }

    sanitizeForC89(buffer);

    // Limit to 31 characters for MSVC 6.0 compatibility
    if (plat_strlen(buffer) > 31) {
        buffer[31] = '\0';
    }

    return interner_.intern(buffer);
}

const char* NameMangler::mangleType(Type* type) {
    if (!type) return "void";

    switch (type->kind) {
        case TYPE_VOID: return "void";
        case TYPE_BOOL: return "bool";
        case TYPE_I8:   return "i8";
        case TYPE_I16:  return "i16";
        case TYPE_I32:  return "i32";
        case TYPE_I64:  return "i64";
        case TYPE_U8:   return "u8";
        case TYPE_U16:  return "u16";
        case TYPE_U32:  return "u32";
        case TYPE_U64:  return "u64";
        case TYPE_F32:  return "f32";
        case TYPE_F64:  return "f64";
        case TYPE_ISIZE: return "isize";
        case TYPE_USIZE: return "usize";
        case TYPE_POINTER: {
            char buf[64];
            plat_strcpy(buf, "ptr_");
            const char* base = mangleType(type->as.pointer.base);
            plat_strncpy(buf + 4, (char*)base, 59);
            buf[63] = '\0';
            return interner_.intern(buf);
        }
        case TYPE_ARRAY: {
            char buf[64];
            char* ptr = buf;
            size_t remaining = sizeof(buf);

            safe_append(ptr, remaining, "arr");
            char size_buf[21];
            simple_itoa(type->as.array.size, size_buf, sizeof(size_buf));
            safe_append(ptr, remaining, size_buf);
            safe_append(ptr, remaining, "_");

            const char* elem = mangleType(type->as.array.element_type);
            safe_append(ptr, remaining, elem);

            return interner_.intern(buf);
        }
        case TYPE_TYPE: return "type";
        case TYPE_ANYTYPE: return "anytype";
        default: return "type";
    }
}

void NameMangler::sanitizeForC89(char* buffer) {
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
    } else if (isReservedName(buffer)) {
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
        plat_strcpy(buffer, temp);
    }
}

bool NameMangler::isCKeyword(const char* str) {
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

bool NameMangler::isReservedName(const char* str) {
    if (str[0] == '_') {
        // Starts with _ followed by Uppercase or another _
        if ((str[1] >= 'A' && str[1] <= 'Z') || str[1] == '_') {
            return true;
        }
    }
    return false;
}
