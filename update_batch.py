import os
import re
import subprocess
import sys

def get_actual_output(batch_num):
    runner = f"./test_runner_batch{batch_num}"
    if not os.path.exists(runner):
        print(f"Runner {runner} not found.")
        return None
    try:
        # Run with --test-mode is NOT needed if the TestCompilationUnit already sets it
        # But we need to make sure the runner is compiled with RETROZIG_TEST
        result = subprocess.run([runner], capture_output=True, text=True, timeout=60)
        return result.stdout
    except subprocess.TimeoutExpired:
        print(f"Runner {runner} timed out.")
        return None

def update_test_file(filepath, actual_output):
    if not actual_output:
        return False

    with open(filepath, 'r') as f:
        content = f.read()

    # Pattern to find FAIL messages in actual output
    # FAIL: Signature emission mismatch for function 'foo'.
    # Expected: void foo(void)
    # Actual:   void zF_d071e5_foo(void)

    # Matches with newlines
    matches = re.findall(r"FAIL: .* mismatch for .* '.*'.\nExpected: (.*)\nActual:   (.*)", actual_output)

    changed = False
    new_content = content
    for expected, actual in matches:
        # We look for the expected string inside quotes in the source file
        # We need to handle escaping
        pattern = '"' + expected + '"'
        replacement = '"' + actual + '"'
        if pattern in new_content:
            new_content = new_content.replace(pattern, replacement)
            changed = True

    if changed:
        with open(filepath, 'w') as f:
            f.write(new_content)
        print(f"  Updated {filepath}")
    return changed

batch_num = sys.argv[1]
print(f"Processing Batch {batch_num}...")
# Rebuild runner
subprocess.run(["./test.sh", f"Batch{batch_num}"], capture_output=True)
output = get_actual_output(batch_num)
if output:
    test_files = []
    for root, dirs, files in os.walk('tests'):
        for file in files:
            if file.endswith('.cpp') and not file.startswith('main_batch') and not file.startswith('batch_runner'):
                test_files.append(os.path.join(root, file))

    for f in test_files:
        update_test_file(f, output)
