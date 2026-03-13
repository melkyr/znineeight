#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../src/include/test_framework.hpp"

// Forward declaration of the test function
bool test_WhileContinueLabel();

// Use the framework's style
TEST_FUNC(WhileContinueLabel) {
    printf("Running WhileContinueLabel integration test...\n");

    const char* source_file = "tests/integration/wcl_test.zig";
    const char* output_c = "tests/integration/wcl_test.c";
    const char* binary = "tests/integration/wcl_test_bin";
    const char* runtime_c = "src/runtime/zig_runtime.c";

    // 1. Compile Zig to C
    char cmd[1024];
    sprintf(cmd, "./retrozig %s -o %s", source_file, output_c);
    int ret = system(cmd);
    ASSERT_EQ(0, ret);

    // 2. Compile C to binary - need to include src/include for zig_runtime.h and link with runtime
    sprintf(cmd, "gcc -std=c89 -pedantic -Wno-long-long -Wno-pointer-sign -Isrc/include %s %s -o %s", output_c, runtime_c, binary);
    ret = system(cmd);
    ASSERT_EQ(0, ret);

    // 3. Run binary and check output
#ifdef _WIN32
    sprintf(cmd, "%s.exe > tests/integration/wcl_test.out 2>&1", binary);
#else
    sprintf(cmd, "./%s > tests/integration/wcl_test.out 2>&1", binary);
#endif
    ret = system(cmd);
    ASSERT_EQ(0, ret);

    // 4. Verify output
    FILE* f = fopen("tests/integration/wcl_test.out", "r");
    ASSERT_TRUE(f != NULL);

    char line[256];
    bool found_count1 = false;
    bool found_count2 = false;
    bool found_i = false;

    while (fgets(line, sizeof(line), f)) {
        // printf("Line: %s", line); // Debug
        if (strstr(line, "Final count (should be 9): 9")) found_count1 = true;
        if (strstr(line, "Final i (should be 10): 10")) found_i = true;
        if (strstr(line, "Final count (should be 8): 8")) found_count2 = true;
    }
    fclose(f);

    if (!found_count1) printf("DEBUG: count1 not found\n");
    if (!found_i) printf("DEBUG: i not found\n");
    if (!found_count2) printf("DEBUG: count2 not found\n");

    ASSERT_TRUE(found_count1);
    ASSERT_TRUE(found_i);
    ASSERT_TRUE(found_count2);

    printf("WhileContinueLabel integration test passed!\n");
    return true;
}
