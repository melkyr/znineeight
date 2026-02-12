#include "platform.hpp"

#ifdef _WIN32
// --- Windows Implementation ---

void* plat_alloc(size_t size) {
    return HeapAlloc(GetProcessHeap(), 0, size);
}

void plat_free(void* ptr) {
    if (ptr) {
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

void plat_write_file(PlatFile file, const void* data, size_t size) {
    if (file == PLAT_INVALID_FILE) return;
    DWORD written;
    WriteFile(file, data, (DWORD)size, &written, NULL);
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

void plat_print_info(const char* message) {
    DWORD written;
    HANDLE hStdOut = GetStdHandle(STD_OUTPUT_HANDLE);
    if (hStdOut != INVALID_HANDLE_VALUE && hStdOut != NULL) {
        WriteFile(hStdOut, message, (DWORD)plat_strlen(message), &written, NULL);
    }
}

void plat_print_error(const char* message) {
    DWORD written;
    HANDLE hStdErr = GetStdHandle(STD_ERROR_HANDLE);
    if (hStdErr != INVALID_HANDLE_VALUE && hStdErr != NULL) {
        WriteFile(hStdErr, message, (DWORD)plat_strlen(message), &written, NULL);
    }
}

void plat_print_debug(const char* message) {
    OutputDebugStringA(message);
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
    // Windows implementation using CreateProcess would go here
    // For now, let's use _popen for simplicity if it were allowed,
    // but the instruction says kernel32 only.
    // Stubs for now.
    (void)cmd;
    (void)output;
    (void)output_size;
    return -1;
}

char* plat_create_temp_file(const char* prefix, const char* suffix) {
    // GetTempPath + GetTempFileName + rename to add suffix
    (void)prefix;
    (void)suffix;
    return NULL;
}

int plat_delete_file(const char* path) {
    if (DeleteFileA(path)) return 0;
    return -1;
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
#include <cstdio>

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
    int mode = write ? 0644 : 0;
    return open(path, flags, mode);
}

void plat_write_file(PlatFile file, const void* data, size_t size) {
    if (file == PLAT_INVALID_FILE) return;
    size_t total_written = 0;
    while (total_written < size) {
        ssize_t written = write(file, (const char*)data + total_written, size - total_written);
        if (written <= 0) break;
        total_written += written;
    }
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
    write(STDOUT_FILENO, message, plat_strlen(message));
}

void plat_print_error(const char* message) {
    write(STDERR_FILENO, message, plat_strlen(message));
}

void plat_print_debug(const char* message) {
    // On Linux, we just print to stderr for "debug"
    plat_print_error("[DEBUG] ");
    plat_print_error(message);
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

#endif
