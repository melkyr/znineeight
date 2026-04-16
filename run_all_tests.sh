#!/bin/bash

RESULTS_FILE="test_results.log"
rm -f $RESULTS_FILE

BATCHES=$(ls tests/main_batch*.cpp)

TOTAL_PASSES=0
TOTAL_FAILS=0
TOTAL_BATCHES=0

# Compiler and Flags
CXX="g++"
CXXFLAGS="-std=c++98 -m32 -Isrc/include -Itests -Itests/c89_validation -Itests/integration -DZ98_TEST"

for batch_file in $BATCHES; do
    # Extract batch name (e.g., batch1, batch9a, batch_bugs)
    batch_name=$(basename "$batch_file" .cpp | sed 's/main_//')
    runner_file="tests/${batch_name/batch/batch_runner_}.cpp"

    # Handle special case for batch_bugs
    if [[ "$batch_name" == "batch_bugs" ]]; then
        runner_file="tests/batch_runner__bugs.cpp"
    fi

    echo "Running $batch_name..." | tee -a $RESULTS_FILE

    executable="./${batch_name}_test"

    $CXX $CXXFLAGS "$runner_file" -o "$executable" 2>>$RESULTS_FILE

    if [ $? -ne 0 ]; then
        echo "COMPILATION FAILED for $batch_name" | tee -a $RESULTS_FILE
        ((TOTAL_FAILS++))
    else
        "$executable" >> $RESULTS_FILE 2>&1
        if [ $? -eq 0 ]; then
            echo "$batch_name: PASS" | tee -a $RESULTS_FILE
            ((TOTAL_PASSES++))
        else
            echo "$batch_name: FAIL" | tee -a $RESULTS_FILE
            ((TOTAL_FAILS++))
        fi
        rm "$executable"
    fi
    ((TOTAL_BATCHES++))
    echo "-----------------------------------" >> $RESULTS_FILE
done

echo "Summary:" | tee -a $RESULTS_FILE
echo "Total Batches: $TOTAL_BATCHES" | tee -a $RESULTS_FILE
echo "Passed: $TOTAL_PASSES" | tee -a $RESULTS_FILE
echo "Failed: $TOTAL_FAILS" | tee -a $RESULTS_FILE
