#ifndef TEST_UTILS_HPP
#define TEST_UTILS_HPP

#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
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
 * This utility class handles the boilerplate of setting up a Lexer, tokenizing
 * a source string, and creating a Parser instance. It ensures that parser tests
 * are consistent and easy to write. The context owns the token array and the parser.
 */
class ParserTestContext {
public:
    /**
     * @brief Constructs a new ParserTestContext.
     * @param source The source code string to be parsed.
     * @param arena The ArenaAllocator to use for all allocations.
     * @param interner The StringInterner to use for managing strings.
     */
    ParserTestContext(const char* source, ArenaAllocator& arena, StringInterner& interner)
        : arena_(arena),
          token_array_(arena),
          parser_(NULL, 0, &arena) // Dummy initialization
    {
        SourceManager sm(arena);
        u32 file_id = sm.addFile("test.zig", source, strlen(source));
        Lexer lexer(sm, interner, arena, file_id);

        Token token;
        do {
            token = lexer.nextToken();
            token_array_.append(token);
        } while (token.type != TOKEN_EOF);

        // Use placement new to construct the parser in place
        new (&parser_) Parser(token_array_.getData(), token_array_.length(), &arena_);
    }

    /**
     * @brief Returns a reference to the Parser instance for the tokenized source code.
     * @return A reference to the Parser instance.
     */
    Parser& getParser() {
        parser_.reset();
        return parser_;
    }

private:
    ArenaAllocator& arena_;
    DynamicArray<Token> token_array_;
    Parser parser_;
};

#endif // TEST_UTILS_HPP
