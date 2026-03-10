#include "ast_utils.hpp"
#include "symbol_table.hpp"
#include "type_system.hpp"

bool isTypeExpression(ASTNode* node, SymbolTable& symbols) {
    if (!node) return false;
    switch (node->type) {
        case NODE_TYPE_NAME:
        case NODE_POINTER_TYPE:
        case NODE_ARRAY_TYPE:
        case NODE_STRUCT_DECL:
        case NODE_ENUM_DECL:
        case NODE_UNION_DECL:
        case NODE_ERROR_UNION_TYPE:
        case NODE_OPTIONAL_TYPE:
        case NODE_ERROR_SET_DEFINITION:
        case NODE_ERROR_SET_MERGE:
            return true;
        case NODE_IDENTIFIER: {
            // Check builtin types first
            if (resolvePrimitiveTypeName(node->as.identifier.name)) {
                return true;
            }
            // Then check symbol table
            Symbol* sym = symbols.lookup(node->as.identifier.name);
            return sym && sym->kind == SYMBOL_TYPE;
        }
        default:
            return false;
    }
}

void forEachChild(ASTNode* node, ChildVisitor& visitor) {
    if (!node) return;

    switch (node->type) {
        // ~~~~~~~~~~~~~~~~~~~~~~ Expressions ~~~~~~~~~~~~~~~~~~~~~~
        case NODE_ASSIGNMENT:
            if (node->as.assignment) {
                // Zig evaluates RHS before LHS side effects
                visitor.visitChild(&node->as.assignment->rvalue);
                visitor.visitChild(&node->as.assignment->lvalue);
            }
            break;
        case NODE_COMPOUND_ASSIGNMENT:
            if (node->as.compound_assignment) {
                // Zig evaluates RHS before LHS side effects
                visitor.visitChild(&node->as.compound_assignment->rvalue);
                visitor.visitChild(&node->as.compound_assignment->lvalue);
            }
            break;
        case NODE_UNARY_OP:
            visitor.visitChild(&node->as.unary_op.operand);
            break;
        case NODE_BINARY_OP:
            if (node->as.binary_op) {
                visitor.visitChild(&node->as.binary_op->left);
                visitor.visitChild(&node->as.binary_op->right);
            }
            break;
        case NODE_FUNCTION_CALL:
            if (node->as.function_call) {
                visitor.visitChild(&node->as.function_call->callee);
                if (node->as.function_call->args) {
                    for (size_t i = 0; i < node->as.function_call->args->length(); ++i) {
                        visitor.visitChild(&(*node->as.function_call->args)[i]);
                    }
                }
            }
            break;
        case NODE_ARRAY_ACCESS:
            if (node->as.array_access) {
                visitor.visitChild(&node->as.array_access->array);
                visitor.visitChild(&node->as.array_access->index);
            }
            break;
        case NODE_ARRAY_SLICE:
            if (node->as.array_slice) {
                visitor.visitChild(&node->as.array_slice->array);
                visitor.visitChild(&node->as.array_slice->start);
                visitor.visitChild(&node->as.array_slice->end);
                visitor.visitChild(&node->as.array_slice->base_ptr);
                visitor.visitChild(&node->as.array_slice->len);
            }
            break;
        case NODE_MEMBER_ACCESS:
            if (node->as.member_access) {
                visitor.visitChild(&node->as.member_access->base);
            }
            break;
        case NODE_STRUCT_INITIALIZER:
            if (node->as.struct_initializer) {
                visitor.visitChild(&node->as.struct_initializer->type_expr);
                if (node->as.struct_initializer->fields) {
                    for (size_t i = 0; i < node->as.struct_initializer->fields->length(); ++i) {
                        visitor.visitChild(&(*node->as.struct_initializer->fields)[i]->value);
                    }
                }
            }
            break;
        case NODE_TUPLE_LITERAL:
            if (node->as.tuple_literal && node->as.tuple_literal->elements) {
                for (size_t i = 0; i < node->as.tuple_literal->elements->length(); ++i) {
                    visitor.visitChild(&(*node->as.tuple_literal->elements)[i]);
                }
            }
            break;

        // ~~~~~~~~~~~~~~~~~~~~~~~ Literals ~~~~~~~~~~~~~~~~~~~~~~~~
        case NODE_BOOL_LITERAL:
        case NODE_NULL_LITERAL:
        case NODE_UNDEFINED_LITERAL:
        case NODE_INTEGER_LITERAL:
        case NODE_FLOAT_LITERAL:
        case NODE_CHAR_LITERAL:
        case NODE_STRING_LITERAL:
        case NODE_ERROR_LITERAL:
        case NODE_IDENTIFIER:
        case NODE_UNREACHABLE:
            break; // No children

        // ~~~~~~~~~~~~~~~~~~~~~~ Statements ~~~~~~~~~~~~~~~~~~~~~~~
        case NODE_BLOCK_STMT:
            if (node->as.block_stmt.statements) {
                // Iterate backwards to support transformations that insert statements
                // at the current index without causing infinite re-processing.
                for (int i = (int)node->as.block_stmt.statements->length() - 1; i >= 0; --i) {
                    visitor.visitChild(&(*node->as.block_stmt.statements)[i]);
                }
            }
            break;
        case NODE_EMPTY_STMT:
            break; // No children
        case NODE_IF_STMT:
            if (node->as.if_stmt) {
                visitor.visitChild(&node->as.if_stmt->condition);
                visitor.visitChild(&node->as.if_stmt->then_block);
                visitor.visitChild(&node->as.if_stmt->else_block);
            }
            break;
        case NODE_IF_EXPR:
            if (node->as.if_expr) {
                visitor.visitChild(&node->as.if_expr->condition);
                visitor.visitChild(&node->as.if_expr->then_expr);
                visitor.visitChild(&node->as.if_expr->else_expr);
            }
            break;
        case NODE_WHILE_STMT:
            if (node->as.while_stmt) {
                visitor.visitChild(&node->as.while_stmt->condition);
                visitor.visitChild(&node->as.while_stmt->body);
                visitor.visitChild(&node->as.while_stmt->iter_expr);
            }
            break;
        case NODE_BREAK_STMT:
        case NODE_CONTINUE_STMT:
            break; // No children
        case NODE_RETURN_STMT:
            visitor.visitChild(&node->as.return_stmt.expression);
            break;
        case NODE_DEFER_STMT:
            visitor.visitChild(&node->as.defer_stmt.statement);
            break;
        case NODE_FOR_STMT:
            if (node->as.for_stmt) {
                visitor.visitChild(&node->as.for_stmt->iterable_expr);
                visitor.visitChild(&node->as.for_stmt->body);
            }
            break;
        case NODE_EXPRESSION_STMT:
            visitor.visitChild(&node->as.expression_stmt.expression);
            break;
        case NODE_PAREN_EXPR:
            visitor.visitChild(&node->as.paren_expr.expr);
            break;
        case NODE_RANGE:
            visitor.visitChild(&node->as.range.start);
            visitor.visitChild(&node->as.range.end);
            break;
        case NODE_SWITCH_STMT:
            if (node->as.switch_stmt) {
                visitor.visitChild(&node->as.switch_stmt->expression);
                if (node->as.switch_stmt->prongs) {
                    for (size_t i = 0; i < node->as.switch_stmt->prongs->length(); ++i) {
                        ASTSwitchStmtProngNode* prong = (*node->as.switch_stmt->prongs)[i];
                        if (prong->items) {
                            for (size_t j = 0; j < prong->items->length(); ++j) {
                                visitor.visitChild(&(*prong->items)[j]);
                            }
                        }
                        visitor.visitChild(&prong->body);
                    }
                }
            }
            break;

        // ~~~~~~~~~~~~~~~~~~~ Expressions ~~~~~~~~~~~~~~~~~~~~~
        case NODE_SWITCH_EXPR:
            if (node->as.switch_expr) {
                visitor.visitChild(&node->as.switch_expr->expression);
                if (node->as.switch_expr->prongs) {
                    for (size_t i = 0; i < node->as.switch_expr->prongs->length(); ++i) {
                        ASTSwitchProngNode* prong = (*node->as.switch_expr->prongs)[i];
                        if (prong->items) {
                            for (size_t j = 0; j < prong->items->length(); ++j) {
                                visitor.visitChild(&(*prong->items)[j]);
                            }
                        }
                        visitor.visitChild(&prong->body);
                    }
                }
            }
            break;
        case NODE_PTR_CAST:
            if (node->as.ptr_cast) {
                visitor.visitChild(&node->as.ptr_cast->target_type);
                visitor.visitChild(&node->as.ptr_cast->expr);
            }
            break;
        case NODE_INT_CAST:
        case NODE_FLOAT_CAST:
            if (node->as.numeric_cast) {
                visitor.visitChild(&node->as.numeric_cast->target_type);
                visitor.visitChild(&node->as.numeric_cast->expr);
            }
            break;
        case NODE_OFFSET_OF:
            if (node->as.offset_of) {
                visitor.visitChild(&node->as.offset_of->type_expr);
            }
            break;

        // ~~~~~~~~~~~~~~~~~~~~ Declarations ~~~~~~~~~~~~~~~~~~~~~~~
        case NODE_VAR_DECL:
            if (node->as.var_decl) {
                visitor.visitChild(&node->as.var_decl->type);
                visitor.visitChild(&node->as.var_decl->initializer);
            }
            break;
        case NODE_PARAM_DECL:
            visitor.visitChild(&node->as.param_decl.type);
            break;
        case NODE_FN_DECL:
            if (node->as.fn_decl) {
                if (node->as.fn_decl->params) {
                    for (size_t i = 0; i < node->as.fn_decl->params->length(); ++i) {
                        visitor.visitChild(&(*node->as.fn_decl->params)[i]);
                    }
                }
                visitor.visitChild(&node->as.fn_decl->return_type);
                visitor.visitChild(&node->as.fn_decl->body);
            }
            break;
        case NODE_STRUCT_FIELD:
            if (node->as.struct_field) {
                visitor.visitChild(&node->as.struct_field->type);
            }
            break;

        // ~~~~~~~~~~~~~~ Container Declarations ~~~~~~~~~~~~~~~~~
        case NODE_STRUCT_DECL:
            if (node->as.struct_decl && node->as.struct_decl->fields) {
                for (size_t i = 0; i < node->as.struct_decl->fields->length(); ++i) {
                    visitor.visitChild(&(*node->as.struct_decl->fields)[i]);
                }
            }
            break;
        case NODE_UNION_DECL:
            if (node->as.union_decl) {
                if (node->as.union_decl->fields) {
                    for (size_t i = 0; i < node->as.union_decl->fields->length(); ++i) {
                        visitor.visitChild(&(*node->as.union_decl->fields)[i]);
                    }
                }
                visitor.visitChild(&node->as.union_decl->tag_type_expr);
            }
            break;
        case NODE_ENUM_DECL:
            if (node->as.enum_decl) {
                visitor.visitChild(&node->as.enum_decl->backing_type);
                if (node->as.enum_decl->fields) {
                    for (size_t i = 0; i < node->as.enum_decl->fields->length(); ++i) {
                        visitor.visitChild(&(*node->as.enum_decl->fields)[i]);
                    }
                }
            }
            break;
        case NODE_ERROR_SET_DEFINITION:
            break; // No children (just strings)
        case NODE_ERROR_SET_MERGE:
            if (node->as.error_set_merge) {
                visitor.visitChild(&node->as.error_set_merge->left);
                visitor.visitChild(&node->as.error_set_merge->right);
            }
            break;

        // ~~~~~~~~~~~~~~~~~~~~~~ Statements ~~~~~~~~~~~~~~~~~~~~~~~
        case NODE_IMPORT_STMT:
            break; // No children

        // ~~~~~~~~~~~~~~~~~~~ Type Expressions ~~~~~~~~~~~~~~~~~~~~
        case NODE_TYPE_NAME:
            break; // No children
        case NODE_POINTER_TYPE:
            visitor.visitChild(&node->as.pointer_type.base);
            break;
        case NODE_ARRAY_TYPE:
            visitor.visitChild(&node->as.array_type.element_type);
            visitor.visitChild(&node->as.array_type.size);
            break;
        case NODE_ERROR_UNION_TYPE:
            if (node->as.error_union_type) {
                visitor.visitChild(&node->as.error_union_type->error_set);
                visitor.visitChild(&node->as.error_union_type->payload_type);
            }
            break;
        case NODE_OPTIONAL_TYPE:
            if (node->as.optional_type) {
                visitor.visitChild(&node->as.optional_type->payload_type);
            }
            break;
        case NODE_FUNCTION_TYPE:
            if (node->as.function_type) {
                if (node->as.function_type->params) {
                    for (size_t i = 0; i < node->as.function_type->params->length(); ++i) {
                        visitor.visitChild(&(*node->as.function_type->params)[i]);
                    }
                }
                visitor.visitChild(&node->as.function_type->return_type);
            }
            break;

        // ~~~~~~~~~~~~~~~~ Error Handling ~~~~~~~~~~~~~~~~~
        case NODE_TRY_EXPR:
            visitor.visitChild(&node->as.try_expr.expression);
            break;
        case NODE_CATCH_EXPR:
            if (node->as.catch_expr) {
                visitor.visitChild(&node->as.catch_expr->payload);
                visitor.visitChild(&node->as.catch_expr->else_expr);
            }
            break;
        case NODE_ORELSE_EXPR:
            if (node->as.orelse_expr) {
                visitor.visitChild(&node->as.orelse_expr->payload);
                visitor.visitChild(&node->as.orelse_expr->else_expr);
            }
            break;
        case NODE_ERRDEFER_STMT:
            visitor.visitChild(&node->as.errdefer_stmt.statement);
            break;

        // ~~~~~~~~~~~~~~~~ Async Operations ~~~~~~~~~~~~~~~~~
        case NODE_ASYNC_EXPR:
            visitor.visitChild(&node->as.async_expr.expression);
            break;
        case NODE_AWAIT_EXPR:
            visitor.visitChild(&node->as.await_expr.expression);
            break;

        // ~~~~~~~~~~~~~~~~ Compile-Time Operations ~~~~~~~~~~~~~~~~~
        case NODE_COMPTIME_BLOCK:
            visitor.visitChild(&node->as.comptime_block.expression);
            break;
    }
}

