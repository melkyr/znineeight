#include "platform.hpp"
#include "logger.hpp"
#include <stdarg.h>
#include <stdio.h>

static Logger* g_logger = NULL;
static bool g_logging_in_progress = false;

void plat_set_logger(Logger* logger) { g_logger = logger; }
Logger* plat_get_logger() { return g_logger; }

// Internal low-level write functions (bypassing logger)
#ifdef _WIN32
void plat_write_stdout_internal(const char* message);
void plat_write_stderr_internal(const char* message);
#else
#include <unistd.h>
void plat_write_stdout_internal(const char* message) {
    if (!message) return;
    write(STDOUT_FILENO, message, plat_strlen(message));
}
void plat_write_stderr_internal(const char* message) {
    if (!message) return;
    write(STDERR_FILENO, message, plat_strlen(message));
}
#endif

static void plat_reverse(char* str, int length) {
    int start = 0;
    int end = length - 1;
    while (start < end) {
        char temp = str[start];
        str[start] = str[end];
        str[end] = temp;
        start++;
        end--;
    }
}

#ifdef _WIN32
// --- Windows Implementation ---

#pragma comment(lib, "wsock32.lib")

int plat_socket_init(void) {
    WSADATA wsa;
    return WSAStartup(MAKEWORD(1, 1), &wsa);
}

void plat_socket_cleanup(void) {
    WSACleanup();
}

PlatSocket plat_create_tcp_server(u16 port) {
    SOCKET s = socket(AF_INET, SOCK_STREAM, 0);
    if (s == INVALID_SOCKET) return PLAT_INVALID_SOCKET;

    struct sockaddr_in addr;
    plat_memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(s, (struct sockaddr*)&addr, sizeof(addr)) == SOCKET_ERROR) {
        closesocket(s);
        return PLAT_INVALID_SOCKET;
    }

    return s;
}

int plat_bind_listen(PlatSocket sock, int backlog) {
    if (listen(sock, backlog) == SOCKET_ERROR) return -1;
    return 0;
}

PlatSocket plat_accept(PlatSocket server_sock) {
    return accept(server_sock, NULL, NULL);
}

int plat_recv(PlatSocket sock, char* buf, int len) {
    return recv(sock, buf, len, 0);
}

int plat_send(PlatSocket sock, const char* buf, int len) {
    return send(sock, buf, len, 0);
}

void plat_close_socket(PlatSocket sock) {
    closesocket(sock);
}

int plat_socket_select(int nfds, plat_fd_set* readfds, plat_fd_set* writefds, plat_fd_set* exceptfds, int timeout_ms) {
    struct timeval tv;
    struct timeval* p_tv = NULL;
    if (timeout_ms >= 0) {
        tv.tv_sec = timeout_ms / 1000;
        tv.tv_usec = (timeout_ms % 1000) * 1000;
        p_tv = &tv;
    }
    return select(nfds, (fd_set*)readfds, (fd_set*)writefds, (fd_set*)exceptfds, p_tv);
}

void plat_socket_fd_zero(plat_fd_set* s) { FD_ZERO((fd_set*)s); }
void plat_socket_fd_set(PlatSocket fd, plat_fd_set* s) { FD_SET(fd, (fd_set*)s); }
bool plat_socket_fd_isset(PlatSocket fd, plat_fd_set* s) { return FD_ISSET(fd, (fd_set*)s) != 0; }

void* plat_alloc(size_t size) {
    if (size == 0) return NULL;
    if (size > 4 * 1024 * 1024) {  /* > 4 MB */
        /* VirtualAlloc gives page-aligned memory, suitable for large blocks */
        return VirtualAlloc(NULL, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    } else {
        return HeapAlloc(GetProcessHeap(), 0, size);
    }
}

void plat_free(void* ptr) {
    if (!ptr) return;
    /* Freeing a VirtualAlloc block requires VirtualFree */
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery(ptr, &mbi, sizeof(mbi)) && mbi.AllocationBase == ptr) {
        VirtualFree(ptr, 0, MEM_RELEASE);
    } else {
        HeapFree(GetProcessHeap(), 0, ptr);
    }
}

void* plat_realloc(void* ptr, size_t new_size) {
    if (!ptr) return plat_alloc(new_size);
    return HeapReAlloc(GetProcessHeap(), 0, ptr, new_size);
}

