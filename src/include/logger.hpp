#ifndef LOGGER_HPP
#define LOGGER_HPP

#include "common.hpp"
#include "platform.hpp"
#include "memory.hpp"
#include <stdarg.h>

enum LogLevel {
    LOG_ERROR,
    LOG_WARNING,
    LOG_INFO,
    LOG_DEBUG
};

class Logger {
public:
    Logger(ArenaAllocator& arena, bool console_enabled, const char* log_file_path);
    ~Logger();

    void log(LogLevel level, const char* msg);
    void logf(LogLevel level, const char* format, ...);
    void flush();

    void setSuppressAll(bool suppress) { suppress_all_ = suppress; }
    void setVerbose(bool verbose) { verbose_ = verbose; }

private:
    ArenaAllocator& arena_;
    char* buffer_;
    size_t buffer_pos_;
    size_t buffer_capacity_;
    bool console_enabled_;
    bool file_enabled_;
    PlatFile log_file_;
    bool suppress_all_;
    bool verbose_;

    void writeToBuffer(const char* s, size_t len);
    void flushBuffer();
};

#endif // LOGGER_HPP
