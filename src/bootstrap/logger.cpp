#include "logger.hpp"
#include "platform.hpp"

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

    // Determine console output visibility
    bool show_on_console = console_enabled_;

    // --no-logs (suppress_all_) only suppresses INFO and DEBUG on console.
    // WARNING and ERROR should always be shown if console_enabled_ is true.
    if (suppress_all_ && (level == LOG_INFO || level == LOG_DEBUG)) {
        show_on_console = false;
    }

    // DEBUG logs only shown on console if verbose is specifically requested
    if (level == LOG_DEBUG && !verbose_) {
        show_on_console = false;
    }

    if (show_on_console) {
        if (level == LOG_ERROR || level == LOG_WARNING) {
            plat_write_stderr(msg);
        } else {
            plat_write_stdout(msg);
        }
    }

    // File output logic (buffered). Always log everything to file if enabled,
    // regardless of console suppression flags.
    if (file_enabled_) {
        size_t len = plat_strlen(msg);
        writeToBuffer(msg, len);
    }
}

void Logger::logf(LogLevel level, const char* format, ...) {
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
            plat_write_file(log_file_, s, len);
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

    plat_write_file(log_file_, buffer_, buffer_pos_);
    buffer_pos_ = 0;
}