namespace {
    struct CloningVisitor : ChildVisitor {
        ArenaAllocator* arena;

        CloningVisitor(ArenaAllocator* arena) : arena(arena) {}

        void visitChild(ASTNode** child_slot) {
            if (*child_slot) {
                *child_slot = cloneASTNode(*child_slot, arena);
            }
        }
    };
}

ASTNode* cloneASTNode(ASTNode* node, ArenaAllocator* arena) {
    if (!node) return NULL;

    // 1. Shallow copy the node structure
    ASTNode* copy = (ASTNode*)arena->alloc(sizeof(ASTNode));
    plat_memcpy(copy, node, sizeof(ASTNode));

    // 2. Handle DynamicArray deep-cloning
    // We must manually clone any DynamicArray pointers before forEachChild
    // because forEachChild will visit elements but not the array itself.
    switch (node->type) {
        case NODE_FUNCTION_CALL:
            if (node->as.function_call && node->as.function_call->args) {
                ASTFunctionCallNode* call_copy = (ASTFunctionCallNode*)arena->alloc(sizeof(ASTFunctionCallNode));
                plat_memcpy(call_copy, node->as.function_call, sizeof(ASTFunctionCallNode));
                copy->as.function_call = call_copy;

                void* array_mem = arena->alloc(sizeof(DynamicArray<ASTNode*>));
                call_copy->args = new (array_mem) DynamicArray<ASTNode*>(*arena);
                call_copy->args->ensure_capacity(node->as.function_call->args->length());
                for (size_t i = 0; i < node->as.function_call->args->length(); ++i) {
                    call_copy->args->append((*node->as.function_call->args)[i]);
                }
            }
            break;

        case NODE_BLOCK_STMT:
            if (node->as.block_stmt.statements) {
                void* array_mem = arena->alloc(sizeof(DynamicArray<ASTNode*>));
                copy->as.block_stmt.statements = new (array_mem) DynamicArray<ASTNode*>(*arena);
                copy->as.block_stmt.statements->ensure_capacity(node->as.block_stmt.statements->length());
                for (size_t i = 0; i < node->as.block_stmt.statements->length(); ++i) {
                    copy->as.block_stmt.statements->append((*node->as.block_stmt.statements)[i]);
                }
            }
            break;

        case NODE_STRUCT_INITIALIZER:
            if (node->as.struct_initializer && node->as.struct_initializer->fields) {
                ASTStructInitializerNode* init_copy = (ASTStructInitializerNode*)arena->alloc(sizeof(ASTStructInitializerNode));
                plat_memcpy(init_copy, node->as.struct_initializer, sizeof(ASTStructInitializerNode));
                copy->as.struct_initializer = init_copy;

                void* array_mem = arena->alloc(sizeof(DynamicArray<ASTNamedInitializer*>));
                init_copy->fields = new (array_mem) DynamicArray<ASTNamedInitializer*>(*arena);
                init_copy->fields->ensure_capacity(node->as.struct_initializer->fields->length());

                for (size_t i = 0; i < node->as.struct_initializer->fields->length(); ++i) {
                    ASTNamedInitializer* field_orig = (*node->as.struct_initializer->fields)[i];
                    ASTNamedInitializer* field_copy = (ASTNamedInitializer*)arena->alloc(sizeof(ASTNamedInitializer));
                    plat_memcpy(field_copy, field_orig, sizeof(ASTNamedInitializer));
                    // Value will be cloned via forEachChild
                    init_copy->fields->append(field_copy);
                }
            }
            break;

        case NODE_TUPLE_LITERAL:
            if (node->as.tuple_literal && node->as.tuple_literal->elements) {
                ASTTupleLiteralNode* tuple_copy = (ASTTupleLiteralNode*)arena->alloc(sizeof(ASTTupleLiteralNode));
                plat_memcpy(tuple_copy, node->as.tuple_literal, sizeof(ASTTupleLiteralNode));
                copy->as.tuple_literal = tuple_copy;

                void* array_mem = arena->alloc(sizeof(DynamicArray<ASTNode*>));
                tuple_copy->elements = new (array_mem) DynamicArray<ASTNode*>(*arena);
                tuple_copy->elements->ensure_capacity(node->as.tuple_literal->elements->length());
                for (size_t i = 0; i < node->as.tuple_literal->elements->length(); ++i) {
                    tuple_copy->elements->append((*node->as.tuple_literal->elements)[i]);
                }
            }
            break;

        case NODE_SWITCH_EXPR:
            if (node->as.switch_expr) {
                ASTSwitchExprNode* sw_copy = (ASTSwitchExprNode*)arena->alloc(sizeof(ASTSwitchExprNode));
                plat_memcpy(sw_copy, node->as.switch_expr, sizeof(ASTSwitchExprNode));
                copy->as.switch_expr = sw_copy;

                if (node->as.switch_expr->prongs) {
                    void* array_mem = arena->alloc(sizeof(DynamicArray<ASTSwitchProngNode*>));
                    sw_copy->prongs = new (array_mem) DynamicArray<ASTSwitchProngNode*>(*arena);
                    sw_copy->prongs->ensure_capacity(node->as.switch_expr->prongs->length());

                    for (size_t i = 0; i < node->as.switch_expr->prongs->length(); ++i) {
                        ASTSwitchProngNode* prong_orig = (*node->as.switch_expr->prongs)[i];
                        ASTSwitchProngNode* prong_copy = (ASTSwitchProngNode*)arena->alloc(sizeof(ASTSwitchProngNode));
                        plat_memcpy(prong_copy, prong_orig, sizeof(ASTSwitchProngNode));

                        if (prong_orig->items) {
                            void* items_mem = arena->alloc(sizeof(DynamicArray<ASTNode*>));
                            prong_copy->items = new (items_mem) DynamicArray<ASTNode*>(*arena);
                            prong_copy->items->ensure_capacity(prong_orig->items->length());
                            for (size_t j = 0; j < prong_orig->items->length(); ++j) {
                                prong_copy->items->append((*prong_orig->items)[j]);
                            }
                        }
                        sw_copy->prongs->append(prong_copy);
                    }
                }
            }
            break;

        case NODE_SWITCH_STMT:
            if (node->as.switch_stmt) {
                ASTSwitchStmtNode* sw_copy = (ASTSwitchStmtNode*)arena->alloc(sizeof(ASTSwitchStmtNode));
                plat_memcpy(sw_copy, node->as.switch_stmt, sizeof(ASTSwitchStmtNode));
                copy->as.switch_stmt = sw_copy;

                if (node->as.switch_stmt->prongs) {
                    void* array_mem = arena->alloc(sizeof(DynamicArray<ASTSwitchStmtProngNode*>));
                    sw_copy->prongs = new (array_mem) DynamicArray<ASTSwitchStmtProngNode*>(*arena);
                    sw_copy->prongs->ensure_capacity(node->as.switch_stmt->prongs->length());

                    for (size_t i = 0; i < node->as.switch_stmt->prongs->length(); ++i) {
                        ASTSwitchStmtProngNode* prong_orig = (*node->as.switch_stmt->prongs)[i];
                        ASTSwitchStmtProngNode* prong_copy = (ASTSwitchStmtProngNode*)arena->alloc(sizeof(ASTSwitchStmtProngNode));
                        plat_memcpy(prong_copy, prong_orig, sizeof(ASTSwitchStmtProngNode));

                        if (prong_orig->items) {
                            void* items_mem = arena->alloc(sizeof(DynamicArray<ASTNode*>));
                            prong_copy->items = new (items_mem) DynamicArray<ASTNode*>(*arena);
                            prong_copy->items->ensure_capacity(prong_orig->items->length());
                            for (size_t j = 0; j < prong_orig->items->length(); ++j) {
                                prong_copy->items->append((*prong_orig->items)[j]);
                            }
                        }
                        sw_copy->prongs->append(prong_copy);
                    }
                }
            }
            break;

        case NODE_FN_DECL:
            if (node->as.fn_decl) {
                ASTFnDeclNode* fn_copy = (ASTFnDeclNode*)arena->alloc(sizeof(ASTFnDeclNode));
                plat_memcpy(fn_copy, node->as.fn_decl, sizeof(ASTFnDeclNode));
                copy->as.fn_decl = fn_copy;

                if (node->as.fn_decl->params) {
                    void* array_mem = arena->alloc(sizeof(DynamicArray<ASTNode*>));
                    fn_copy->params = new (array_mem) DynamicArray<ASTNode*>(*arena);
                    fn_copy->params->ensure_capacity(node->as.fn_decl->params->length());
                    for (size_t i = 0; i < node->as.fn_decl->params->length(); ++i) {
                        fn_copy->params->append((*node->as.fn_decl->params)[i]);
                    }
                }
            }
            break;

        case NODE_STRUCT_DECL:
            if (node->as.struct_decl && node->as.struct_decl->fields) {
                ASTStructDeclNode* struct_copy = (ASTStructDeclNode*)arena->alloc(sizeof(ASTStructDeclNode));
                plat_memcpy(struct_copy, node->as.struct_decl, sizeof(ASTStructDeclNode));
                copy->as.struct_decl = struct_copy;

                void* array_mem = arena->alloc(sizeof(DynamicArray<ASTNode*>));
                struct_copy->fields = new (array_mem) DynamicArray<ASTNode*>(*arena);
                struct_copy->fields->ensure_capacity(node->as.struct_decl->fields->length());
                for (size_t i = 0; i < node->as.struct_decl->fields->length(); ++i) {
                    struct_copy->fields->append((*node->as.struct_decl->fields)[i]);
                }
            }
            break;

        case NODE_UNION_DECL:
            if (node->as.union_decl && node->as.union_decl->fields) {
                ASTUnionDeclNode* union_copy = (ASTUnionDeclNode*)arena->alloc(sizeof(ASTUnionDeclNode));
                plat_memcpy(union_copy, node->as.union_decl, sizeof(ASTUnionDeclNode));
                copy->as.union_decl = union_copy;

                void* array_mem = arena->alloc(sizeof(DynamicArray<ASTNode*>));
                union_copy->fields = new (array_mem) DynamicArray<ASTNode*>(*arena);
                union_copy->fields->ensure_capacity(node->as.union_decl->fields->length());
                for (size_t i = 0; i < node->as.union_decl->fields->length(); ++i) {
                    union_copy->fields->append((*node->as.union_decl->fields)[i]);
                }
            }
            break;

        case NODE_ENUM_DECL:
            if (node->as.enum_decl && node->as.enum_decl->fields) {
                ASTEnumDeclNode* enum_copy = (ASTEnumDeclNode*)arena->alloc(sizeof(ASTEnumDeclNode));
                plat_memcpy(enum_copy, node->as.enum_decl, sizeof(ASTEnumDeclNode));
                copy->as.enum_decl = enum_copy;

                void* array_mem = arena->alloc(sizeof(DynamicArray<ASTNode*>));
                enum_copy->fields = new (array_mem) DynamicArray<ASTNode*>(*arena);
                enum_copy->fields->ensure_capacity(node->as.enum_decl->fields->length());
                for (size_t i = 0; i < node->as.enum_decl->fields->length(); ++i) {
                    enum_copy->fields->append((*node->as.enum_decl->fields)[i]);
                }
            }
            break;

        case NODE_ERROR_SET_DEFINITION:
            if (node->as.error_set_decl && node->as.error_set_decl->tags) {
                ASTErrorSetDefinitionNode* err_copy = (ASTErrorSetDefinitionNode*)arena->alloc(sizeof(ASTErrorSetDefinitionNode));
                plat_memcpy(err_copy, node->as.error_set_decl, sizeof(ASTErrorSetDefinitionNode));
                copy->as.error_set_decl = err_copy;

                void* array_mem = arena->alloc(sizeof(DynamicArray<const char*>));
                err_copy->tags = new (array_mem) DynamicArray<const char*>(*arena);
                err_copy->tags->ensure_capacity(node->as.error_set_decl->tags->length());
                for (size_t i = 0; i < node->as.error_set_decl->tags->length(); ++i) {
                    err_copy->tags->append((*node->as.error_set_decl->tags)[i]);
                }
            }
            break;

        case NODE_FUNCTION_TYPE:
            if (node->as.function_type && node->as.function_type->params) {
                ASTFunctionTypeNode* type_copy = (ASTFunctionTypeNode*)arena->alloc(sizeof(ASTFunctionTypeNode));
                plat_memcpy(type_copy, node->as.function_type, sizeof(ASTFunctionTypeNode));
                copy->as.function_type = type_copy;

                void* array_mem = arena->alloc(sizeof(DynamicArray<ASTNode*>));
                type_copy->params = new (array_mem) DynamicArray<ASTNode*>(*arena);
                type_copy->params->ensure_capacity(node->as.function_type->params->length());
                for (size_t i = 0; i < node->as.function_type->params->length(); ++i) {
                    type_copy->params->append((*node->as.function_type->params)[i]);
                }
            }
            break;

        default:
            // For other out-of-line nodes that don't have DynamicArrays,
            // we still need to clone the out-of-line structure if forEachChild
            // doesn't handle them by value.
            switch (node->type) {
                case NODE_ASSIGNMENT:
                    if (node->as.assignment) {
                        copy->as.assignment = (ASTAssignmentNode*)arena->alloc(sizeof(ASTAssignmentNode));
                        plat_memcpy(copy->as.assignment, node->as.assignment, sizeof(ASTAssignmentNode));
                    }
                    break;
                case NODE_COMPOUND_ASSIGNMENT:
                    if (node->as.compound_assignment) {
                        copy->as.compound_assignment = (ASTCompoundAssignmentNode*)arena->alloc(sizeof(ASTCompoundAssignmentNode));
                        plat_memcpy(copy->as.compound_assignment, node->as.compound_assignment, sizeof(ASTCompoundAssignmentNode));
                    }
                    break;
                case NODE_BINARY_OP:
                    if (node->as.binary_op) {
                        copy->as.binary_op = (ASTBinaryOpNode*)arena->alloc(sizeof(ASTBinaryOpNode));
                        plat_memcpy(copy->as.binary_op, node->as.binary_op, sizeof(ASTBinaryOpNode));
                    }
                    break;
                case NODE_ARRAY_ACCESS:
                    if (node->as.array_access) {
                        copy->as.array_access = (ASTArrayAccessNode*)arena->alloc(sizeof(ASTArrayAccessNode));
                        plat_memcpy(copy->as.array_access, node->as.array_access, sizeof(ASTArrayAccessNode));
                    }
                    break;
                case NODE_ARRAY_SLICE:
                    if (node->as.array_slice) {
                        copy->as.array_slice = (ASTArraySliceNode*)arena->alloc(sizeof(ASTArraySliceNode));
                        plat_memcpy(copy->as.array_slice, node->as.array_slice, sizeof(ASTArraySliceNode));
                    }
                    break;
                case NODE_MEMBER_ACCESS:
                    if (node->as.member_access) {
                        copy->as.member_access = (ASTMemberAccessNode*)arena->alloc(sizeof(ASTMemberAccessNode));
                        plat_memcpy(copy->as.member_access, node->as.member_access, sizeof(ASTMemberAccessNode));
                    }
                    break;
                case NODE_IF_STMT:
                    if (node->as.if_stmt) {
                        copy->as.if_stmt = (ASTIfStmtNode*)arena->alloc(sizeof(ASTIfStmtNode));
                        plat_memcpy(copy->as.if_stmt, node->as.if_stmt, sizeof(ASTIfStmtNode));
                    }
                    break;
                case NODE_IF_EXPR:
                    if (node->as.if_expr) {
                        copy->as.if_expr = (ASTIfExprNode*)arena->alloc(sizeof(ASTIfExprNode));
                        plat_memcpy(copy->as.if_expr, node->as.if_expr, sizeof(ASTIfExprNode));
                    }
                    break;
                case NODE_WHILE_STMT:
                    if (node->as.while_stmt) {
                        copy->as.while_stmt = (ASTWhileStmtNode*)arena->alloc(sizeof(ASTWhileStmtNode));
                        plat_memcpy(copy->as.while_stmt, node->as.while_stmt, sizeof(ASTWhileStmtNode));
                    }
                    break;
                case NODE_FOR_STMT:
                    if (node->as.for_stmt) {
                        copy->as.for_stmt = (ASTForStmtNode*)arena->alloc(sizeof(ASTForStmtNode));
                        plat_memcpy(copy->as.for_stmt, node->as.for_stmt, sizeof(ASTForStmtNode));
                    }
                    break;
                case NODE_PTR_CAST:
                    if (node->as.ptr_cast) {
                        copy->as.ptr_cast = (ASTPtrCastNode*)arena->alloc(sizeof(ASTPtrCastNode));
                        plat_memcpy(copy->as.ptr_cast, node->as.ptr_cast, sizeof(ASTPtrCastNode));
                    }
                    break;
                case NODE_INT_CAST:
                case NODE_FLOAT_CAST:
                    if (node->as.numeric_cast) {
                        copy->as.numeric_cast = (ASTNumericCastNode*)arena->alloc(sizeof(ASTNumericCastNode));
                        plat_memcpy(copy->as.numeric_cast, node->as.numeric_cast, sizeof(ASTNumericCastNode));
                    }
                    break;
                case NODE_OFFSET_OF:
                    if (node->as.offset_of) {
                        copy->as.offset_of = (ASTOffsetOfNode*)arena->alloc(sizeof(ASTOffsetOfNode));
                        plat_memcpy(copy->as.offset_of, node->as.offset_of, sizeof(ASTOffsetOfNode));
                    }
                    break;
                case NODE_VAR_DECL:
                    if (node->as.var_decl) {
                        copy->as.var_decl = (ASTVarDeclNode*)arena->alloc(sizeof(ASTVarDeclNode));
                        plat_memcpy(copy->as.var_decl, node->as.var_decl, sizeof(ASTVarDeclNode));
                    }
                    break;
                case NODE_STRUCT_FIELD:
                    if (node->as.struct_field) {
                        copy->as.struct_field = (ASTStructFieldNode*)arena->alloc(sizeof(ASTStructFieldNode));
                        plat_memcpy(copy->as.struct_field, node->as.struct_field, sizeof(ASTStructFieldNode));
                    }
                    break;
                case NODE_ERROR_SET_MERGE:
                    if (node->as.error_set_merge) {
                        copy->as.error_set_merge = (ASTErrorSetMergeNode*)arena->alloc(sizeof(ASTErrorSetMergeNode));
                        plat_memcpy(copy->as.error_set_merge, node->as.error_set_merge, sizeof(ASTErrorSetMergeNode));
                    }
                    break;
                case NODE_ERROR_UNION_TYPE:
                    if (node->as.error_union_type) {
                        copy->as.error_union_type = (ASTErrorUnionTypeNode*)arena->alloc(sizeof(ASTErrorUnionTypeNode));
                        plat_memcpy(copy->as.error_union_type, node->as.error_union_type, sizeof(ASTErrorUnionTypeNode));
                    }
                    break;
                case NODE_OPTIONAL_TYPE:
                    if (node->as.optional_type) {
                        copy->as.optional_type = (ASTOptionalTypeNode*)arena->alloc(sizeof(ASTOptionalTypeNode));
                        plat_memcpy(copy->as.optional_type, node->as.optional_type, sizeof(ASTOptionalTypeNode));
                    }
                    break;
                case NODE_CATCH_EXPR:
                    if (node->as.catch_expr) {
                        copy->as.catch_expr = (ASTCatchExprNode*)arena->alloc(sizeof(ASTCatchExprNode));
                        plat_memcpy(copy->as.catch_expr, node->as.catch_expr, sizeof(ASTCatchExprNode));
                    }
                    break;
                case NODE_ORELSE_EXPR:
                    if (node->as.orelse_expr) {
                        copy->as.orelse_expr = (ASTOrelseExprNode*)arena->alloc(sizeof(ASTOrelseExprNode));
                        plat_memcpy(copy->as.orelse_expr, node->as.orelse_expr, sizeof(ASTOrelseExprNode));
                    }
                    break;
                case NODE_IMPORT_STMT:
                    if (node->as.import_stmt) {
                        copy->as.import_stmt = (ASTImportStmtNode*)arena->alloc(sizeof(ASTImportStmtNode));
                        plat_memcpy(copy->as.import_stmt, node->as.import_stmt, sizeof(ASTImportStmtNode));
                    }
                    break;
                default:
                    break;
            }
            break;
    }

    // 3. Recursively clone all children
    CloningVisitor visitor(arena);
    forEachChild(copy, visitor);

    return copy;
}

