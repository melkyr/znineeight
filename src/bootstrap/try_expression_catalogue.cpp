#include "try_expression_catalogue.hpp"
#include "utils.hpp"
#include "platform.hpp"
#include <new>

TryExpressionCatalogue::TryExpressionCatalogue(ArenaAllocator& arena)
    : arena_(arena) {
    try_expressions_ = (DynamicArray<TryExpressionInfo>*)arena.alloc(sizeof(DynamicArray<TryExpressionInfo>));
    if (!try_expressions_) plat_abort();
    new (try_expressions_) DynamicArray<TryExpressionInfo>(arena);
}

int TryExpressionCatalogue::addTryExpression(SourceLocation loc, const char* context_type,
                                             Type* inner_type, Type* result_type, int depth) {
    TryExpressionInfo info;
    info.location = loc;
    info.context_type = arena_.allocString(context_type);
    info.inner_type = inner_type;
    info.result_type = result_type;
    info.is_nested = (depth > 0);
    info.depth = depth;
    info.extraction_strategy = EXTRACTION_STACK; // Default
    info.stack_safe = true; // Default

    try_expressions_->append(info);
    return (int)(try_expressions_->length() - 1);
}

int TryExpressionCatalogue::count() const {
    return (int)try_expressions_->length();
}

void TryExpressionCatalogue::printSummary() const {
    plat_print_info("--- Try Expression Catalogue Summary ---\n");
    for (size_t i = 0; i < try_expressions_->length(); ++i) {
        const TryExpressionInfo& info = (*try_expressions_)[i];
        char line[16], col[16], depth[16], strategy[16];
        plat_u64_to_string(info.location.line, line, sizeof(line));
        plat_u64_to_string(info.location.column, col, sizeof(col));
        plat_u64_to_string(info.depth, depth, sizeof(depth));

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
        safe_append(current, remaining, info.is_nested ? " nested=yes" : " nested=no");

        plat_u64_to_string((size_t)info.extraction_strategy, strategy, sizeof(strategy));
        safe_append(current, remaining, " strategy=");
        safe_append(current, remaining, strategy);
        safe_append(current, remaining, info.stack_safe ? " safe=yes\n" : " safe=no\n");

        plat_print_info(buffer);
        plat_print_debug(buffer);
    }
    char total[16];
    plat_u64_to_string(count(), total, sizeof(total));
    char final_msg[64];
    char* cur = final_msg;
    size_t rem = sizeof(final_msg);
    safe_append(cur, rem, "Total: ");
    safe_append(cur, rem, total);
    safe_append(cur, rem, "\n");
    plat_print_info(final_msg);
    plat_print_debug(final_msg);
}
