#ifndef TEXT_WRITER_HPP
#define TEXT_WRITER_HPP

#include "platform.hpp"

/**
 * @class TextWriter
 * @brief Base class for writing text with configurable line endings.
 */
class TextWriter {
public:
    TextWriter(const char* line_ending = "\n") : line_ending_(line_ending) {}
    virtual ~TextWriter() {}

    virtual void writeString(const char* str) = 0;

    void writeLine() {
        writeString(line_ending_);
    }

    void writeLine(const char* str) {
        writeString(str);
        writeString(line_ending_);
    }

    const char* getLineEnding() const { return line_ending_; }

protected:
    const char* line_ending_;
};

/**
 * @class FileTextWriter
 * @brief Implementation of TextWriter that writes to a PlatFile.
 */
class FileTextWriter : public TextWriter {
public:
    FileTextWriter(PlatFile file, const char* line_ending = "\n")
        : TextWriter(line_ending), file_(file) {}

    virtual void writeString(const char* str) {
        if (file_ != PLAT_INVALID_FILE && str) {
            plat_write_file(file_, str, plat_strlen(str));
        }
    }

private:
    PlatFile file_;
};

#endif // TEXT_WRITER_HPP
