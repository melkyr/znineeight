#ifndef TEST_COMPILATION_UNIT_HPP
#define TEST_COMPILATION_UNIT_HPP

// TEST-ONLY: Helper for integration testing
// Not part of the production codebase

#include "compilation_unit.hpp"
#include "parser.hpp"
#include "type_checker.hpp"
#include "name_collision_detector.hpp"
#include "signature_analyzer.hpp"
#include "c89_feature_validator.hpp"
#include "ast.hpp"

/**
 * @class TestCompilationUnit
 * @brief Extension of CompilationUnit specifically for integration tests.
 *
 * Provides methods to execute the compilation pipeline and extract specific
 * AST nodes for validation.
 */
class TestCompilationUnit : public CompilationUnit {
public:
    ASTNode* last_ast;

    TestCompilationUnit(ArenaAllocator& arena, StringInterner& interner)
        : CompilationUnit(arena, interner), last_ast(NULL) {
        setTestMode(true);
        injectRuntimeSymbols();
    }

    /**
     * @brief Performs the full compilation pipeline for a given file and stores the AST.
     * @param file_id The ID of the file to compile.
     * @return True if the pipeline finished without errors.
     */
    bool performTestPipeline(u32 file_id) {
        Parser* parser = createParser(file_id);
        last_ast = parser->parse();
        if (!last_ast) return false;

        // Pass 0.25: Name Collision Detection
        NameCollisionDetector name_detector(*this);
        name_detector.check(last_ast);
        if (name_detector.hasCollisions()) return false;

        // Pass 0.5: Type Checking (resolves types and sets node->resolved_type)
        TypeChecker checker(*this);
        checker.check(last_ast);

        // Pass 0.75: Signature Analysis
        SignatureAnalyzer sig_analyzer(*this);
        sig_analyzer.analyze(last_ast);

        // Pass 1.0: C89 feature validation
        C89FeatureValidator validator(*this);
        bool success = validator.validate(last_ast);

        return success && !sig_analyzer.hasInvalidSignatures() && !getErrorHandler().hasErrors();
    }

    /**
     * @brief Extracts a test expression from a function body.
     * Searches for the first statement in the first top-level function.
     */
    const ASTNode* extractTestExpression() const {
        if (!last_ast || last_ast->type != NODE_BLOCK_STMT) return NULL;

        DynamicArray<ASTNode*>* top_levels = last_ast->as.block_stmt.statements;
        for (size_t i = 0; i < top_levels->length(); ++i) {
            ASTNode* item = (*top_levels)[i];
            if (item->type == NODE_FN_DECL) {
                ASTNode* body = item->as.fn_decl->body;
                if (body && body->type == NODE_BLOCK_STMT && body->as.block_stmt.statements->length() > 0) {
                    ASTNode* stmt = (*body->as.block_stmt.statements)[0];
                    if (stmt->type == NODE_EXPRESSION_STMT) {
                        return stmt->as.expression_stmt.expression;
                    } else if (stmt->type == NODE_RETURN_STMT) {
                        return stmt->as.return_stmt.expression;
                    }
                }
            }
        }
        return NULL;
    }

    /**
     * @brief Helper to get the resolved type of a node.
     */
    Type* resolveType(const ASTNode* node) const {
        return node ? node->resolved_type : NULL;
    }
};

#endif // TEST_COMPILATION_UNIT_HPP
