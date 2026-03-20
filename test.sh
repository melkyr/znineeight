#!/bin/bash
# test.sh - Optimized and reliable test runner compilation script

echo "Compiling RetroZig Batch Test Runners..."

FLAGS="-std=c++98 -Wall -DRETROZIG_TEST -Wno-error=unused-function -Wno-error=c++11-extensions -Wno-error=unused-variable -Isrc/include -Itests/integration -Itests/c89_validation -Itests"

# Index all tests once
echo "Indexing tests..."
INDEX_FILE=$(mktemp)
find tests src -name "*.cpp" | xargs grep -E "TEST_FUNC\([a-zA-Z0-9_]+\)|bool test_[a-zA-Z0-9_]+\(\)" | grep -v "main_batch" | grep -v "test_declarations.hpp" > "$INDEX_FILE"

for MAIN_FILE in tests/main_batch*.cpp; do
    if [ ! -f "$MAIN_FILE" ]; then continue; fi

    i=$(echo "$MAIN_FILE" | sed 's/tests\/main_batch//;s/\.cpp//')
    echo "Generating and Compiling Batch $i..."
    RUNNER_FILE="tests/batch_runner_$i.cpp"

    echo "// Generated batch runner for $MAIN_FILE" > "$RUNNER_FILE"
    echo "#include \"../src/bootstrap/bootstrap_all.cpp\"" >> "$RUNNER_FILE"
    echo "#include \"test_utils.cpp\"" >> "$RUNNER_FILE"
    echo "#include \"c89_validation/gcc_validator.cpp\"" >> "$RUNNER_FILE"
    echo "#include \"c89_validation/msvc6_validator.cpp\"" >> "$RUNNER_FILE"

    # Extract all test names from the main file
    TEST_NAMES=$(grep -o 'test_[a-zA-Z0-9_]*' "$MAIN_FILE" | sed 's/test_//' | sort | uniq | grep -vE "^declarations$|^runner_main$")

    # Find all unique source files needed for these tests
    NEEDED_FILES=$(for name in $TEST_NAMES; do
        grep -E "TEST_FUNC\($name\)|bool test_$name\(\)" "$INDEX_FILE" | cut -d: -f1
    done | sort | uniq)

    # Add dependencies: if a file in a subdirectory is needed, include all files in that subdirectory
    # (Matching original test.sh logic)
    for test_file in $NEEDED_FILES; do
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
            # If it's not in tests/, we need to handle it carefully, but mostly they are in tests/
            if [[ "$test_file" == tests/* ]]; then
                echo "#include \"$REL_PATH\"" >> "$RUNNER_FILE"
            else
                # Handle cases outside tests/ if any
                echo "#include \"../$test_file\"" >> "$RUNNER_FILE"
            fi
        fi
    done

    echo "#include \"main_batch$i.cpp\"" >> "$RUNNER_FILE"

    g++ $FLAGS "$RUNNER_FILE" -o "test_runner_batch$i"
    if [ $? -ne 0 ]; then
        echo "Compilation of Batch $i failed!"
        # Keep runner for debugging
        exit 1
    fi
done

rm "$INDEX_FILE"

echo "Running all tests..."
./run_all_tests.sh "$@"
