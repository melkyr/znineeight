#ifndef TEST_UTILS_HPP
#define TEST_UTILS_HPP

#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
#include "compilation_unit.hpp"
#include <new> // For placement new
#include <cmath> // For fabs

class ArenaLifetimeGuard {
    ArenaAllocator* arena;
    size_t checkpoint;
public:
    ArenaLifetimeGuard(ArenaAllocator& a) : arena(&a), checkpoint(a.getOffset()) {}
    ~ArenaLifetimeGuard() { arena->reset(checkpoint); }
private:
    ArenaLifetimeGuard(const ArenaLifetimeGuard&);
    ArenaLifetimeGuard& operator=(const ArenaLifetimeGuard&);
};

class ParserTestContext {
public:
    ParserTestContext(const char* source, ArenaAllocator& arena, StringInterner& interner)
        : unit_(arena, interner) {
        file_id_ = unit_.addSource("test.zig", source);
    }

    Parser* getParser() {
        return unit_.createParser(file_id_);
    }

    CompilationUnit& getCompilationUnit() {
        return unit_;
    }

private:
    CompilationUnit unit_;
    u32 file_id_;
};

// Forward declarations for test helpers
bool expect_parser_abort(const char* source_code);
bool expect_statement_parser_abort(const char* source_code);
bool expect_type_checker_abort(const char* source_code);

/**
 * @brief Runs the type checker on the given source and expects it to succeed.
 * @param source The source code to compile.
 * @return True if the type checker runs without aborting and returns exit code 0.
 */
bool run_type_checker_test_successfully(const char* source);
bool expect_parser_oom_abort(const char* source);


// These are called by main() when running as a child process for a test
void run_parser_test_in_child(const char* source);
void run_type_checker_test_in_child(const char* source);

inline bool compare_floats(double a, double b) {
    double diff = a - b;
    if (diff < 0) diff = -diff;
    return diff < 1e-9;
}

#endif // TEST_UTILS_HPP
