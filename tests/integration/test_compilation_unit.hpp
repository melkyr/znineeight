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
#include "utils.hpp"
#include "mock_emitter.hpp"

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
     * @brief Recursively searches for a function declaration with the given name in the AST.
     * @param node The AST node to start searching from.
     * @param name The name of the function to find.
     * @return The ASTFnDeclNode if found, NULL otherwise.
     */
    const ASTFnDeclNode* findFunctionDeclaration(const ASTNode* node, const char* name) const {
        if (!node) return NULL;

        if (node->type == NODE_FN_DECL) {
            if (strings_equal(node->as.fn_decl->name, name)) {
                return node->as.fn_decl;
            }
        }

        // Search in children
        if (node->type == NODE_BLOCK_STMT) {
            DynamicArray<ASTNode*>* stmts = node->as.block_stmt.statements;
            for (size_t i = 0; i < stmts->length(); ++i) {
                const ASTFnDeclNode* found = findFunctionDeclaration((*stmts)[i], name);
                if (found) return found;
            }
        } else if (node->type == NODE_STRUCT_DECL) {
            DynamicArray<ASTNode*>* fields = node->as.struct_decl->fields;
            for (size_t i = 0; i < fields->length(); ++i) {
                const ASTFnDeclNode* found = findFunctionDeclaration((*fields)[i], name);
                if (found) return found;
            }
        } else if (node->type == NODE_UNION_DECL) {
            DynamicArray<ASTNode*>* fields = node->as.union_decl->fields;
            for (size_t i = 0; i < fields->length(); ++i) {
                const ASTFnDeclNode* found = findFunctionDeclaration((*fields)[i], name);
                if (found) return found;
            }
        }

        return NULL;
    }

    /**
     * @brief Extracts a function declaration by name.
     */
    const ASTFnDeclNode* extractFunctionDeclaration(const char* name) const {
        return findFunctionDeclaration(last_ast, name);
    }

    /**
     * @brief Recursively searches for a function call to the given name in the AST.
     */
    const ASTNode* findFunctionCall(const ASTNode* node, const char* name) const {
        if (!node) return NULL;

        if (node->type == NODE_FUNCTION_CALL) {
            ASTNode* callee = node->as.function_call->callee;
            if (callee->type == NODE_IDENTIFIER && strings_equal(callee->as.identifier.name, name)) {
                return node;
            }

            // Recurse into arguments in case it's a nested call (e.g. foo(bar()))
            DynamicArray<ASTNode*>* args = node->as.function_call->args;
            if (args) {
                for (size_t i = 0; i < args->length(); ++i) {
                    const ASTNode* found = findFunctionCall((*args)[i], name);
                    if (found) return found;
                }
            }
        }

        // Search in other children
        if (node->type == NODE_BLOCK_STMT) {
            DynamicArray<ASTNode*>* stmts = node->as.block_stmt.statements;
            for (size_t i = 0; i < stmts->length(); ++i) {
                const ASTNode* found = findFunctionCall((*stmts)[i], name);
                if (found) return found;
            }
        } else if (node->type == NODE_FN_DECL) {
            return findFunctionCall(node->as.fn_decl->body, name);
        } else if (node->type == NODE_IF_STMT) {
            const ASTNode* found = findFunctionCall(node->as.if_stmt->condition, name);
            if (found) return found;
            found = findFunctionCall(node->as.if_stmt->then_block, name);
            if (found) return found;
            return findFunctionCall(node->as.if_stmt->else_block, name);
        } else if (node->type == NODE_WHILE_STMT) {
            const ASTNode* found = findFunctionCall(node->as.while_stmt.condition, name);
            if (found) return found;
            return findFunctionCall(node->as.while_stmt.body, name);
        } else if (node->type == NODE_RETURN_STMT) {
            return findFunctionCall(node->as.return_stmt.expression, name);
        } else if (node->type == NODE_EXPRESSION_STMT) {
            return findFunctionCall(node->as.expression_stmt.expression, name);
        } else if (node->type == NODE_BINARY_OP) {
            const ASTNode* found = findFunctionCall(node->as.binary_op->left, name);
            if (found) return found;
            return findFunctionCall(node->as.binary_op->right, name);
        } else if (node->type == NODE_UNARY_OP) {
            return findFunctionCall(node->as.unary_op.operand, name);
        } else if (node->type == NODE_PAREN_EXPR) {
            return findFunctionCall(node->as.paren_expr.expr, name);
        } else if (node->type == NODE_VAR_DECL) {
            return findFunctionCall(node->as.var_decl->initializer, name);
        }

        return NULL;
    }

    /**
     * @brief Extracts a function call node by name.
     */
    const ASTNode* extractFunctionCall(const char* name) const {
        return findFunctionCall(last_ast, name);
    }

    /**
     * @brief Validates that a function signature emits the expected C89 string.
     */
    bool validateFunctionSignature(const char* name, const std::string& expectedC89) {
        const ASTFnDeclNode* fn = extractFunctionDeclaration(name);
        if (!fn) {
            printf("FAIL: Could not find function declaration for '%s'.\n", name);
            return false;
        }

        Symbol* sym = getSymbolTable().findInAnyScope(name);
        if (!sym) {
            printf("FAIL: Could not find symbol for function '%s'.\n", name);
            return false;
        }

        MockC89Emitter emitter(&getCallSiteLookupTable(), &getSymbolTable());
        std::string actual = emitter.emitFunctionSignature(fn, sym);

        if (actual != expectedC89) {
            printf("FAIL: Signature emission mismatch for function '%s'.\nExpected: %s\nActual:   %s\n", name, expectedC89.c_str(), actual.c_str());
            return false;
        }

        return true;
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
                if (body && body->type == NODE_BLOCK_STMT) {
                    DynamicArray<ASTNode*>* stmts = body->as.block_stmt.statements;
                    for (size_t j = 0; j < stmts->length(); ++j) {
                        ASTNode* stmt = (*stmts)[j];
                        if (stmt->type == NODE_EXPRESSION_STMT) {
                            return stmt->as.expression_stmt.expression;
                        } else if (stmt->type == NODE_RETURN_STMT) {
                            return stmt->as.return_stmt.expression;
                        }
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

    /**
     * @brief Recursively searches for a variable declaration with the given name in the AST.
     * @param node The AST node to start searching from.
     * @param name The name of the variable to find.
     * @return The ASTVarDeclNode if found, NULL otherwise.
     */
    const ASTVarDeclNode* findVariableDeclaration(const ASTNode* node, const char* name) const {
        if (!node) return NULL;

        if (node->type == NODE_VAR_DECL) {
            if (strings_equal(node->as.var_decl->name, name)) {
                return node->as.var_decl;
            }
        }

        // Search in children
        if (node->type == NODE_BLOCK_STMT) {
            DynamicArray<ASTNode*>* stmts = node->as.block_stmt.statements;
            for (size_t i = 0; i < stmts->length(); ++i) {
                const ASTVarDeclNode* found = findVariableDeclaration((*stmts)[i], name);
                if (found) return found;
            }
        } else if (node->type == NODE_FN_DECL) {
            return findVariableDeclaration(node->as.fn_decl->body, name);
        } else if (node->type == NODE_IF_STMT) {
            const ASTVarDeclNode* found = findVariableDeclaration(node->as.if_stmt->then_block, name);
            if (found) return found;
            return findVariableDeclaration(node->as.if_stmt->else_block, name);
        } else if (node->type == NODE_WHILE_STMT) {
            return findVariableDeclaration(node->as.while_stmt.body, name);
        }

        return NULL;
    }

    /**
     * @brief Extracts a variable declaration by name.
     */
    const ASTVarDeclNode* extractVariableDeclaration(const char* name) const {
        return findVariableDeclaration(last_ast, name);
    }

    /**
     * @brief Validates that a function declaration (signature + body) emits the expected C89 string.
     */
    bool validateFunctionEmission(const char* name, const std::string& expectedC89) {
        const ASTFnDeclNode* fn = extractFunctionDeclaration(name);
        if (!fn) {
            printf("FAIL: Could not find function declaration for '%s'.\n", name);
            return false;
        }

        Symbol* sym = getSymbolTable().findInAnyScope(name);
        if (!sym) {
            printf("FAIL: Could not find symbol for function '%s'.\n", name);
            return false;
        }

        MockC89Emitter emitter(&getCallSiteLookupTable(), &getSymbolTable());
        std::string actual = emitter.emitFunctionDeclaration(fn, sym);

        if (actual != expectedC89) {
            printf("FAIL: Emission mismatch for function '%s'.\nExpected: %s\nActual:   %s\n", name, expectedC89.c_str(), actual.c_str());
            return false;
        }

        return true;
    }

    /**
     * @brief Validates that the first expression in the test source has the expected type kind.
     */
    bool validateExpressionType(TypeKind expected_kind) {
        const ASTNode* expr = extractTestExpression();
        if (!expr) {
            printf("FAIL: Could not extract test expression.\n");
            return false;
        }

        if (!expr->resolved_type) {
            printf("FAIL: Expression has no resolved type.\n");
            return false;
        }

        if (expr->resolved_type->kind != expected_kind) {
            printf("FAIL: Type kind mismatch.\nExpected: %d\nActual:   %d\n", (int)expected_kind, (int)expr->resolved_type->kind);
            return false;
        }

        return true;
    }

    /**
     * @brief Validates that the first expression in the test source emits the expected C89 string.
     */
    bool validateExpressionEmission(const std::string& expectedC89) {
        const ASTNode* expr = extractTestExpression();
        if (!expr) {
            printf("FAIL: Could not extract test expression.\n");
            return false;
        }

        MockC89Emitter emitter(&getCallSiteLookupTable(), &getSymbolTable());
        std::string actual = emitter.emitExpression(expr);

        if (actual != expectedC89) {
            printf("FAIL: Expression emission mismatch.\nExpected: %s\nActual:   %s\n", expectedC89.c_str(), actual.c_str());
            return false;
        }

        return true;
    }

    /**
     * @brief Validates that a variable declaration emits the expected C89 string.
     */
    bool validateVariableEmission(const char* name, const std::string& expectedC89) {
        const ASTVarDeclNode* decl = extractVariableDeclaration(name);
        if (!decl) return false;

        Symbol* sym = getSymbolTable().findInAnyScope(name);
        if (!sym) return false;

        MockC89Emitter emitter(&getCallSiteLookupTable(), &getSymbolTable());
        std::string actual = emitter.emitVariableDeclaration(decl, sym);

        if (actual != expectedC89) {
            printf("FAIL: Emission mismatch for variable '%s'.\nExpected: %s\nActual:   %s\n", name, expectedC89.c_str(), actual.c_str());
            return false;
        }

        return true;
    }

    /**
     * @brief Validates that a call site was correctly resolved in the lookup table.
     */
    bool validateCallResolution(const char* name, CallType expected_type) {
        const ASTNode* call_node = extractFunctionCall(name);
        if (!call_node) {
            printf("FAIL: Could not find call to '%s'.\n", name);
            return false;
        }

        const CallSiteEntry* entry = getCallSiteLookupTable().findByCallNode(const_cast<ASTNode*>(call_node));
        if (!entry) {
            printf("FAIL: Call to '%s' not found in CallSiteLookupTable.\n", name);
            return false;
        }

        if (entry->call_type != expected_type) {
            printf("FAIL: Call type mismatch for '%s'. Expected %d, got %d.\n", name, (int)expected_type, (int)entry->call_type);
            return false;
        }

        if (!entry->resolved) {
            printf("FAIL: Call to '%s' is not resolved. Reason: %s\n", name, entry->error_if_unresolved ? entry->error_if_unresolved : "unknown");
            return false;
        }

        return true;
    }
};

#endif // TEST_COMPILATION_UNIT_HPP
