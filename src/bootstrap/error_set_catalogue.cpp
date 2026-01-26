#include "error_set_catalogue.hpp"
#include "utils.hpp"
#include <new>

#ifdef _WIN32
#include <windows.h>
#endif

ErrorSetCatalogue::ErrorSetCatalogue(ArenaAllocator& arena)
    : arena_(arena) {
    void* mem = arena_.alloc(sizeof(DynamicArray<ErrorSetInfo>));
    error_sets_ = new (mem) DynamicArray<ErrorSetInfo>(arena_);
}

void ErrorSetCatalogue::addErrorSet(const char* name, DynamicArray<const char*>* tags, SourceLocation loc, bool is_imported) {
    ErrorSetInfo info;
    info.name = name;
    info.tags = tags;
    info.location = loc;
    info.is_imported = is_imported;
    error_sets_->append(info);
}

void ErrorSetCatalogue::updateLastSetName(const char* name) {
    if (error_sets_->length() > 0) {
        ErrorSetInfo& last = (*error_sets_)[error_sets_->length() - 1];
        if (last.name == NULL) {
            last.name = name;
        }
    }
}

int ErrorSetCatalogue::count() const {
    return (int)error_sets_->length();
}

void ErrorSetCatalogue::printSummary() const {
#ifdef _WIN32
    OutputDebugStringA("--- Error Set Catalogue Summary ---\n");
    for (size_t i = 0; i < error_sets_->length(); ++i) {
        const ErrorSetInfo& info = (*error_sets_)[i];
        char buffer[512];
        char* ptr = buffer;
        size_t remaining = sizeof(buffer);

        safe_append(ptr, remaining, "Error Set: ");
        safe_append(ptr, remaining, info.name ? info.name : "<anonymous>");
        if (info.is_imported) {
            safe_append(ptr, remaining, " (imported)");
        }
        safe_append(ptr, remaining, " at ");

        char line_buf[16];
        simple_itoa((long)info.location.line, line_buf, sizeof(line_buf));
        safe_append(ptr, remaining, line_buf);
        safe_append(ptr, remaining, ":");

        char col_buf[16];
        simple_itoa((long)info.location.column, col_buf, sizeof(col_buf));
        safe_append(ptr, remaining, col_buf);

        safe_append(ptr, remaining, "\n");
        OutputDebugStringA(buffer);

        if (info.tags) {
            for (size_t j = 0; j < info.tags->length(); ++j) {
                ptr = buffer;
                remaining = sizeof(buffer);
                safe_append(ptr, remaining, "  - ");
                safe_append(ptr, remaining, (*info.tags)[j]);
                safe_append(ptr, remaining, "\n");
                OutputDebugStringA(buffer);
            }
        }
    }
    OutputDebugStringA("-----------------------------------\n");
#endif
}
