#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "metadata_preparation_pass.hpp"
#include "type_system.hpp"

TEST_FUNC(MetadataPreparation_TransitiveHeaders) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    // lib.zig
    const char* lib_source =
        "pub const Inner = struct { val: i32 };\n"
        "pub const Outer = struct { inner: Inner };\n"
        "pub fn getOuter() Outer { return .{ .inner = .{ .val = 42 } }; }\n";

    FILE* flib = fopen("lib.zig", "w");
    fprintf(flib, "%s", lib_source);
    fclose(flib);

    const char* main_source =
        "const lib = @import(\"lib.zig\");\n"
        "fn main() void {\n"
        "    var o = lib.getOuter();\n"
        "    _ = o;\n"
        "}\n";

    u32 main_id = unit.addSource("main.zig", main_source);
    unit.addIncludePath(".");
    bool success = unit.performFullPipeline(main_id);

    remove("lib.zig");

    if (!success || unit.getErrorHandler().hasErrors()) {
        printf("MetadataPreparation_TransitiveHeaders: pipeline failed\n");
        return false;
    }

    // Verify lib.zig header types
    Module* lib_mod = unit.getModule("lib");
    if (!lib_mod) {
        printf("MetadataPreparation_TransitiveHeaders: lib module not found\n");
        return false;
    }

    bool found_inner = false;
    bool found_outer = false;

    for (size_t i = 0; i < lib_mod->header_types.length(); ++i) {
        Type* t = lib_mod->header_types[i];
        if (t->kind == TYPE_STRUCT) {
            if (t->as.struct_details.name && plat_strcmp(t->as.struct_details.name, "Inner") == 0) found_inner = true;
            if (t->as.struct_details.name && plat_strcmp(t->as.struct_details.name, "Outer") == 0) found_outer = true;
        }
    }

    if (!found_inner) printf("MetadataPreparation_TransitiveHeaders: Inner not found in header_types\n");
    if (!found_outer) printf("MetadataPreparation_TransitiveHeaders: Outer not found in header_types\n");

    return found_inner && found_outer;
}

TEST_FUNC(MetadataPreparation_SpecialTypes) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    // lib.zig
    const char* lib_source =
        "pub const Data = struct { x: i32 };\n"
        "pub fn getSlice() []const Data { return undefined; }\n"
        "pub fn getOptional() ?Data { return undefined; }\n"
        "pub fn getErrorUnion() !Data { return undefined; }\n";

    FILE* flib = fopen("lib.zig", "w");
    fprintf(flib, "%s", lib_source);
    fclose(flib);

    const char* main_source =
        "const lib = @import(\"lib.zig\");\n"
        "fn main() void {\n"
        "    _ = lib.getSlice();\n"
        "    _ = lib.getOptional();\n"
        "    _ = lib.getErrorUnion();\n"
        "}\n";

    u32 main_id = unit.addSource("main.zig", main_source);
    unit.addIncludePath(".");
    bool success = unit.performFullPipeline(main_id);

    remove("lib.zig");

    if (!success || unit.getErrorHandler().hasErrors()) {
        printf("MetadataPreparation_SpecialTypes: pipeline failed\n");
        return false;
    }

    Module* lib_mod = unit.getModule("lib");
    if (!lib_mod) return false;

    bool found_slice = false;
    bool found_optional = false;
    bool found_error_union = false;

    for (size_t i = 0; i < lib_mod->header_types.length(); ++i) {
        Type* t = lib_mod->header_types[i];
        if (t->kind == TYPE_SLICE) found_slice = true;
        if (t->kind == TYPE_OPTIONAL) found_optional = true;
        if (t->kind == TYPE_ERROR_UNION) found_error_union = true;
    }

    if (!found_slice) printf("MetadataPreparation_SpecialTypes: slice not found in header_types\n");
    if (!found_optional) printf("MetadataPreparation_SpecialTypes: optional not found in header_types\n");
    if (!found_error_union) printf("MetadataPreparation_SpecialTypes: error_union not found in header_types\n");

    return found_slice && found_optional && found_error_union;
}

TEST_FUNC(MetadataPreparation_RecursivePlaceholder) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* main_source =
        "const Node = struct {\n"
        "    next: *Node,\n"
        "    val: i32,\n"
        "};\n"
        "fn main() void {\n"
        "    var n: Node = undefined;\n"
        "    _ = n;\n"
        "}\n";

    u32 main_id = unit.addSource("main.zig", main_source);
    bool success = unit.performFullPipeline(main_id);

    if (!success || unit.getErrorHandler().hasErrors()) {
        printf("MetadataPreparation_RecursivePlaceholder: pipeline failed\n");
        return false;
    }

    // Verify Node has non-zero size
    Symbol* sym = unit.getSymbolTable("main").lookup("Node");
    if (!sym || !sym->symbol_type) {
        printf("MetadataPreparation_RecursivePlaceholder: Node symbol or type not found\n");
        return false;
    }

    if (sym->symbol_type->size == 0) printf("MetadataPreparation_RecursivePlaceholder: Node size is 0\n");
    if (sym->symbol_type->kind != TYPE_STRUCT) printf("MetadataPreparation_RecursivePlaceholder: Node kind is %d, expected %d\n", (int)sym->symbol_type->kind, (int)TYPE_STRUCT);

    return sym->symbol_type->size > 0 && sym->symbol_type->kind == TYPE_STRUCT;
}

TEST_FUNC(PlaceholderHardening_RecursiveComposites) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* main_source =
        "const Node = struct {\n"
        "    children: []Node,\n"
        "    parent: ?*Node,\n"
        "    val: i32,\n"
        "};\n"
        "fn main() void {\n"
        "    var n: Node = undefined;\n"
        "    _ = n;\n"
        "}\n";

    u32 main_id = unit.addSource("main.zig", main_source);
    bool success = unit.performFullPipeline(main_id);

    if (!success || unit.getErrorHandler().hasErrors()) {
        printf("PlaceholderHardening_RecursiveComposites: pipeline failed\n");
        return false;
    }

    Symbol* sym = unit.getSymbolTable("main").lookup("Node");
    if (!sym || !sym->symbol_type) return false;

    Type* node_type = sym->symbol_type;
    if (node_type->kind != TYPE_STRUCT) return false;

    // Check fields
    DynamicArray<StructField>* fields = node_type->as.struct_details.fields;
    if (!fields || fields->length() != 3) {
        printf("PlaceholderHardening_RecursiveComposites: fields count mismatch\n");
        return false;
    }

    // []Node
    Type* children_type = (*fields)[0].type;
    if (children_type->kind != TYPE_SLICE) {
        printf("PlaceholderHardening_RecursiveComposites: children_type not SLICE\n");
        return false;
    }
    if (children_type->as.slice.element_type != node_type) {
        printf("PlaceholderHardening_RecursiveComposites: children_type base mismatch\n");
        return false;
    }

    // ?*Node
    Type* parent_type = (*fields)[1].type;
    if (parent_type->kind != TYPE_OPTIONAL) {
        printf("PlaceholderHardening_RecursiveComposites: parent_type not OPTIONAL\n");
        return false;
    }
    if (parent_type->as.optional.payload->kind != TYPE_POINTER) {
        printf("PlaceholderHardening_RecursiveComposites: parent_type payload not POINTER\n");
        return false;
    }
    if (parent_type->as.optional.payload->as.pointer.base != node_type) {
        printf("PlaceholderHardening_RecursiveComposites: parent_type base mismatch\n");
        return false;
    }

    if (node_type->size == 0) printf("PlaceholderHardening_RecursiveComposites: node_type size is 0\n");

    return node_type->size > 0;
}
