#ifndef TEST_UTILS_HPP
#define TEST_UTILS_HPP

#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
#include "compilation_unit.hpp" // Include the new header
#include <new> // For placement new

/**
 * @class ArenaLifetimeGuard
 * @brief A RAII-style guard to automatically reset an ArenaAllocator's state.
 *
 * This guard records the arena's offset upon creation and restores it upon
 * destruction. This is useful in tests to ensure that memory allocated during
 * one test case is automatically cleaned up before the next one runs, preventing
 * memory leaks between tests.
 */
class ArenaLifetimeGuard {
    ArenaAllocator* arena;
    size_t checkpoint;
public:
    /**
     * @brief Constructs the guard and saves the arena's current state.
     * @param a The ArenaAllocator to manage.
     */
    ArenaLifetimeGuard(ArenaAllocator& a) : arena(&a), checkpoint(a.offset) {}

    /**
     * @brief Destroys the guard and restores the arena's state.
     */
    ~ArenaLifetimeGuard() { arena->offset = checkpoint; }

private:
    // Prevent copying of the guard to avoid double-free issues.
    ArenaLifetimeGuard(const ArenaLifetimeGuard&);
    ArenaLifetimeGuard& operator=(const ArenaLifetimeGuard&);
};

/**
 * @class ParserTestContext
 * @brief Encapsulates the setup logic for parser tests.
 *
 * This utility class handles the boilerplate of setting up a CompilationUnit,
 * tokenizing a source string, and creating Parser instances for tests. It owns
 * the token stream, ensuring its lifetime exceeds that of any Parser created.
 */
class ParserTestContext {
public:
    /**
     * @brief Constructs a new ParserTestContext, which tokenizes the source.
     * @param source The source code string to be parsed.
     * @param arena The ArenaAllocator to use for all allocations.
     * @param interner The StringInterner to use for managing strings.
     */
    ParserTestContext(const char* source, ArenaAllocator& arena, StringInterner& interner)
        : unit_(arena, interner)
    {
        u32 file_id = unit_.addSource("test.zig", source);
        unit_.tokenize(file_id);
    }

    /**
     * @brief Returns a new Parser instance that views the tokenized source.
     * @return A new Parser instance.
     */
    Parser getParser() {
        return unit_.createParser();
    }

private:
    CompilationUnit unit_;
};


// Forward declarations for test helpers defined in main.cpp
bool expect_parser_abort(const char* source_code);
bool expect_statement_parser_abort(const char* source_code);

#endif // TEST_UTILS_HPP
