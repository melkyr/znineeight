#include "source_manager.hpp"

u32 SourceManager::addFile(const char* filename, const char* content, size_t size) {
    SourceFile file = { filename, content, size };
    files.append(file);
    return files.length() - 1;
}

SourceLocation SourceManager::getLocation(u32 file_id, size_t offset) {
    const SourceFile* file = getFile(file_id);
    if (!file || offset > file->size) {
        // Return a default/invalid location if the file_id or offset is bad
        return SourceLocation{file_id, 0, 0};
    }

    u32 line = 1;
    const char* line_start = file->content;
    for (size_t i = 0; i < offset; ++i) {
        if (file->content[i] == '\n') {
            line++;
            line_start = &file->content[i + 1];
        }
    }

    u32 column = (u32)(&file->content[offset] - line_start) + 1;
    return SourceLocation{file_id, line, column};
}

const SourceFile* SourceManager::getFile(u32 file_id) const {
    if (file_id >= files.length()) {
        return NULL;
    }
    return &files[file_id];
}
