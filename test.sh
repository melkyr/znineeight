#!/bin/bash
# test.sh - Dumb and reliable test runner compilation script

echo "Compiling RetroZig Batch Test Runners..."

FLAGS="-std=c++98 -Wall -Wno-error=unused-function -Wno-error=c++11-extensions -Wno-error=unused-variable -Isrc/include -Itests/integration -Itests/c89_validation -Itests"

# Optional: Add -DDEBUG if needed, though batches should be self-contained
# FLAGS="$FLAGS -DDEBUG"

for i in {1..29}; do
    MAIN_FILE="tests/main_batch$i.cpp"
    if [ ! -f "$MAIN_FILE" ]; then
        echo "Skipping Batch $i (no main file found)"
        continue
    fi

    echo "Generating and Compiling Batch $i..."
    RUNNER_FILE="tests/batch_runner_$i.cpp"

    # Generate the self-contained runner
    echo "// Generated batch runner for $MAIN_FILE" > "$RUNNER_FILE"
    echo "#include \"../src/bootstrap/bootstrap_all.cpp\"" >> "$RUNNER_FILE"
    echo "#include \"test_utils.cpp\"" >> "$RUNNER_FILE"

    # Always include validation helpers as they are used by integration tests
    echo "#include \"c89_validation/gcc_validator.cpp\"" >> "$RUNNER_FILE"
    echo "#include \"c89_validation/msvc6_validator.cpp\"" >> "$RUNNER_FILE"

    # Find needed test files
    TEMP_FILE_LIST=$(mktemp)
    grep -o 'test_[a-zA-Z0-9_]*' "$MAIN_FILE" | sed 's/test_//' | sort | uniq | while read name; do
        find tests -name "*.cpp" | xargs grep -lE "TEST_FUNC\($name\)|bool test_$name\(\)" | grep -v "main_batch" | grep -v "test_declarations.hpp"
    done | sort | uniq > "$TEMP_FILE_LIST"

    # Add dependencies: if a file in a subdirectory is needed, include all files in that subdirectory
    cat "$TEMP_FILE_LIST" | while read test_file; do
        DIR=$(dirname "$test_file")
        if [[ "$DIR" != "tests" ]]; then
            find "$DIR" -name "*.cpp"
        else
            echo "$test_file"
        fi
    done | sort | uniq | while read test_file; do
        if [[ "$test_file" != "$MAIN_FILE" && "$test_file" != "tests/test_utils.cpp" && \
              "$test_file" != "tests/c89_validation/gcc_validator.cpp" && \
              "$test_file" != "tests/c89_validation/msvc6_validator.cpp" ]]; then
            REL_PATH=${test_file#tests/}
            echo "#include \"$REL_PATH\"" >> "$RUNNER_FILE"
        fi
    done
    rm "$TEMP_FILE_LIST"

    echo "#include \"main_batch$i.cpp\"" >> "$RUNNER_FILE"

    # Compile the runner
    g++ $FLAGS "$RUNNER_FILE" -o "test_runner_batch$i"
    if [ $? -ne 0 ]; then
        echo "Compilation of Batch $i failed!"
        exit 1
    fi
done

echo "Running all tests..."
./run_all_tests.sh "$@"
