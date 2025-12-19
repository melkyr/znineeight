#include "test_framework.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#if defined(_WIN32)
#include <windows.h>
#else
#include <sys/wait.h>
#include <unistd.h>
#endif

// Helper function to run a parsing task in a separate process
// and check if it terminates as expected.
static bool run_test_in_child_process(const char* source_code, const char* test_type_flag) {
    char command[512];
#if defined(_WIN32)
    _snprintf(command, sizeof(command), "test_runner.exe %s \"%s\"", test_type_flag, source_code);
    command[sizeof(command) - 1] = '\0';

    STARTUPINFO si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    if (!CreateProcess(NULL, command, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        return false; // Failed to create process
    }

    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD exit_code;
    GetExitCodeProcess(pi.hProcess, &exit_code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return exit_code != 0;
#else
    // On Unix-like systems, use fork and exec.
    pid_t pid = fork();
    if (pid == 0) {
        // Child process: execute the test runner with the special arguments.
        // Suppress stdout/stderr to keep test output clean.
        freopen("/dev/null", "w", stdout);
        freopen("/dev/null", "w", stderr);
        execlp("./test_runner", "test_runner", test_type_flag, source_code, (char*)NULL);
        // If execlp returns, it means an error occurred.
        exit(127); // Exit with a special code to indicate exec failure.
    } else if (pid > 0) {
        // Parent process: wait for the child and check its exit status.
        int status;
        waitpid(pid, &status, 0);
        // We expect the child to be terminated by a signal (SIGABRT from abort()).
        // WIFSIGNALED will be true in this case.
        return WIFSIGNALED(status);
    }
    return false; // Fork failed.
#endif
}

bool expect_parser_abort(const char* source_code) {
    return run_test_in_child_process(source_code, "--run-parser-test");
}

bool expect_statement_parser_abort(const char* source_code) {
    return run_test_in_child_process(source_code, "--run-statement-parser-test");
}

TEST_FUNC(Parser_Error_OnMissingColon) {
    // This source code is missing a colon after the identifier 'x'
    const char* source = "var x i32 = 42;";
    ASSERT_TRUE(expect_parser_abort(source));
    return true;
}

TEST_FUNC(Parser_Struct_Error_MissingLBrace) {
    ASSERT_TRUE(expect_parser_abort("struct"));
    return true;
}

TEST_FUNC(Parser_Struct_Error_MissingRBrace) {
    ASSERT_TRUE(expect_parser_abort("struct {"));
    return true;
}

TEST_FUNC(Parser_Struct_Error_MissingColon) {
    ASSERT_TRUE(expect_parser_abort("struct { a i32 }"));
    return true;
}

TEST_FUNC(Parser_Struct_Error_MissingType) {
    ASSERT_TRUE(expect_parser_abort("struct { a : }"));
    return true;
}

TEST_FUNC(Parser_Struct_Error_InvalidField) {
    ASSERT_TRUE(expect_parser_abort("struct { 123 }"));
    return true;
}

TEST_FUNC(Parser_RecursionLimit_Aborts) {
    std::string source = "if (";
    for (int i = 0; i < 300; ++i) {
        source += "(";
    }
    source += "a";
    for (int i = 0; i < 300; ++i) {
        source += ")";
    }
    source += ") {}";

    // This test should cause the parser to abort due to the recursion limit.
    // The expect_parser_abort function returns true if the child process aborts as expected.
    ASSERT_TRUE(expect_parser_abort(source.c_str()));

    return true;
}