const char* getTokenSpelling(TokenType op) {
    switch (op) {
        case TOKEN_PLUS: return "+";
        case TOKEN_MINUS: return "-";
        case TOKEN_STAR: return "*";
        case TOKEN_SLASH: return "/";
        case TOKEN_PERCENT: return "%";
        case TOKEN_EQUAL_EQUAL: return "==";
        case TOKEN_BANG_EQUAL: return "!=";
        case TOKEN_LESS: return "<";
        case TOKEN_LESS_EQUAL: return "<=";
        case TOKEN_GREATER: return ">";
        case TOKEN_GREATER_EQUAL: return ">=";
        case TOKEN_AMPERSAND: return "&";
        case TOKEN_PIPE: return "|";
        case TOKEN_CARET: return "^";
        case TOKEN_LARROW2: return "<<";
        case TOKEN_RARROW2: return ">>";
        case TOKEN_BANG: return "!";
        case TOKEN_TILDE: return "~";
        case TOKEN_AND: return "&&";
        case TOKEN_OR: return "||";
        case TOKEN_DOT_ASTERISK: return "*";
        case TOKEN_PLUS_EQUAL: return "+=";
        case TOKEN_MINUS_EQUAL: return "-=";
        case TOKEN_STAR_EQUAL: return "*=";
        case TOKEN_SLASH_EQUAL: return "/=";
        case TOKEN_PERCENT_EQUAL: return "%=";
        case TOKEN_AMPERSAND_EQUAL: return "&=";
        case TOKEN_PIPE_EQUAL: return "|=";
        case TOKEN_CARET_EQUAL: return "^=";
        case TOKEN_LARROW2_EQUAL: return "<<=";
        case TOKEN_RARROW2_EQUAL: return ">>=";
        case TOKEN_PLUSPERCENT: return "+";
        case TOKEN_MINUSPERCENT: return "-";
        case TOKEN_STARPERCENT: return "*";
        default: return "unknown";
    }
}

