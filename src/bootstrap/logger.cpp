#include "logger.hpp"

// Low-level bypasses and helpers to be implemented/exposed in platform.cpp/hpp
extern void plat_write_stderr(const char* s);
extern void plat_write_stdout(const char* s);
extern int plat_vsnprintf(char* str, size_t size, const char* format, va_list args);

Logger::Logger(ArenaAllocator& arena, bool console_enabled, const char* log_file_path)
    : arena_(arena), buffer_pos_(0), buffer_capacity_(16384),
      console_enabled_(console_enabled), file_enabled_(log_file_path != NULL),
      log_file_(PLAT_INVALID_FILE), suppress_all_(false), verbose_(false)
{
    buffer_ = (char*)arena_.alloc(buffer_capacity_);
    if (!buffer_) {
        buffer_capacity_ = 0;
    }

    if (file_enabled_ && log_file_path) {
        log_file_ = plat_open_file(log_file_path, true);
        if (log_file_ == PLAT_INVALID_FILE) {
            file_enabled_ = false;
            // Use low-level bypass to avoid logger recursion
            plat_write_stderr("Warning: Could not open log file: ");
            plat_write_stderr(log_file_path);
            plat_write_stderr("\n");
        }
    }
}

Logger::~Logger() {
    flush();
    if (log_file_ != PLAT_INVALID_FILE) {
        plat_close_file(log_file_);
    }
}

void Logger::log(LogLevel level, const char* msg) {
    if (!msg) return;

    // Filter by level
    // DEBUG logs only recorded if verbose is on OR file logging is enabled
    if (level == LOG_DEBUG && !verbose_ && !file_enabled_) return;

    // If all logs suppressed, only LOG_ERROR gets through (and bypasses buffering)
    if (suppress_all_ && level != LOG_ERROR) return;

    size_t len = plat_strlen(msg);

    // If it's an error and logs are suppressed, print directly to stderr and don't buffer/file-log
    if (suppress_all_ && level == LOG_ERROR) {
        plat_write_stderr(msg);
        return;
    }

    // Console output logic
    bool show_on_console = console_enabled_;
    if (level == LOG_DEBUG && !verbose_) show_on_console = false;
    if (level == LOG_INFO && suppress_all_) show_on_console = false;

    if (show_on_console) {
        if (level == LOG_ERROR || level == LOG_WARNING) {
            plat_write_stderr(msg);
        } else {
            plat_write_stdout(msg);
        }
    }

    // File output logic (buffered)
    if (file_enabled_) {
        writeToBuffer(msg, len);
    }
}

void Logger::logf(LogLevel level, const char* format, ...) {
    // Early exit if this level won't be logged anywhere
    if (level == LOG_DEBUG && !verbose_ && !file_enabled_) return;
    if (suppress_all_ && level != LOG_ERROR) return;

    char buf[4096];
    va_list args;
    va_start(args, format);
    plat_vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);
    log(level, buf);
}

void Logger::writeToBuffer(const char* s, size_t len) {
    if (!s || len == 0 || buffer_capacity_ == 0) return;

    // Flush if buffer is near full (80%)
    if (buffer_pos_ + len >= (buffer_capacity_ * 8 / 10)) {
        flushBuffer();
    }

    if (len >= buffer_capacity_) {
        // Message too large for buffer, write directly to file
        if (log_file_ != PLAT_INVALID_FILE) {
            if (plat_write_file(log_file_, s, len) != (long)len) {
                plat_print_error("Error: Failed to write large message to log file\n");
            }
        }
        return;
    }

    plat_memcpy(buffer_ + buffer_pos_, s, len);
    buffer_pos_ += len;
}

void Logger::flush() {
    flushBuffer();
}

void Logger::flushBuffer() {
    if (buffer_pos_ == 0 || log_file_ == PLAT_INVALID_FILE) {
        buffer_pos_ = 0;
        return;
    }

    if (plat_write_file(log_file_, buffer_, buffer_pos_) != (long)buffer_pos_) {
        plat_print_error("Error: Failed to flush log buffer to file\n");
    }
    buffer_pos_ = 0;
}
