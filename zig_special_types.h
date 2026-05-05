#ifndef ZIG_SPECIAL_TYPES_H
#define ZIG_SPECIAL_TYPES_H

#include <stddef.h>
#include "zig_compat.h"

#ifndef ZIG_TUPLE_EMPTY
#define ZIG_TUPLE_EMPTY
struct Tuple_empty { char __dummy; };
typedef struct Tuple_empty Tuple_empty;
#endif

#ifndef ZIG_SLICE_Slice_u8
#define ZIG_SLICE_Slice_u8
struct Slice_u8 { unsigned char* ptr; usize len; };
typedef struct Slice_u8 Slice_u8;
ZIG_INLINE ZIG_UNUSED Slice_u8 __make_slice_u8(const char* ptr, usize len) {
    Slice_u8 s;
    s.ptr = (unsigned char*)ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_u32
#define ZIG_SLICE_Slice_u32
struct Slice_u32 { unsigned int* ptr; usize len; };
typedef struct Slice_u32 Slice_u32;
ZIG_INLINE ZIG_UNUSED Slice_u32 __make_slice_u32(unsigned int* ptr, usize len) {
    Slice_u32 s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_zS_c313e0ed_f3385aec_AstNode
#define ZIG_SLICE_Slice_zS_c313e0ed_f3385aec_AstNode
struct Slice_zS_c313e0ed_f3385aec_AstNode { struct zS_c313e0ed_f3385aec_AstNode* ptr; usize len; };
typedef struct Slice_zS_c313e0ed_f3385aec_AstNode Slice_zS_c313e0ed_f3385aec_AstNode;
ZIG_INLINE ZIG_UNUSED Slice_zS_c313e0ed_f3385aec_AstNode __make_slice_zS_c313e0ed_f3385aec_AstNode(struct zS_c313e0ed_f3385aec_AstNode* ptr, usize len) {
    Slice_zS_c313e0ed_f3385aec_AstNode s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_u64
#define ZIG_SLICE_Slice_u64
struct Slice_u64 { u64* ptr; usize len; };
typedef struct Slice_u64 Slice_u64;
ZIG_INLINE ZIG_UNUSED Slice_u64 __make_slice_u64(u64* ptr, usize len) {
    Slice_u64 s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_f64
#define ZIG_SLICE_Slice_f64
struct Slice_f64 { double* ptr; usize len; };
typedef struct Slice_f64 Slice_f64;
ZIG_INLINE ZIG_UNUSED Slice_f64 __make_slice_f64(double* ptr, usize len) {
    Slice_f64 s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_zS_c313e0ed_42ae50fe_FnProto
#define ZIG_SLICE_Slice_zS_c313e0ed_42ae50fe_FnProto
struct Slice_zS_c313e0ed_42ae50fe_FnProto { struct zS_c313e0ed_42ae50fe_FnProto* ptr; usize len; };
typedef struct Slice_zS_c313e0ed_42ae50fe_FnProto Slice_zS_c313e0ed_42ae50fe_FnProto;
ZIG_INLINE ZIG_UNUSED Slice_zS_c313e0ed_42ae50fe_FnProto __make_slice_zS_c313e0ed_42ae50fe_FnProto(struct zS_c313e0ed_42ae50fe_FnProto* ptr, usize len) {
    Slice_zS_c313e0ed_42ae50fe_FnProto s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_zS_89baa7c0_28f04bce_KeywordEntry
#define ZIG_SLICE_Slice_zS_89baa7c0_28f04bce_KeywordEntry
struct Slice_zS_89baa7c0_28f04bce_KeywordEntry { struct zS_89baa7c0_28f04bce_KeywordEntry* ptr; usize len; };
typedef struct Slice_zS_89baa7c0_28f04bce_KeywordEntry Slice_zS_89baa7c0_28f04bce_KeywordEntry;
ZIG_INLINE ZIG_UNUSED Slice_zS_89baa7c0_28f04bce_KeywordEntry __make_slice_zS_89baa7c0_28f04bce_KeywordEntry(struct zS_89baa7c0_28f04bce_KeywordEntry* ptr, usize len) {
    Slice_zS_89baa7c0_28f04bce_KeywordEntry s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_zS_2b6fc0a6_a270ac29_SourceFile
#define ZIG_SLICE_Slice_zS_2b6fc0a6_a270ac29_SourceFile
struct Slice_zS_2b6fc0a6_a270ac29_SourceFile { struct zS_2b6fc0a6_a270ac29_SourceFile* ptr; usize len; };
typedef struct Slice_zS_2b6fc0a6_a270ac29_SourceFile Slice_zS_2b6fc0a6_a270ac29_SourceFile;
ZIG_INLINE ZIG_UNUSED Slice_zS_2b6fc0a6_a270ac29_SourceFile __make_slice_zS_2b6fc0a6_a270ac29_SourceFile(struct zS_2b6fc0a6_a270ac29_SourceFile* ptr, usize len) {
    Slice_zS_2b6fc0a6_a270ac29_SourceFile s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_zS_4c1e99d4_7c9905b1_InternEntry
#define ZIG_SLICE_Slice_zS_4c1e99d4_7c9905b1_InternEntry
struct Slice_zS_4c1e99d4_7c9905b1_InternEntry { struct zS_4c1e99d4_7c9905b1_InternEntry* ptr; usize len; };
typedef struct Slice_zS_4c1e99d4_7c9905b1_InternEntry Slice_zS_4c1e99d4_7c9905b1_InternEntry;
ZIG_INLINE ZIG_UNUSED Slice_zS_4c1e99d4_7c9905b1_InternEntry __make_slice_zS_4c1e99d4_7c9905b1_InternEntry(struct zS_4c1e99d4_7c9905b1_InternEntry* ptr, usize len) {
    Slice_zS_4c1e99d4_7c9905b1_InternEntry s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_zS_9daadfc5_bac763ac_Diagnostic
#define ZIG_SLICE_Slice_zS_9daadfc5_bac763ac_Diagnostic
struct Slice_zS_9daadfc5_bac763ac_Diagnostic { struct zS_9daadfc5_bac763ac_Diagnostic* ptr; usize len; };
typedef struct Slice_zS_9daadfc5_bac763ac_Diagnostic Slice_zS_9daadfc5_bac763ac_Diagnostic;
ZIG_INLINE ZIG_UNUSED Slice_zS_9daadfc5_bac763ac_Diagnostic __make_slice_zS_9daadfc5_bac763ac_Diagnostic(struct zS_9daadfc5_bac763ac_Diagnostic* ptr, usize len) {
    Slice_zS_9daadfc5_bac763ac_Diagnostic s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_zS_89baa7c0_7a3512d8_Token
#define ZIG_SLICE_Slice_zS_89baa7c0_7a3512d8_Token
struct Slice_zS_89baa7c0_7a3512d8_Token { struct zS_89baa7c0_7a3512d8_Token* ptr; usize len; };
typedef struct Slice_zS_89baa7c0_7a3512d8_Token Slice_zS_89baa7c0_7a3512d8_Token;
ZIG_INLINE ZIG_UNUSED Slice_zS_89baa7c0_7a3512d8_Token __make_slice_zS_89baa7c0_7a3512d8_Token(struct zS_89baa7c0_7a3512d8_Token* ptr, usize len) {
    Slice_zS_89baa7c0_7a3512d8_Token s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#endif /* ZIG_SPECIAL_TYPES_H */
