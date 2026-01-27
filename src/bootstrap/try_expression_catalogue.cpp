#include "try_expression_catalogue.hpp"
#include "utils.hpp"
#include <new>

#ifndef _WIN32
#include <cstdio>
#endif

TryExpressionCatalogue::TryExpressionCatalogue(ArenaAllocator& arena)
    : arena_(arena) {
    try_expressions_ = (DynamicArray<TryExpressionInfo>*)arena.alloc(sizeof(DynamicArray<TryExpressionInfo>));
    new (try_expressions_) DynamicArray<TryExpressionInfo>(arena);
}

void TryExpressionCatalogue::addTryExpression(SourceLocation loc, const char* context_type,
                                             Type* inner_type, Type* result_type, int depth) {
    TryExpressionInfo info;
    info.location = loc;
    info.context_type = arena_.allocString(context_type);
    info.inner_type = inner_type;
    info.result_type = result_type;
    info.is_nested = (depth > 0);
    info.depth = depth;

    try_expressions_->append(info);
}

int TryExpressionCatalogue::count() const {
    return (int)try_expressions_->length();
}

void TryExpressionCatalogue::printSummary() const {
#ifdef _WIN32
    OutputDebugStringA("--- Try Expression Catalogue Summary ---\n");
    for (size_t i = 0; i < try_expressions_->length(); ++i) {
        const TryExpressionInfo& info = (*try_expressions_)[i];
        char msg[256];
        char line[16], col[16], depth[16];
        arena_simple_itoa(info.location.line, line, sizeof(line));
        arena_simple_itoa(info.location.column, col, sizeof(col));
        arena_simple_itoa(info.depth, depth, sizeof(depth));

        char buffer[512];
        char* current = buffer;
        size_t remaining = sizeof(buffer);
        safe_append(current, remaining, "Try at ");
        safe_append(current, remaining, line);
        safe_append(current, remaining, ":");
        safe_append(current, remaining, col);
        safe_append(current, remaining, " context=");
        safe_append(current, remaining, info.context_type);
        safe_append(current, remaining, " depth=");
        safe_append(current, remaining, depth);
        safe_append(current, remaining, info.is_nested ? " nested=yes\n" : " nested=no\n");

        OutputDebugStringA(buffer);
    }
    char total[16];
    arena_simple_itoa(count(), total, sizeof(total));
    char final_msg[64];
    char* cur = final_msg;
    size_t rem = sizeof(final_msg);
    safe_append(cur, rem, "Total: ");
    safe_append(cur, rem, total);
    safe_append(cur, rem, "\n");
    OutputDebugStringA(final_msg);
#else
    printf("--- Try Expression Catalogue Summary ---\n");
    for (size_t i = 0; i < try_expressions_->length(); ++i) {
        const TryExpressionInfo& info = (*try_expressions_)[i];
        printf("Try at %u:%u context=%s depth=%d nested=%s\n",
               info.location.line, info.location.column,
               info.context_type, info.depth, info.is_nested ? "yes" : "no");
    }
    printf("Total: %d\n", count());
#endif
}
