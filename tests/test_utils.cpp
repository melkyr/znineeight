#include "test_utils.hpp"
#include "type_checker.hpp"
#include <sys/wait.h>
#include <unistd.h>

// Helper function to check for aborts in a forked process
static bool expect_abort(void (*test_func)()) {
    pid_t pid = fork();
    if (pid == 0) {
        // Child process
        test_func();
        exit(0); // Should not be reached
    } else if (pid > 0) {
        // Parent process
        int status;
        waitpid(pid, &status, 0);
        return WIFSIGNALED(status) && (WTERMSIG(status) == SIGABRT);
    }
    return false; // Fork failed
}

// Global state for passing test data to the forked process
static const char* g_source_for_abort_test = NULL;

static void parse_and_expect_abort() {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", g_source_for_abort_test);
    Parser* p = comp_unit.createParser(file_id);
    p->parse();
}

static void type_check_and_expect_abort() {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", g_source_for_abort_test);
    Parser* p = comp_unit.createParser(file_id);
    ASTNode* root = p->parse();
    TypeChecker tc(comp_unit);
    tc.check(root);
}

bool expect_parser_abort(const char* source) {
    g_source_for_abort_test = source;
    return expect_abort(parse_and_expect_abort);
}

bool expect_statement_parser_abort(const char* source) {
    g_source_for_abort_test = source;
    return expect_abort(parse_and_expect_abort);
}

bool expect_type_checker_abort(const char* source) {
    g_source_for_abort_test = source;
    return expect_abort(type_check_and_expect_abort);
}

bool expect_parser_oom_abort(const char* source) {
    // This is a simplified check. A real OOM test might need
    // a very small, controlled arena size.
    g_source_for_abort_test = source;
    return expect_abort(parse_and_expect_abort);
}
