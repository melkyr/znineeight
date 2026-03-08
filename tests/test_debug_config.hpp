#ifndef TEST_DEBUG_CONFIG_HPP
#define TEST_DEBUG_CONFIG_HPP

#include "platform.hpp"

struct TestDebugConfig {
    static bool& lifter_debug() { static bool val = false; return val; }
    static bool& codegen_debug() { static bool val = false; return val; }
    static bool& validate_symbols() { static bool val = false; return val; }
    static bool& dump_ast() { static bool val = false; return val; }

    static void enableAll() {
        lifter_debug() = true;
        codegen_debug() = true;
        validate_symbols() = true;
        dump_ast() = true;
    }

    static void reset() {
        lifter_debug() = false;
        codegen_debug() = false;
        validate_symbols() = false;
        dump_ast() = false;
    }
};

#endif
