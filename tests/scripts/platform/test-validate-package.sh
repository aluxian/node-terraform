#!/bin/bash

# Test script for scripts/platform/validate-package.sh

set -euo pipefail

# Source test helpers
source "$(dirname "$0")/../helpers/test-helpers.sh"

# Test setup
setup_test_env

SCRIPT_PATH="$PROJECT_ROOT/scripts/platform/validate-package.sh"

test_info "Testing validate-package.sh"

# Verify script exists
validate_script_exists "$SCRIPT_PATH" || exit 1

# Test 1: Invalid arguments
test_info "Test 1: Invalid arguments handling"

output=$(capture_output "$SCRIPT_PATH")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with no arguments"
assert_contains "$output" "Error: Missing required arguments" "Should show error message"

# Test 2: Help usage
test_info "Test 2: Help flag and usage"

output=$(capture_output "$SCRIPT_PATH" --help 2>&1 || true)
# Even if it doesn't support --help, should show usage when args are wrong

# Test 3: Invalid package name
test_info "Test 3: Invalid package name validation"

mkdir -p test-package
output=$(capture_output "$SCRIPT_PATH" "./test-package" "invalid-name" "linux" "terraform")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with invalid package name"
assert_contains "$output" "Invalid package name format" "Should show package name error"

# Test 4: Invalid platform
test_info "Test 4: Invalid platform validation"

output=$(capture_output "$SCRIPT_PATH" "./test-package" "@jahed/terraform-test" "invalid-platform" "terraform")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with invalid platform"
assert_contains "$output" "Unsupported platform" "Should show platform error"

# Test 5: Invalid binary name
test_info "Test 5: Invalid binary name validation"

output=$(capture_output "$SCRIPT_PATH" "./test-package" "@jahed/terraform-test" "linux" "invalid-binary")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with invalid binary name"
assert_contains "$output" "Invalid binary name" "Should show binary name error"

# Test 6: Missing package directory
test_info "Test 6: Missing package directory handling"

output=$(capture_output "$SCRIPT_PATH" "./nonexistent" "@jahed/terraform-test" "linux" "terraform")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with missing directory"
assert_contains "$output" "Package directory does not exist" "Should show directory error"

# Test 7: Missing required files
test_info "Test 7: Missing required files validation"

empty_package="empty-package"
mkdir -p "$empty_package"

output=$(capture_output "$SCRIPT_PATH" "./$empty_package" "@jahed/terraform-test" "linux" "terraform")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with missing files"
assert_contains "$output" "Required file missing" "Should show missing files error"

# Test 8: Valid package validation (success case)
test_info "Test 8: Valid package validation"

# Create a complete valid package
valid_package="valid-package"
mkdir -p "$valid_package/bin"

# Create mock binary
create_mock_terraform_binary "$valid_package/bin/terraform" "1.13.1"

# Create valid package.json
create_mock_package_json "$valid_package/package.json" "@jahed/terraform-linux-x64" "1.13.1" "linux" "x64"

# Create README.md
cat > "$valid_package/README.md" << 'EOF'
# @jahed/terraform-linux-x64

This package contains the Terraform binary for Linux x64.

## Platform Support
- OS: Linux
- Architecture: x64

## Usage
Install via the main package.

## License
MIT
EOF

# Validate the package
output=$(capture_output "$SCRIPT_PATH" "./$valid_package" "@jahed/terraform-linux-x64" "linux" "terraform")
exit_code=$?
assert_equals 0 "$exit_code" "Should pass validation for valid package"
assert_contains "$output" "Package validation PASSED" "Should show success message"

# Test 9: Invalid package.json content
test_info "Test 9: Invalid package.json validation"

invalid_json_package="invalid-json-package"
mkdir -p "$invalid_json_package/bin"

# Create mock binary
create_mock_terraform_binary "$invalid_json_package/bin/terraform"

# Create invalid JSON
echo "{ invalid json }" > "$invalid_json_package/package.json"

# Create minimal README
echo "# Test README" > "$invalid_json_package/README.md"

output=$(capture_output "$SCRIPT_PATH" "./$invalid_json_package" "@jahed/terraform-test" "linux" "terraform")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with invalid JSON"
assert_contains "$output" "not valid JSON" "Should detect invalid JSON"

# Test 10: Package name mismatch
test_info "Test 10: Package name mismatch detection"

mismatch_package="mismatch-package"
mkdir -p "$mismatch_package/bin"

