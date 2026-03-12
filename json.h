#ifndef ZIG_MODULE_JSON_H
#define ZIG_MODULE_JSON_H

#include "zig_runtime.h"
#include "file.h"
#include "arena.h"

struct z_json_JsonObjectEntry;
union z_json_JsonData;
struct z_json_JsonValue;

enum z_json_JsonValueTag {
    z_json_JsonValueTag_Null = 0,
    z_json_JsonValueTag_Boolean = 1,
    z_json_JsonValueTag_Number = 2,
    z_json_JsonValueTag_String = 3,
    z_json_JsonValueTag_Array = 4,
    z_json_JsonValueTag_Object = 5
};
typedef enum z_json_JsonValueTag z_json_JsonValueTag;

#ifndef ZIG_SLICE_Slice_u8
#define ZIG_SLICE_Slice_u8
typedef struct { unsigned char* ptr; usize len; } Slice_u8;
static RETR_UNUSED_FUNC Slice_u8 __make_slice_u8(unsigned char* ptr, usize len) {
    Slice_u8 s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_z_json_JsonValue
#define ZIG_SLICE_Slice_z_json_JsonValue
typedef struct { struct z_json_JsonValue* ptr; usize len; } Slice_z_json_JsonValue;
static RETR_UNUSED_FUNC Slice_z_json_JsonValue __make_slice_z_json_JsonValue(struct z_json_JsonValue* ptr, usize len) {
    Slice_z_json_JsonValue s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_z_json_JsonObjectEntry
#define ZIG_SLICE_Slice_z_json_JsonObjectEntry
typedef struct { struct z_json_JsonObjectEntry* ptr; usize len; } Slice_z_json_JsonObjectEntry;
static RETR_UNUSED_FUNC Slice_z_json_JsonObjectEntry __make_slice_z_json_JsonObjectEntry(struct z_json_JsonObjectEntry* ptr, usize len) {
    Slice_z_json_JsonObjectEntry s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

union z_json_JsonData {
    int boolean;
    double number;
    Slice_u8 string;
    Slice_z_json_JsonValue array;
    Slice_z_json_JsonObjectEntry object;
};

struct z_json_JsonValue {
    enum z_json_JsonValueTag tag;
    union z_json_JsonData data;
};

#ifndef ZIG_ERRORUNION_ErrorUnion_z_json_JsonValue
#define ZIG_ERRORUNION_ErrorUnion_z_json_JsonValue
typedef struct {
    union {
        struct z_json_JsonValue payload;
        int err;
    } data;
    int is_error;
} ErrorUnion_z_json_JsonValue;
#endif

#ifndef ZIG_OPTIONAL_Optional_Ptr_c_char
#define ZIG_OPTIONAL_Optional_Ptr_c_char
typedef struct {
    char const* value;
    int has_value;
} Optional_Ptr_c_char;
#endif

struct z_json_JsonObjectEntry {
    Slice_u8 key;
    struct z_json_JsonValue* value;
};

extern int z_json_ParseError;

ErrorUnion_z_json_JsonValue z_json_parseJson(void *, Slice_u8);

#endif
