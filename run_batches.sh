#!/bin/bash
FLAGS="-m32 -std=c++98 -Wall -DZ98_TEST -Wno-error=unused-function -Wno-error=c++11-extensions -Wno-error=unused-variable -Isrc/include -Itests/integration -Itests/c89_validation -Itests"

echo "Batch,Status" > test_results.csv

for i in {0..77}; do
    MAIN_FILE="tests/main_batch$i.cpp"
    if [ ! -f "$MAIN_FILE" ]; then continue; fi

    echo "Processing Batch $i..."
    RUNNER_FILE="tests/batch_runner_$i.cpp"
    BINARY="./test_runner_batch$i"

    echo "// Generated batch runner for $MAIN_FILE" > "$RUNNER_FILE"
    echo "#include \"../src/bootstrap/bootstrap_all.cpp\"" >> "$RUNNER_FILE"
    echo "#include \"test_utils.cpp\"" >> "$RUNNER_FILE"
    echo "#include \"c89_validation/gcc_validator.cpp\"" >> "$RUNNER_FILE"
    echo "#include \"c89_validation/msvc6_validator.cpp\"" >> "$RUNNER_FILE"

    TEMP_FILE_LIST=$(mktemp)
    grep -o 'test_[a-zA-Z0-9_]*' "$MAIN_FILE" | sed 's/test_//' | sort | uniq | while read name; do
        find tests -name "*.cpp" | xargs grep -lE "TEST_FUNC\($name\)|bool test_$name\(\)" | grep -v "main_batch" | grep -v "test_declarations.hpp"
    done | sort | uniq > "$TEMP_FILE_LIST"

    while read test_file; do
        if [[ "$test_file" != "$MAIN_FILE" && "$test_file" != "tests/test_utils.cpp" && \
              "$test_file" != "tests/c89_validation/gcc_validator.cpp" && \
              "$test_file" != "tests/c89_validation/msvc6_validator.cpp" ]]; then
            REL_PATH=${test_file#tests/}
            echo "#include \"$REL_PATH\"" >> "$RUNNER_FILE"
        fi
    done < "$TEMP_FILE_LIST"
    rm "$TEMP_FILE_LIST"

    echo "#include \"main_batch$i.cpp\"" >> "$RUNNER_FILE"

    g++ $FLAGS "$RUNNER_FILE" -o "$BINARY" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "$i,COMPILE_FAIL" >> test_results.csv
        echo "Batch $i: COMPILE_FAIL"
        continue
    fi

    $BINARY > batch_$i.log 2>&1
    if [ $? -eq 0 ]; then
        echo "$i,PASS" >> test_results.csv
        echo "Batch $i: PASS"
    else
        echo "$i,FAIL" >> test_results.csv
        echo "Batch $i: FAIL"
    fi
    rm -f "$BINARY"
done