PlatFile plat_open_file(const char* path, bool write) {
    DWORD access = write ? GENERIC_WRITE : GENERIC_READ;
    DWORD creation = write ? CREATE_ALWAYS : OPEN_EXISTING;
    return CreateFileA(path, access, FILE_SHARE_READ, NULL, creation, FILE_ATTRIBUTE_NORMAL, NULL);
}

long plat_write_file(PlatFile file, const void* data, size_t size) {
    if (file == PLAT_INVALID_FILE) return -1;
    DWORD written;
    if (WriteFile(file, data, (DWORD)size, &written, NULL)) {
        return (long)written;
    }
    return -1;
}

size_t plat_read_file_raw(PlatFile file, void* buffer, size_t size) {
    if (file == PLAT_INVALID_FILE) return 0;
    DWORD read;
    if (ReadFile(file, buffer, (DWORD)size, &read, NULL)) {
        return (size_t)read;
    }
    return 0;
}

void plat_close_file(PlatFile file) {
    if (file != PLAT_INVALID_FILE) {
        CloseHandle(file);
    }
}

bool plat_file_read(const char* path, char** buffer, size_t* size) {
    HANDLE hFile = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ,
                               NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return false;

    DWORD fileSize = GetFileSize(hFile, NULL);
    if (fileSize == INVALID_FILE_SIZE) {
        CloseHandle(hFile);
        return false;
    }

    *buffer = (char*)plat_alloc(fileSize + 1);
    if (!*buffer) {
        CloseHandle(hFile);
        return false;
    }

    DWORD bytesRead;
    if (!ReadFile(hFile, *buffer, fileSize, &bytesRead, NULL)) {
        plat_free(*buffer);
        CloseHandle(hFile);
        return false;
    }

    (*buffer)[fileSize] = '\0';
    if (size) *size = (size_t)fileSize;

    CloseHandle(hFile);
    return true;
}

void plat_write_stdout_internal(const char* message) {
    if (!message) return;
    HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
    if (hOut == INVALID_HANDLE_VALUE || hOut == NULL) {
        hOut = GetStdHandle(STD_ERROR_HANDLE);
        if (hOut == INVALID_HANDLE_VALUE || hOut == NULL) return;
    }

    DWORD written = 0;
    DWORD len = (DWORD)plat_strlen(message);
    if (!WriteConsoleA(hOut, (LPCSTR)message, len, &written, NULL)) {
        WriteFile(hOut, message, len, &written, NULL);
    }
}

void plat_write_stderr_internal(const char* message) {
    if (!message) return;
    HANDLE hErr = GetStdHandle(STD_ERROR_HANDLE);
    if (hErr == INVALID_HANDLE_VALUE || hErr == NULL) return;

    DWORD written = 0;
    DWORD len = (DWORD)plat_strlen(message);
    if (!WriteConsoleA(hErr, (LPCSTR)message, len, &written, NULL)) {
        WriteFile(hErr, message, len, &written, NULL);
    }
}

void plat_print_info(const char* message) {
    if (g_logger && !g_logging_in_progress) {
        g_logging_in_progress = true;
        g_logger->log(LOG_INFO, message);
        g_logging_in_progress = false;
    } else {
        plat_write_stdout_internal(message);
    }
}

void plat_print_error(const char* message) {
    if (g_logger && !g_logging_in_progress) {
        g_logging_in_progress = true;
        g_logger->log(LOG_ERROR, message);
        g_logging_in_progress = false;
    } else {
        plat_write_stderr_internal(message);
    }
}

void plat_print_debug(const char* message) {
    OutputDebugStringA(message);
    if (g_logger && !g_logging_in_progress) {
        g_logging_in_progress = true;
        g_logger->log(LOG_DEBUG, message);
        g_logging_in_progress = false;
    } else {
        plat_write_stderr_internal(message);
    }
}

void plat_printf_debug(const char* format, ...) {
    char buffer[4096];
    va_list args;
    va_start(args, format);
    plat_vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    buffer[sizeof(buffer)-1] = '\0';
    plat_print_debug(buffer);
}

int plat_snprintf(char* str, size_t size, const char* format, ...) {
    va_list args;
    va_start(args, format);
    int result = plat_vsnprintf(str, size, format, args);
    va_end(args);
    return result;
}

