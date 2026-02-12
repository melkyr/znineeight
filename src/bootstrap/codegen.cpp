#include "codegen.hpp"
#include "platform.hpp"
#include "utils.hpp"
#include <cstdio>

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

void C89Emitter::emitExpression(const ASTNode* node) {
    if (!node) return;
    switch (node->type) {
        case NODE_INTEGER_LITERAL:
            emitIntegerLiteral(&node->as.integer_literal);
            break;
        case NODE_FLOAT_LITERAL:
            emitFloatLiteral(&node->as.float_literal);
            break;
        case NODE_PAREN_EXPR:
            writeString("(");
            emitExpression(node->as.paren_expr.expr);
            writeString(")");
            break;
        default:
            writeString("/* [Unimplemented Expression] */");
            break;
    }
}

void C89Emitter::emitIntegerLiteral(const ASTIntegerLiteralNode* node) {
    char buf[32];
    u64_to_decimal(node->value, buf, sizeof(buf));
    writeString(buf);

    if (node->resolved_type) {
        switch (node->resolved_type->kind) {
            case TYPE_U32:
                writeString("U");
                break;
            case TYPE_I64:
                writeString("i64");
                break;
            case TYPE_U64:
                writeString("ui64");
                break;
            default:
                // i32, u8, i8, u16, i16, usize, isize get no suffix
                break;
        }
    }
}

void C89Emitter::emitFloatLiteral(const ASTFloatLiteralNode* node) {
    char buffer[64];
    sprintf(buffer, "%.15g", node->value);

    // Ensure it's treated as a float by C (add .0 if no '.' or 'e')
    bool has_dot = false;
    bool has_exp = false;
    for (char* p = buffer; *p; ++p) {
        if (*p == '.') has_dot = true;
        if (*p == 'e' || *p == 'E') has_exp = true;
    }

    writeString(buffer);
    if (!has_dot && !has_exp) {
        writeString(".0");
    }

    if (node->resolved_type && node->resolved_type->kind == TYPE_F32) {
        writeString("f");
    }
}