bool allPathsExit(const ASTNode* node) {
    if (!node) return false;
    switch (node->type) {
        case NODE_RETURN_STMT:
        case NODE_BREAK_STMT:
        case NODE_CONTINUE_STMT:
        case NODE_UNREACHABLE:
            return true;
        case NODE_BLOCK_STMT: {
            const ASTBlockStmtNode& block = node->as.block_stmt;
            if (!block.statements) return false;
            for (size_t i = 0; i < block.statements->length(); ++i) {
                if (allPathsExit((*block.statements)[i])) return true;
            }
            return false;
        }
        case NODE_IF_STMT: {
            const ASTIfStmtNode* if_stmt = node->as.if_stmt;
            if (!if_stmt->else_block) return false;
            return allPathsExit(if_stmt->then_block) && allPathsExit(if_stmt->else_block);
        }
        case NODE_IF_EXPR: {
            const ASTIfExprNode* if_expr = node->as.if_expr;
            if (!if_expr->else_expr) return false;
            return allPathsExit(if_expr->then_expr) && allPathsExit(if_expr->else_expr);
        }
        case NODE_SWITCH_EXPR: {
            const ASTSwitchExprNode* sw = node->as.switch_expr;
            if (!sw->prongs || sw->prongs->length() == 0) return false;
            bool has_else = false;
            for (size_t i = 0; i < sw->prongs->length(); ++i) {
                if ((*sw->prongs)[i]->is_else) has_else = true;
                if (!allPathsExit((*sw->prongs)[i]->body)) return false;
            }
            return has_else; /* Exhaustive switch with all paths exiting */
        }
        case NODE_SWITCH_STMT: {
            const ASTSwitchStmtNode* sw = node->as.switch_stmt;
            if (!sw->prongs || sw->prongs->length() == 0) return false;
            bool has_else = false;
            for (size_t i = 0; i < sw->prongs->length(); ++i) {
                if ((*sw->prongs)[i]->is_else) has_else = true;
                if (!allPathsExit((*sw->prongs)[i]->body)) return false;
            }
            return has_else;
        }
        case NODE_TRY_EXPR:
            /* try expression exits only on error path, but it doesn't always exit.
               However, if used as a statement 'try ...', it might be considered divergent?
               No, it only returns on error. */
            return false;
        case NODE_CATCH_EXPR:
            return allPathsExit(node->as.catch_expr->payload) && allPathsExit(node->as.catch_expr->else_expr);
        case NODE_ORELSE_EXPR:
            return allPathsExit(node->as.orelse_expr->payload) && allPathsExit(node->as.orelse_expr->else_expr);
        case NODE_EXPRESSION_STMT:
            return allPathsExit(node->as.expression_stmt.expression);
        case NODE_PAREN_EXPR:
            return allPathsExit(node->as.paren_expr.expr);
        default:
            return false;
    }
}
