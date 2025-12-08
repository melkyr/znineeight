#ifndef SOURCE_MANAGER_HPP
#define SOURCE_MANAGER_HPP

#include "common.hpp"
#include "memory.hpp"

struct SourceLocation {
    u32 file_id;
    u32 line;
    u32 column;
};

struct SourceFile {
    const char* filename;
    const char* content;
    size_t size;
};

class SourceManager {
    ArenaAllocator& allocator;
    DynamicArray<SourceFile> files;

public:
    SourceManager(ArenaAllocator& alloc) : allocator(alloc), files(alloc) {}
    u32 addFile(const char* filename, const char* content, size_t size);
    SourceLocation getLocation(u32 file_id, size_t offset);
};

#endif // SOURCE_MANAGER_HPP
