#ifndef TEST_UTILS_HPP
#define TEST_UTILS_HPP

#include "parser.hpp"
#include "lexer.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
#include "compilation_unit.hpp"
#include <new> // For placement new

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

    Parser getParser() {
        return unit_.createParser(file_id_);
    }

    CompilationUnit& getCompilationUnit() {
        return unit_;
    }

private:
    CompilationUnit unit_;
    u32 file_id_;
};

// Forward declarations for test helpers defined in main.cpp
bool expect_parser_abort(const char* source_code);
bool expect_statement_parser_abort(const char* source_code);
bool expect_type_checker_abort(const char* source_code);

#endif // TEST_UTILS_HPP
