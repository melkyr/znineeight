#include "../include/source_manager.hpp"

u32 SourceManager::addFile(const char* filename, const char* content, size_t size) {
    SourceFile file = { filename, content, size };
    files.append(file);
    return files.length() - 1;
}

SourceLocation SourceManager::getLocation(u32 file_id, size_t offset) {
    if (file_id >= files.length()) {
        // Return a sentinel value for an invalid file_id
        return { file_id, 0, 0 };
    }

    const SourceFile& file = files[file_id];
    if (offset > file.size) {
        // Clamp offset to the end of the file
        offset = file.size;
    }

    u32 line = 1;
    u32 line_start = 0;
    for (size_t i = 0; i < offset; ++i) {
        if (file.content[i] == '\n') {
            line++;
            line_start = i + 1;
        }
    }

    u32 column = offset - line_start + 1;
    return { file_id, line, column };
}