# Create mock binary
create_mock_terraform_binary "$mismatch_package/bin/terraform"

# Create package.json with wrong name
create_mock_package_json "$mismatch_package/package.json" "@jahed/terraform-wrong-name" "1.13.1" "linux" "x64"

# Create README
echo "# Test README" > "$mismatch_package/README.md"

output=$(capture_output "$SCRIPT_PATH" "./$mismatch_package" "@jahed/terraform-expected-name" "linux" "terraform")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with name mismatch"
assert_contains "$output" "package.json name mismatch" "Should detect name mismatch"

# Test 11: Missing binary file
test_info "Test 11: Missing binary file detection"

no_binary_package="no-binary-package"
mkdir -p "$no_binary_package/bin"

# Create valid package.json and README but no binary
create_mock_package_json "$no_binary_package/package.json" "@jahed/terraform-no-binary" "1.13.1" "linux" "x64"
echo "# Test README" > "$no_binary_package/README.md"

output=$(capture_output "$SCRIPT_PATH" "./$no_binary_package" "@jahed/terraform-no-binary" "linux" "terraform")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with missing binary"
assert_contains "$output" "Binary file not found" "Should detect missing binary"

# Test 12: Non-executable binary (Unix systems)
test_info "Test 12: Non-executable binary detection"

non_exec_package="non-exec-package"
mkdir -p "$non_exec_package/bin"

# Create non-executable binary
echo "fake binary" > "$non_exec_package/bin/terraform"
# Don't make it executable

create_mock_package_json "$non_exec_package/package.json" "@jahed/terraform-non-exec" "1.13.1" "linux" "x64"
echo "# Test README" > "$non_exec_package/README.md"

output=$(capture_output "$SCRIPT_PATH" "./$non_exec_package" "@jahed/terraform-non-exec" "linux" "terraform")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with non-executable binary"
assert_contains "$output" "Binary is not executable" "Should detect non-executable binary"

# Test 13: Windows platform (no executable check)
test_info "Test 13: Windows platform handling"

windows_package="windows-package"
mkdir -p "$windows_package/bin"

# Create Windows binary (no chmod needed)
echo "fake windows binary" > "$windows_package/bin/terraform.exe"

create_mock_package_json "$windows_package/package.json" "@jahed/terraform-win32-x64" "1.13.1" "win32" "x64"
echo "# Test README" > "$windows_package/README.md"

output=$(capture_output "$SCRIPT_PATH" "./$windows_package" "@jahed/terraform-win32-x64" "win32" "terraform.exe")
exit_code=$?
# Should pass because Windows doesn't check executable permissions
if [[ $exit_code -eq 0 ]]; then
  test_success "Windows platform validation should pass without executable check"
else
  # May fail for other reasons, but not executable permissions
  assert_not_contains "$output" "Binary is not executable" "Should not check executable for Windows"
fi

# Test 14: Package.json required fields validation
test_info "Test 14: Required fields validation"

missing_fields_package="missing-fields-package"
mkdir -p "$missing_fields_package/bin"

create_mock_terraform_binary "$missing_fields_package/bin/terraform"

# Create package.json missing required fields
cat > "$missing_fields_package/package.json" << 'EOF'
{
  "name": "@jahed/terraform-missing-fields",
  "version": "1.13.1"
}
EOF

echo "# Test README" > "$missing_fields_package/README.md"

output=$(capture_output "$SCRIPT_PATH" "./$missing_fields_package" "@jahed/terraform-missing-fields" "linux" "terraform")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with missing required fields"
assert_contains "$output" "Missing required field" "Should detect missing fields"

# Test 15: Unexpected files detection
test_info "Test 15: Unexpected files detection"

unexpected_files_package="unexpected-files-package"
mkdir -p "$unexpected_files_package/bin"

create_mock_terraform_binary "$unexpected_files_package/bin/terraform"
create_mock_package_json "$unexpected_files_package/package.json" "@jahed/terraform-unexpected" "1.13.1" "linux" "x64"
echo "# Test README" > "$unexpected_files_package/README.md"

# Add some unexpected files
echo "secret" > "$unexpected_files_package/secret.key"
echo "log data" > "$unexpected_files_package/debug.log"

output=$(capture_output "$SCRIPT_PATH" "./$unexpected_files_package" "@jahed/terraform-unexpected" "linux" "terraform")
# This should still pass validation but show warnings
assert_contains "$output" "Unexpected files found" "Should warn about unexpected files"

# Summary
report_test_results "validate-package.sh"