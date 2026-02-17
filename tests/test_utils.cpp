#include "test_utils.hpp"
#include "type_checker.hpp"
#include "lifetime_analyzer.hpp"
#include "c89_feature_validator.hpp"
#include "name_collision_detector.hpp"
#include "signature_analyzer.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>

#if defined(_WIN32)
#include <windows.h>
#else
#include <sys/wait.h>
#include <unistd.h>
#endif

#if defined(_WIN32)
static bool run_test_in_child_process(const char* source, const char* test_type_flag, DWORD expected_exit_code) {
    // 1. Create a temporary file to pass source code
    char temp_path[MAX_PATH];
    char temp_filename[MAX_PATH];
    GetTempPath(MAX_PATH, temp_path);
    GetTempFileName(temp_path, "zig_test", 0, temp_filename);

    FILE* file = fopen(temp_filename, "w");
    if (!file) return false;
    fputs(source, file);
    fclose(file);

    // 2. Get path to current executable
    char exe_path[MAX_PATH];
    GetModuleFileName(NULL, exe_path, MAX_PATH);

    // 3. Create child process
    STARTUPINFO si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    char command_line[1024];
    sprintf(command_line, "\"%s\" %s %s", exe_path, test_type_flag, temp_filename);

    if (!CreateProcess(NULL, command_line, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        remove(temp_filename);
        return false;
    }

    // 4. Wait for child to exit and check exit code
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD exit_code;
    GetExitCodeProcess(pi.hProcess, &exit_code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    remove(temp_filename);

    return exit_code == expected_exit_code;
}

static bool expect_abort(const char* source, const char* test_type_flag) {
    // MSVC abort() has exit code 3
    return run_test_in_child_process(source, test_type_flag, 3);
}
#else
// POSIX implementation using fork()
static bool expect_abort(void (*test_func)()) {
    pid_t pid = fork();
    if (pid == 0) { // Child process
        test_func();
        exit(0);
    } else if (pid > 0) { // Parent process
        int status;
        waitpid(pid, &status, 0);
        return WIFSIGNALED(status) && (WTERMSIG(status) == SIGABRT);
    }
    return false; // Fork failed
}
#endif

// These functions are executed IN THE CHILD PROCESS
void run_parser_test_in_child(const char* source) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    comp_unit.injectRuntimeSymbols();
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser* p = comp_unit.createParser(file_id);
    p->parse();
}

void run_type_checker_test_in_child(const char* source) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    comp_unit.injectRuntimeSymbols();
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser* p = comp_unit.createParser(file_id);
    ASTNode* root = p->parse();

    // Run Name Collision Detector
    NameCollisionDetector name_detector(comp_unit);
    name_detector.check(root);

    // Run the type checker before the C89 feature validator.
    TypeChecker tc(comp_unit);
    tc.check(root);

    // Run Signature Analyzer
    SignatureAnalyzer sig_analyzer(comp_unit);
    sig_analyzer.analyze(root);

    C89FeatureValidator validator(comp_unit);
    validator.validate(root);

    LifetimeAnalyzer la(comp_unit);
    la.analyze(root);

    if (comp_unit.getErrorHandler().hasErrors()) {
        fprintf(stderr, "Child process: errors found, aborting...\n");
        comp_unit.getErrorHandler().printErrors();
        abort();
    }
}


// Global state for passing test data to the forked process (POSIX only)
static const char* g_source_for_abort_test = NULL;

static void posix_parse_and_expect_abort() {
    run_parser_test_in_child(g_source_for_abort_test);
}

static void posix_type_check_and_expect_abort() {
    run_type_checker_test_in_child(g_source_for_abort_test);
}


// These functions are called by the test runner in the main process
bool expect_parser_abort(const char* source) {
#if defined(_WIN32)
    return expect_abort(source, "--run_parser_test");
#else
    g_source_for_abort_test = source;
    return expect_abort(posix_parse_and_expect_abort);
#endif
}

bool expect_statement_parser_abort(const char* source) {
    // Functionally identical to expect_parser_abort for our purposes
    return expect_parser_abort(source);
}

bool expect_type_checker_abort(const char* source) {
#if defined(_WIN32)
    return expect_abort(source, "--run_type_checker_test");
#else
    g_source_for_abort_test = source;
    return expect_abort(posix_type_check_and_expect_abort);
#endif
}

bool run_type_checker_test_successfully(const char* source) {
#if defined(_WIN32)
    return run_test_in_child_process(source, "--run_type_checker_test", 0);
#else
    // For POSIX, we need a different approach. We'll fork and check for a successful exit.
    // This is a simplified version. A more robust implementation would be needed
    // for a real-world scenario.
    pid_t pid = fork();
    if (pid == 0) { // Child process
        run_type_checker_test_in_child(source);
        exit(0);
    } else if (pid > 0) { // Parent process
        int status;
        waitpid(pid, &status, 0);
        return WIFEXITED(status) && WEXITSTATUS(status) == 0;
    }
    return false; // Fork failed
#endif
}

bool expect_parser_oom_abort(const char* source) {
    // This is a simplified check. A real OOM test might need
    // a very small, controlled arena size.
    return expect_parser_abort(source);
}
