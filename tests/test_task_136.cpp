#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "error_set_catalogue.hpp"
#include <cstring>

TEST_FUNC(Task136_ErrorSet_Catalogue) {
    const char* source =
        "const MyErrors = error { A, B };\n"
        "fn myTest() error{C}!void { }\n"
        "const Merged = error{D} || error{E};\n"
        "const std = @import(\"std\");\n";

    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);

    parser->parse();

    ErrorSetCatalogue& catalogue = unit.getErrorSetCatalogue();
    // 1. MyErrors {A, B}
    // 2. anonymous {C}
    // 3. anonymous {D}
    // 4. anonymous {E}

    ASSERT_EQ(4, catalogue.count());

    const DynamicArray<ErrorSetInfo>* entries = catalogue.getErrorSets();
    ASSERT_TRUE(entries != NULL);

    bool found_myerrors = false;
    for (size_t i = 0; i < entries->length(); ++i) {
        if ((*entries)[i].name && strcmp((*entries)[i].name, "MyErrors") == 0) {
            found_myerrors = true;
            ASSERT_EQ(2, (*entries)[i].tags->length());
        }
    }
    ASSERT_TRUE(found_myerrors);

    return true;
}

TEST_FUNC(Task136_ErrorSet_Rejection) {
    const char* source = "const E = error { A };";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(Task136_ErrorSetMerge_Rejection) {
    const char* source = "const Merged = E1 || E2;";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

