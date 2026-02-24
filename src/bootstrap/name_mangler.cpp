#include "name_mangler.hpp"
#include "type_system.hpp"
#include "platform.hpp"
#include "utils.hpp"

NameMangler::NameMangler(ArenaAllocator& arena, StringInterner& interner)
    : arena_(arena), interner_(interner) {}

const char* NameMangler::mangleFunction(const char* name,
                                       DynamicArray<GenericParamInfo>* params,
                                       int param_count,
                                       const char* module) {
    char buffer[256];
    char* ptr = buffer;
    size_t remaining = sizeof(buffer);

    // Handle module prefix (skip for main and test modules)
    if (module && plat_strcmp(module, "main") != 0 &&
        plat_strcmp(module, "test") != 0 && plat_strcmp(name, "main") != 0) {

        safe_append(ptr, remaining, "z_");
        safe_append(ptr, remaining, module);
        safe_append(ptr, remaining, "_");
    } else if (isCKeyword(name)) {
        safe_append(ptr, remaining, "z_");
    }

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
            if ((*params)[i].kind == GENERIC_PARAM_TYPE) {
                type_str = mangleType((*params)[i].type_value);
            } else if ((*params)[i].kind == GENERIC_PARAM_ANYTYPE) {
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

    ::sanitizeForC89(buffer);

    // Limit to 31 characters for MSVC 6.0 compatibility
    if (plat_strlen(buffer) > 31) {
        buffer[31] = '\0';
    }

    return interner_.intern(buffer);
}

const char* NameMangler::mangleTypeName(const char* name, const char* module) {
    char buffer[256];
    char* ptr = buffer;
    size_t remaining = sizeof(buffer);

    // Handle module prefix (skip for main and test modules)
    if (module && plat_strcmp(module, "main") != 0 &&
        plat_strcmp(module, "test") != 0) {

        safe_append(ptr, remaining, "z_");
        safe_append(ptr, remaining, module);
        safe_append(ptr, remaining, "_");
    } else if (isCKeyword(name)) {
        safe_append(ptr, remaining, "z_");
    }

    // Append name
    safe_append(ptr, remaining, name);

    ::sanitizeForC89(buffer);

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
            plat_u64_to_string(type->as.array.size, size_buf, sizeof(size_buf));
            safe_append(ptr, remaining, size_buf);
            safe_append(ptr, remaining, "_");

            const char* elem = mangleType(type->as.array.element_type);
            safe_append(ptr, remaining, elem);

            return interner_.intern(buf);
        }
        case TYPE_TYPE: return "type";
        case TYPE_ANYTYPE: return "anytype";
        case TYPE_ERROR_UNION: {
            char buf[128];
            char* ptr = buf;
            size_t remaining = sizeof(buf);
            safe_append(ptr, remaining, "err_");
            const char* payload = mangleType(type->as.error_union.payload);
            safe_append(ptr, remaining, payload);
            return interner_.intern(buf);
        }
        case TYPE_OPTIONAL: {
            char buf[128];
            char* ptr = buf;
            size_t remaining = sizeof(buf);
            safe_append(ptr, remaining, "opt_");
            const char* payload = mangleType(type->as.optional.payload);
            safe_append(ptr, remaining, payload);
            return interner_.intern(buf);
        }
        case TYPE_STRUCT:
        case TYPE_UNION:
        case TYPE_ENUM: {
            if (type->c_name) return type->c_name;
            const char* name = (type->kind == TYPE_ENUM) ? type->as.enum_details.name : type->as.struct_details.name;
            if (name) return name;
            return "anonymous";
        }
        case TYPE_ERROR_SET: {
            if (type->as.error_set.name) {
                return type->as.error_set.name;
            }
            char buf[256];
            char* ptr = buf;
            size_t remaining = sizeof(buf);
            safe_append(ptr, remaining, "errset");
            if (type->as.error_set.tags) {
                for (size_t i = 0; i < type->as.error_set.tags->length(); ++i) {
                    safe_append(ptr, remaining, "_");
                    safe_append(ptr, remaining, (*type->as.error_set.tags)[i]);
                }
            }
            return interner_.intern(buf);
        }
        default: return "type";
    }
}