int plat_vsnprintf(char* str, size_t size, const char* format, va_list args) {
#ifdef _MSC_VER
    return _vsnprintf(str, size, format, args);
#else
    return vsnprintf(str, size, format, args);
#endif
}


void plat_u64_to_string(u64 value, char* buffer, size_t buffer_size) {
    if (buffer_size == 0) return;
    if (value == 0) {
        if (buffer_size > 1) {
            buffer[0] = '0';
            buffer[1] = '\0';
        } else {
            buffer[0] = '\0';
        }
        return;
    }

    int i = 0;
    while (value > 0 && (size_t)i < buffer_size - 1) {
        buffer[i++] = (char)((value % 10) + '0');
        value /= 10;
    }
    buffer[i] = '\0';
    plat_reverse(buffer, i);
}

void plat_i64_to_string(i64 value, char* buffer, size_t buffer_size) {
    if (buffer_size == 0) return;
    if (value == 0) {
        plat_u64_to_string(0, buffer, buffer_size);
        return;
    }

    int i = 0;
    bool negative = false;
    u64 uval;

    if (value < 0) {
        negative = true;
        uval = (u64)-(value + 1) + 1; // Avoid overflow for MIN_I64
    } else {
        uval = (u64)value;
    }

    while (uval > 0 && (size_t)i < buffer_size - 1) {
        buffer[i++] = (char)((uval % 10) + '0');
        uval /= 10;
    }

    if (negative && (size_t)i < buffer_size - 1) {
        buffer[i++] = '-';
    }

    buffer[i] = '\0';
    plat_reverse(buffer, i);
}

void plat_float_to_string(double value, char* buffer, size_t buffer_size) {
    /*
     * TODO: Implement a custom dtoa to fully avoid msvcrt.dll dependency
     * in the final kernel32-only bootstrap.
     * For now, we use plat_snprintf to maintain %.15g behavior required by tests.
     */
    plat_snprintf(buffer, buffer_size, "%.15g", value);
}

size_t plat_strlen(const char* s) {
    const char* p = s;
    while (*p) p++;
    return (size_t)(p - s);
}

void plat_memcpy(void* dest, const void* src, size_t n) {
    char* d = (char*)dest;
    const char* s = (const char*)src;
    while (n--) *d++ = *s++;
}

void plat_memmove(void* dest, const void* src, size_t n) {
    char* d = (char*)dest;
    const char* s = (const char*)src;
    if (d < s) {
        while (n--) *d++ = *s++;
    } else {
        d += n;
        s += n;
        while (n--) *--d = *--s;
    }
}

void plat_strcpy(char* dest, const char* src) {
    while ((*dest++ = *src++))
        ;
}

void plat_strcat(char* dest, const char* src) {
    while (*dest) dest++;
    while ((*dest++ = *src++))
        ;
}

void plat_strncpy(char* dest, const char* src, size_t n) {
    size_t i;
    for (i = 0; i < n && src[i] != '\0'; i++)
        dest[i] = src[i];
    for ( ; i < n; i++)
        dest[i] = '\0';
}

