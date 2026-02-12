#include "codegen.hpp"
#include "platform.hpp"
#include "test_framework.hpp"

TEST_FUNC(c89_emitter_basic) {
    ArenaAllocator arena(1024 * 1024);
    const char* filename = "test_emitter_basic.c";
    C89Emitter emitter(arena, filename);
    ASSERT_TRUE(emitter.isValid());

    emitter.emitComment("Hello World");
    emitter.writeString("int main() {\n");
    emitter.indent();
    emitter.writeIndent();
    emitter.writeString("return 0;\n");
    emitter.dedent();
    emitter.writeIndent();
    emitter.writeString("}\n");
    emitter.close();

    char* buffer = NULL;
    size_t size = 0;
    ASSERT_TRUE(plat_file_read(filename, &buffer, &size));
    ASSERT_TRUE(buffer != NULL);

    const char* expected = "/* Hello World */\nint main() {\n    return 0;\n}\n";
    ASSERT_EQ(0, plat_strcmp(buffer, expected));

    plat_free(buffer);
    plat_delete_file(filename);
    return true;
}

TEST_FUNC(c89_emitter_buffering) {
    ArenaAllocator arena(1024 * 1024);
    const char* filename = "test_emitter_buffering.c";
    C89Emitter emitter(arena, filename);
    ASSERT_TRUE(emitter.isValid());

    // Write exactly 4096 bytes to fill the buffer
    for (int i = 0; i < 4096; ++i) {
        emitter.write("A", 1);
    }
    // Buffer should be full but not flushed yet (Implementation flushes when next write exceeds size)

    // Write one more byte to trigger flush
    emitter.write("B", 1);

    emitter.close();

    char* buffer = NULL;
    size_t size = 0;
    ASSERT_TRUE(plat_file_read(filename, &buffer, &size));
    ASSERT_EQ(4097, (int)size);
    ASSERT_EQ('A', buffer[0]);
    ASSERT_EQ('A', buffer[4095]);
    ASSERT_EQ('B', buffer[4096]);

    plat_free(buffer);
    plat_delete_file(filename);
    return true;
}

TEST_FUNC(plat_file_raw_io) {
    const char* filename = "test_raw_io.txt";
    PlatFile f = plat_open_file(filename, true);
    ASSERT_TRUE(f != PLAT_INVALID_FILE);

    const char* data = "Hello Raw IO";
    plat_write_file(f, data, plat_strlen(data));
    plat_close_file(f);

    f = plat_open_file(filename, false);
    ASSERT_TRUE(f != PLAT_INVALID_FILE);
    char buf[64];
    size_t read = plat_read_file_raw(f, buf, sizeof(buf));
    ASSERT_EQ(plat_strlen(data), read);
    buf[read] = '\0';
    ASSERT_EQ(0, plat_strcmp(buf, data));
    plat_close_file(f);

    plat_delete_file(filename);
    return true;
}
