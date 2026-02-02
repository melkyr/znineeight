#ifndef TEST_RUNNER_MAIN_HPP
#define TEST_RUNNER_MAIN_HPP

#include "../src/include/test_framework.hpp"
#include "test_utils.hpp"
#include <cstdio>
#include <cstring>
#include <cstdlib>

// Helper function to read source from a temporary file for child process
static char* read_source_from_file_common(const char* path) {
    FILE* file = fopen(path, "rb");
    if (!file) return NULL;
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    fseek(file, 0, SEEK_SET);
    char* buffer = (char*)malloc(length + 1);
    if (!buffer) {
        fclose(file);
        return NULL;
    }
    fread(buffer, 1, length, file);
    buffer[length] = '\0';
    fclose(file);
    return buffer;
}

inline int run_batch(int argc, char* argv[], bool (*tests[])(), int num_tests) {
    if (argc == 3) {
        const char* flag = argv[1];
        const char* filepath = argv[2];
        char* source = read_source_from_file_common(filepath);
        if (!source) {
            fprintf(stderr, "Failed to read source file in child process: %s\n", filepath);
            return 1;
        }

        if (strcmp(flag, "--run_parser_test") == 0) {
            run_parser_test_in_child(source);
        } else if (strcmp(flag, "--run_type_checker_test") == 0) {
            run_type_checker_test_in_child(source);
        }

        free(source);
        return 0; // Child process should exit after running the test
    }

    int passed = 0;
    for (int i = 0; i < num_tests; ++i) {
        printf("Running test %d...\n", i); fflush(stdout);
        if (tests[i]()) {
            passed++;
        }
    }

    printf("Passed %d/%d tests\n", passed, num_tests);
    return passed == num_tests ? 0 : 1;
}

#endif // TEST_RUNNER_MAIN_HPP