int plat_strcmp(const char* s1, const char* s2) {
    while (*s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

int plat_strncmp(const char* s1, const char* s2, size_t n) {
    while (n && *s1 && (*s1 == *s2)) {
        s1++;
        s2++;
        n--;
    }
    if (n == 0) return 0;
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

char* plat_strchr(const char* s, int c) {
    while (*s != (char)c) {
        if (!*s) return NULL;
        s++;
    }
    return (char*)s;
}

char* plat_strrchr(const char* s, int c) {
    const char* last = NULL;
    do {
        if (*s == (char)c) last = s;
    } while (*s++);
    return (char*)last;
}

int plat_memcmp(const void* s1, const void* s2, size_t n) {
    const unsigned char* p1 = (const unsigned char*)s1;
    const unsigned char* p2 = (const unsigned char*)s2;
    while (n--) {
        if (*p1 != *p2) return *p1 - *p2;
        p1++;
        p2++;
    }
    return 0;
}

void plat_memset(void* s, int c, size_t n) {
    unsigned char* p = (unsigned char*)s;
    while (n--) *p++ = (unsigned char)c;
}

int plat_run_command(const char* cmd, char** output, size_t* output_size) {
    (void)cmd;
    (void)output;
    (void)output_size;
    return -1;
}

char* plat_create_temp_file(const char* prefix, const char* suffix) {
    (void)prefix;
    (void)suffix;
    return NULL;
}

int plat_delete_file(const char* path) {
    if (DeleteFileA(path)) return 0;
    return -1;
}

int plat_mkdir(const char* path) {
    if (CreateDirectoryA(path, NULL)) return 0;
    return -1;
}

bool plat_file_exists(const char* path) {
    DWORD dwAttrib = GetFileAttributesA(path);
    return (dwAttrib != INVALID_FILE_ATTRIBUTES);
}

void plat_get_executable_dir(char* buffer, size_t size) {
    if (GetModuleFileNameA(NULL, buffer, (DWORD)size) == 0) {
        plat_strcpy(buffer, ".");
        return;
    }
    char* last_slash = plat_strrchr(buffer, '\\');
    if (last_slash) {
        *last_slash = '\0';
    } else {
        plat_strcpy(buffer, ".");
    }
}

void plat_abort() {
    /*
     * Use exit code 3 on Windows to match what expect_abort() in test_utils.cpp
     * expects for an aborting child process.
     */
    TerminateProcess(GetCurrentProcess(), 3);
}

#else
// --- Linux/POSIX Implementation ---

#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <cstdlib>
#include <cstring>

void* plat_alloc(size_t size) {
    return malloc(size);
}

void plat_free(void* ptr) {
    free(ptr);
}

void* plat_realloc(void* ptr, size_t new_size) {
    return realloc(ptr, new_size);
}

PlatFile plat_open_file(const char* path, bool write) {
    int flags = write ? (O_WRONLY | O_CREAT | O_TRUNC) : O_RDONLY;
    mode_t mode = write ? 0644 : 0;
    return open(path, flags, mode);
}

long plat_write_file(PlatFile file, const void* data, size_t size) {
    if (file == PLAT_INVALID_FILE) return -1;
    size_t total_written = 0;
    while (total_written < size) {
        ssize_t written = write(file, (const char*)data + total_written, size - total_written);
        if (written <= 0) {
            if (total_written > 0) return (long)total_written;
            return -1;
        }
        total_written += (size_t)written;
    }
    return (long)total_written;
}

size_t plat_read_file_raw(PlatFile file, void* buffer, size_t size) {
    if (file == PLAT_INVALID_FILE) return 0;
    ssize_t bytes_read = read(file, buffer, size);
    if (bytes_read < 0) return 0;
    return (size_t)bytes_read;
}

void plat_close_file(PlatFile file) {
    if (file != PLAT_INVALID_FILE) {
        close(file);
    }
}

bool plat_file_read(const char* path, char** buffer, size_t* size) {
    int fd = open(path, O_RDONLY);
    if (fd == -1) return false;

    struct stat st;
    if (fstat(fd, &st) == -1) {
        close(fd);
        return false;
    }

    *buffer = (char*)plat_alloc(st.st_size + 1);
    if (!*buffer) {
        close(fd);
        return false;
    }

    ssize_t bytesRead = read(fd, *buffer, st.st_size);
    if (bytesRead == -1) {
        plat_free(*buffer);
        close(fd);
        return false;
    }

    (*buffer)[st.st_size] = '\0';
    if (size) *size = (size_t)st.st_size;

    close(fd);
    return true;
}

void plat_print_info(const char* message) {
    if (g_logger && !g_logging_in_progress) {
        g_logging_in_progress = true;
        g_logger->log(LOG_INFO, message);
        g_logging_in_progress = false;
    } else {
        plat_write_stdout_internal(message);
    }
}

void plat_print_error(const char* message) {
    if (g_logger && !g_logging_in_progress) {
        g_logging_in_progress = true;
        g_logger->log(LOG_ERROR, message);
        g_logging_in_progress = false;
    } else {
        plat_write_stderr_internal(message);
    }
}

void plat_print_debug(const char* message) {
    if (g_logger && !g_logging_in_progress) {
        g_logging_in_progress = true;
        g_logger->log(LOG_DEBUG, message);
        g_logging_in_progress = false;
    } else {
        plat_write_stderr_internal("[DEBUG] ");
        plat_write_stderr_internal(message);
    }
}

void plat_printf_debug(const char* format, ...) {
    char buffer[4096];
    va_list args;
    va_start(args, format);
    plat_vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    buffer[sizeof(buffer)-1] = '\0';
    plat_print_debug(buffer);
}

int plat_snprintf(char* str, size_t size, const char* format, ...) {
    va_list args;
    va_start(args, format);
    int result = plat_vsnprintf(str, size, format, args);
    va_end(args);
    return result;
}

int plat_vsnprintf(char* str, size_t size, const char* format, va_list args) {
    return vsnprintf(str, size, format, args);
}


void plat_u64_to_string(u64 value, char* buffer, size_t buffer_size) {
    if (buffer_size == 0) return;
    if (value == 0) {
        if (buffer_size > 1) {
            buffer[0] = '0';
            buffer[1] = '\0';
        } else {
            buffer[0] = '\0';
        }
        return;
    }

    int i = 0;
    while (value > 0 && (size_t)i < buffer_size - 1) {
        buffer[i++] = (char)((value % 10) + '0');
        value /= 10;
    }
    buffer[i] = '\0';
    plat_reverse(buffer, i);
}

void plat_i64_to_string(i64 value, char* buffer, size_t buffer_size) {
    if (buffer_size == 0) return;
    if (value == 0) {
        plat_u64_to_string(0, buffer, buffer_size);
        return;
    }

    int i = 0;
    bool negative = false;
    u64 uval;

    if (value < 0) {
        negative = true;
        uval = (u64)-(value + 1) + 1; // Avoid overflow for MIN_I64
    } else {
        uval = (u64)value;
    }

    while (uval > 0 && (size_t)i < buffer_size - 1) {
        buffer[i++] = (char)((uval % 10) + '0');
        uval /= 10;
    }

    if (negative && (size_t)i < buffer_size - 1) {
        buffer[i++] = '-';
    }

    buffer[i] = '\0';
    plat_reverse(buffer, i);
}

void plat_float_to_string(double value, char* buffer, size_t buffer_size) {
    /*
     * TODO: Implement a custom dtoa to fully avoid msvcrt.dll dependency
     * in the final kernel32-only bootstrap.
     * For now, we use plat_snprintf to maintain %.15g behavior required by tests.
     */
    plat_snprintf(buffer, buffer_size, "%.15g", value);
}

size_t plat_strlen(const char* s) {
    return strlen(s);
}

void plat_memcpy(void* dest, const void* src, size_t n) {
    memcpy(dest, src, n);
}

void plat_memmove(void* dest, const void* src, size_t n) {
    memmove(dest, src, n);
}

void plat_strcpy(char* dest, const char* src) {
    strcpy(dest, src);
}

void plat_strcat(char* dest, const char* src) {
    strcat(dest, src);
}

void plat_strncpy(char* dest, const char* src, size_t n) {
    strncpy(dest, src, n);
}

int plat_strcmp(const char* s1, const char* s2) {
    return strcmp(s1, s2);
}

int plat_strncmp(const char* s1, const char* s2, size_t n) {
    return strncmp(s1, s2, n);
}

char* plat_strchr(const char* s, int c) {
    return (char*)strchr(s, c);
}

char* plat_strrchr(const char* s, int c) {
    return (char*)strrchr(s, c);
}

int plat_memcmp(const void* s1, const void* s2, size_t n) {
    return memcmp(s1, s2, n);
}

void plat_memset(void* s, int c, size_t n) {
    memset(s, c, n);
}

int plat_run_command(const char* cmd, char** output, size_t* output_size) {
    FILE* pipe = popen(cmd, "r");
    if (!pipe) return -1;

    char buffer[1024];
    size_t total_size = 0;
    char* full_output = NULL;

    while (fgets(buffer, sizeof(buffer), pipe)) {
        size_t len = strlen(buffer);
        char* next = (char*)plat_realloc(full_output, total_size + len + 1);
        if (!next) {
            plat_free(full_output);
            pclose(pipe);
            return -1;
        }
        full_output = next;
        memcpy(full_output + total_size, buffer, len);
        total_size += len;
        full_output[total_size] = '\0';
    }

    if (output) *output = full_output;
    else plat_free(full_output);

    if (output_size) *output_size = total_size;

    int status = pclose(pipe);
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return -1;
}

char* plat_create_temp_file(const char* prefix, const char* suffix) {
    char template_path[256];
    const char* tmpdir = getenv("TMPDIR");
    if (!tmpdir) tmpdir = "/tmp";

    plat_strncpy(template_path, tmpdir, sizeof(template_path) - 64);
    plat_strcpy(template_path + plat_strlen(template_path), "/");
    if (prefix) plat_strcpy(template_path + plat_strlen(template_path), prefix);
    plat_strcpy(template_path + plat_strlen(template_path), "XXXXXX");

    int fd = mkstemp(template_path);
    if (fd == -1) return NULL;
    close(fd);

    char final_path[256];
    plat_strcpy(final_path, template_path);
    if (suffix) {
        plat_strcpy(final_path + plat_strlen(final_path), suffix);
        if (rename(template_path, final_path) != 0) {
            unlink(template_path);
            return NULL;
        }
    }

    size_t final_len = plat_strlen(final_path);
    char* result = (char*)plat_alloc(final_len + 1);
    if (result) {
        plat_strcpy(result, final_path);
    }
    return result;
}

int plat_delete_file(const char* path) {
    return unlink(path);
}

int plat_mkdir(const char* path) {
    return mkdir(path, 0777);
}

bool plat_file_exists(const char* path) {
    return access(path, F_OK) == 0;
}

void plat_get_executable_dir(char* buffer, size_t size) {
    ssize_t len = readlink("/proc/self/exe", buffer, size - 1);
    if (len != -1) {
        buffer[len] = '\0';
        char* last_slash = plat_strrchr(buffer, '/');
        if (last_slash) {
            *last_slash = '\0';
        } else {
            plat_strcpy(buffer, ".");
        }
    } else {
        plat_strcpy(buffer, ".");
    }
}

void plat_abort() {
    abort();
}

int plat_socket_init(void) { return 0; }
void plat_socket_cleanup(void) {}

PlatSocket plat_create_tcp_server(u16 port) {
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return PLAT_INVALID_SOCKET;

    int opt = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    plat_memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(s, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(s);
        return PLAT_INVALID_SOCKET;
    }

    return s;
}

int plat_bind_listen(PlatSocket sock, int backlog) {
    if (listen(sock, backlog) < 0) return -1;
    return 0;
}

PlatSocket plat_accept(PlatSocket server_sock) {
    return accept(server_sock, NULL, NULL);
}

int plat_recv(PlatSocket sock, char* buf, int len) {
    return recv(sock, buf, len, 0);
}

int plat_send(PlatSocket sock, const char* buf, int len) {
    return send(sock, buf, len, 0);
}

void plat_close_socket(PlatSocket sock) {
    close(sock);
}

int plat_socket_select(int nfds, plat_fd_set* readfds, plat_fd_set* writefds, plat_fd_set* exceptfds, int timeout_ms) {
    struct timeval tv;
    struct timeval* p_tv = NULL;
    if (timeout_ms >= 0) {
        tv.tv_sec = timeout_ms / 1000;
        tv.tv_usec = (timeout_ms % 1000) * 1000;
        p_tv = &tv;
    }
    return select(nfds, (fd_set*)readfds, (fd_set*)writefds, (fd_set*)exceptfds, p_tv);
}

void plat_socket_fd_zero(plat_fd_set* s) { FD_ZERO((fd_set*)s); }
void plat_socket_fd_set(PlatSocket fd, plat_fd_set* s) { FD_SET(fd, (fd_set*)s); }
bool plat_socket_fd_isset(PlatSocket fd, plat_fd_set* s) { return FD_ISSET(fd, (fd_set*)s) != 0; }

int plat_atoi(const char* str) {
    if (!str) return 0;
    int res = 0;
    int sign = 1;
    while (*str == ' ' || *str == '\t' || *str == '\n' || *str == '\r') str++;
    if (*str == '-') {
        sign = -1;
        str++;
    } else if (*str == '+') {
        str++;
    }
    while (*str >= '0' && *str <= '9') {
        res = res * 10 + (*str - '0');
        str++;
    }
    return res * sign;
}
#endif
