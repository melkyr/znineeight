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
static bool expect_parser_abort(const char* source_code) {
    char command[512];
#if defined(_WIN32)
    // On Windows, snprintf is available in modern SDKs but might not be in C++98 compilers.
    // _snprintf is the MSVC equivalent.
    _snprintf(command, sizeof(command), "test_runner.exe --run-parser-test \"%s\"", source_code);
    command[sizeof(command) - 1] = '\0'; // Ensure null termination

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
        execlp("./test_runner", "test_runner", "--run-parser-test", source_code, (char*)NULL);
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

TEST_FUNC(Parser_Error_OnMissingColon) {
    // This source code is missing a colon after the identifier 'x'
    const char* source = "var x i32 = 42;";
    ASSERT_TRUE(expect_parser_abort(source));
    return true;
}
