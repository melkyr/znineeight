#include "test_framework.hpp"
#include "test_utils.hpp"
#include "ast.hpp"
#include "parser.hpp"

/**
 * @file test_parser_lifecycle.cpp
 * @brief Contains tests for the Parser's lifecycle and memory safety.
 */

/**
 * @brief Verifies that making a copy of a Parser is safe and does not lead to a
 * use-after-free or double-free bug.
 *
 * This test confirms that the Parser performs a shallow copy and does not own
 * the resources it points to (like the token stream or the arena). The test
 * creates a parser in an inner scope, copies it to a parser in an outer scope,
 * and then lets the inner scope parser be destroyed. It then uses the copied
 * parser to ensure its underlying pointers are still valid.
 */
TEST_FUNC(Parser_CopyIsSafeAndDoesNotDoubleFree) {
    const char* source = "const y: i32 = 100;";
    ArenaAllocator arena(1024);
    StringInterner interner(arena);

    // We must declare the copy outside the inner scope.
    // Initialize with a dummy parser that will be overwritten.
    Parser parser_copy = create_parser_for_test("", arena, interner);

    {
        // Inner scope to control the lifetime of the original parser
        Parser parser_original = create_parser_for_test(source, arena, interner);

        // Use the copy assignment operator. Both parsers now point to the same
        // token stream, which is allocated within the long-lived 'arena'.
        parser_copy = parser_original;

        // At the end of this scope, 'parser_original' is destroyed.
        // If its destructor incorrectly freed the token stream,
        // 'parser_copy' would now have dangling pointers.
    }

    // Now, use the copied parser after the original has been destroyed.
    // This will crash or fail if the underlying memory was freed.
    ASTNode* decl = parser_copy.parseVarDecl();

    // Assert that parsing was successful, proving the copy is still valid.
    ASSERT_TRUE(decl != NULL);
    ASSERT_TRUE(decl->type == NODE_VAR_DECL);
    ASSERT_STREQ("y", decl->as.var_decl->name);

    return true; // Test passed
}
