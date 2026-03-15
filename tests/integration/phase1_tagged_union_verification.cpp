#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string.h>

TEST_FUNC(Phase1_TaggedUnion_Codegen) {
    const char* source =
        "const U = union(enum) {\n"
        "    A: i32,\n"
        "    B: f64,\n"
        "    C: void,\n"
        "};\n"
        "pub fn test_fn() void {\n"
        "    var u = U{ .A = 42 };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    /* Verify C emission */
    C89Emitter emitter(unit);
    const char* path = "test_tagged_union_codegen.c";
    emitter.open(path);

    /* We need to trigger type definition emission */
    Symbol* sym = unit.getSymbolTable().lookup("U");
    ASSERT_TRUE(sym != NULL);
    ASSERT_TRUE(sym->symbol_type != NULL);
    ASSERT_TRUE(isTaggedUnion(sym->symbol_type));

    emitter.emitTypeDefinition(sym->symbol_type);
    emitter.close();

    /* Read and verify the output */
    FILE* f = fopen(path, "r");
    ASSERT_TRUE(f != NULL);
    char buffer[4096];
    size_t n = fread(buffer, 1, sizeof(buffer) - 1, f);
    buffer[n] = '\0';
    fclose(f);

    /* Check for structural elements */
    ASSERT_TRUE(strstr(buffer, "struct U") != NULL);
    ASSERT_TRUE(strstr(buffer, "U_Tag tag;") != NULL);
    ASSERT_TRUE(strstr(buffer, "union {") != NULL);
    ASSERT_TRUE(strstr(buffer, "int A;") != NULL);
    ASSERT_TRUE(strstr(buffer, "double B;") != NULL);
    ASSERT_TRUE(strstr(buffer, "void C;") == NULL); /* void fields omitted */
    ASSERT_TRUE(strstr(buffer, "} data;") != NULL);

    return true;
}

TEST_FUNC(Phase1_TaggedUnion_ForwardDecl) {
    /* Two tagged unions referring to each other via pointers */
    const char* source =
        "pub const Node = union(enum) {\n"
        "    Leaf: i32,\n"
        "    Branch: *Tree,\n"
        "};\n"
        "pub const Tree = union(enum) {\n"
        "    Single: *Node,\n"
        "    Pair: struct { left: *Node, right: *Node },\n"
        "};\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    /* Verify Header emission */
    C89Emitter header_emitter(unit, true);
    const char* header_path = "test_forward_decl.h";
    header_emitter.open(header_path);
    header_emitter.setModule("test");

    /* We need to manually run MetadataPreparationPass in this test to populate header_types */
    MetadataPreparationPass prep(unit);
    prep.run();

    Module* mod = unit.getModule("test");
    ASSERT_TRUE(mod != NULL);

    /* Use the same logic as CBackend::generateHeaderFile for forward declarations */
    for (size_t i = 0; i < mod->header_types.length(); ++i) {
        header_emitter.ensureForwardDeclaration(mod->header_types[i]);
    }
    header_emitter.close();

    /* Read and verify the header */
    FILE* f = fopen(header_path, "r");
    ASSERT_TRUE(f != NULL);
    char buffer[4096];
    size_t n = fread(buffer, 1, sizeof(buffer) - 1, f);
    buffer[n] = '\0';
    fclose(f);

    /* Both Node and Tree are tagged unions, so they MUST be forward declared as 'struct' */
    /* Note: getC89GlobalName does NOT add module prefix for module "test" or "main" */
    ASSERT_TRUE(strstr(buffer, "struct Node;") != NULL);
    ASSERT_TRUE(strstr(buffer, "struct Tree;") != NULL);
    ASSERT_TRUE(strstr(buffer, "union Node;") == NULL);
    ASSERT_TRUE(strstr(buffer, "union Tree;") == NULL);

    return true;
}
