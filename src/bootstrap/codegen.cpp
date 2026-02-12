#include "codegen.hpp"
#include "platform.hpp"

C89Emitter::C89Emitter(ArenaAllocator& arena)
    : buffer_pos_(0), output_file_(PLAT_INVALID_FILE), indent_level_(0), owns_file_(false), var_alloc_(arena) {
}

C89Emitter::C89Emitter(ArenaAllocator& arena, const char* path)
    : buffer_pos_(0), indent_level_(0), owns_file_(true), var_alloc_(arena) {
    output_file_ = plat_open_file(path, true);
}

C89Emitter::C89Emitter(ArenaAllocator& arena, PlatFile file)
    : buffer_pos_(0), output_file_(file), indent_level_(0), owns_file_(false), var_alloc_(arena) {
}

C89Emitter::~C89Emitter() {
    close();
}

void C89Emitter::indent() {
    indent_level_++;
}

void C89Emitter::dedent() {
    if (indent_level_ > 0) {
        indent_level_--;
    }
}

void C89Emitter::writeIndent() {
    for (int i = 0; i < indent_level_; ++i) {
        write("    ", 4);
    }
}

void C89Emitter::beginFunction() {
    var_alloc_.reset();
}

void C89Emitter::write(const char* data, size_t len) {
    if (output_file_ == PLAT_INVALID_FILE) return;

    if (buffer_pos_ + len > sizeof(buffer_)) {
        flush();
        // If the data is larger than the buffer itself, write it directly
        if (len > sizeof(buffer_)) {
            plat_write_file(output_file_, data, len);
            return;
        }
    }

    plat_memcpy(buffer_ + buffer_pos_, data, len);
    buffer_pos_ += len;
}

void C89Emitter::writeString(const char* str) {
    if (!str) return;
    write(str, plat_strlen(str));
}

void C89Emitter::emitComment(const char* text) {
    if (!text) return;
    writeIndent();
    write("/* ", 3);
    writeString(text);
    write(" */\n", 4);
}

void C89Emitter::flush() {
    if (output_file_ != PLAT_INVALID_FILE && buffer_pos_ > 0) {
        plat_write_file(output_file_, buffer_, buffer_pos_);
        buffer_pos_ = 0;
    }
}

bool C89Emitter::open(const char* path) {
    close();
    output_file_ = plat_open_file(path, true);
    owns_file_ = true;
    return isValid();
}

void C89Emitter::close() {
    flush();
    if (owns_file_ && output_file_ != PLAT_INVALID_FILE) {
        plat_close_file(output_file_);
        output_file_ = PLAT_INVALID_FILE;
    }
}
