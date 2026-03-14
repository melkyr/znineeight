#ifndef ZIG_MODULE_JSON_H
#define ZIG_MODULE_JSON_H

#include "zig_runtime.h"
#include "file.h"

struct z_json_JsonProperty;
struct z_json_JsonValue;
union z_json_JsonData;

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

#ifndef ZIG_SLICE_Slice_z_json_JsonProperty
#define ZIG_SLICE_Slice_z_json_JsonProperty
typedef struct { struct z_json_JsonProperty* ptr; usize len; } Slice_z_json_JsonProperty;
static RETR_UNUSED_FUNC Slice_z_json_JsonProperty __make_slice_z_json_JsonProperty(struct z_json_JsonProperty* ptr, usize len) {
    Slice_z_json_JsonProperty s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_z_json_JsonValue
#define ZIG_ERRORUNION_ErrorUnion_Ptr_z_json_JsonValue
typedef struct {
    union {
        struct z_json_JsonValue* payload;
        int err;
    } data;
    int is_error;
} ErrorUnion_Ptr_z_json_JsonValue;
#endif

enum z_json_JsonValueTag {
    z_json_JsonValueTag_Null = 0,
    z_json_JsonValueTag_Boolean = 1,
    z_json_JsonValueTag_Number = 2,
    z_json_JsonValueTag_String = 3,
    z_json_JsonValueTag_Array = 4,
    z_json_JsonValueTag_Object = 5
};
typedef enum z_json_JsonValueTag z_json_JsonValueTag;

struct z_json_JsonProperty {
    Slice_u8 key;
    struct z_json_JsonValue* value;
};

union z_json_JsonData {
    int Boolean;
    double Number;
    Slice_u8 String;
    Slice_z_json_JsonValue Array;
    Slice_z_json_JsonProperty Object;
};

struct z_json_JsonValue {
    enum z_json_JsonValueTag tag;
    union z_json_JsonData data;
};

struct z_json_Arena; /* opaque */

extern int z_json_ParseError;

ErrorUnion_Ptr_z_json_JsonValue z_json_parseJson(void *, Slice_u8);

#endif
