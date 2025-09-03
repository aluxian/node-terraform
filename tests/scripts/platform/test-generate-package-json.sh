#!/bin/bash

# Test script for scripts/platform/generate-package-json.js

set -euo pipefail

# Source test helpers
source "$(dirname "$0")/../helpers/test-helpers.sh"

# Test setup
setup_test_env

SCRIPT_PATH="$PROJECT_ROOT/scripts/platform/generate-package-json.js"

test_info "Testing generate-package-json.js"

# Verify script exists
validate_script_exists "$SCRIPT_PATH" || exit 1

# Test 1: Invalid arguments
test_info "Test 1: Invalid arguments handling"

output=$(capture_output node "$SCRIPT_PATH")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with no arguments"
assert_contains "$output" "Error: Missing required arguments" "Should show error message"

# Test 2: Help flag
test_info "Test 2: Help flag support"

output=$(capture_output node "$SCRIPT_PATH" --help)
exit_code=$?
assert_equals 0 "$exit_code" "Should succeed with --help"
assert_contains "$output" "Usage:" "Should show usage with --help"
assert_contains "$output" "Examples:" "Should show examples with --help"

# Test 3: Invalid package name format
test_info "Test 3: Invalid package name validation"

mkdir -p test-package
output=$(capture_output node "$SCRIPT_PATH" "invalid-name" "1.13.1" "darwin" "arm64" "./test-package")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with invalid package name"
assert_contains "$output" "Invalid package name format" "Should show package name error"

# Test 4: Invalid version format
test_info "Test 4: Invalid version validation"

mkdir -p test-package
output=$(capture_output node "$SCRIPT_PATH" "@jahed/terraform-test" "invalid" "darwin" "arm64" "./test-package")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with invalid version"
assert_contains "$output" "Invalid semantic version format" "Should show version error"

# Test 5: Invalid platform
test_info "Test 5: Invalid platform validation"

mkdir -p test-package
output=$(capture_output node "$SCRIPT_PATH" "@jahed/terraform-test" "1.13.1" "invalid" "arm64" "./test-package")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with invalid platform"
assert_contains "$output" "Invalid platform" "Should show platform error"

# Test 6: Invalid architecture
test_info "Test 6: Invalid architecture validation"

mkdir -p test-package
output=$(capture_output node "$SCRIPT_PATH" "@jahed/terraform-test" "1.13.1" "darwin" "invalid" "./test-package")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with invalid architecture"
assert_contains "$output" "Invalid npm architecture" "Should show architecture error"

# Test 7: Missing package directory
test_info "Test 7: Missing package directory handling"

output=$(capture_output node "$SCRIPT_PATH" "@jahed/terraform-test" "1.13.1" "darwin" "arm64" "./nonexistent")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with nonexistent directory"
assert_contains "$output" "Package directory does not exist" "Should show directory error"

# Test 8: Successful package.json generation
test_info "Test 8: Successful package.json generation"

test_package_dir="test-package-success"
mkdir -p "$test_package_dir"

output=$(capture_output node "$SCRIPT_PATH" "@jahed/terraform-darwin-arm64" "1.13.1" "darwin" "arm64" "./$test_package_dir")
exit_code=$?
assert_equals 0 "$exit_code" "Should succeed with valid arguments"
assert_contains "$output" "Generated package.json" "Should show success message"

# Verify generated file
package_json_path="$test_package_dir/package.json"
assert_file_exists "$package_json_path" "Should create package.json file"
assert_json_valid "$package_json_path" "Generated package.json should be valid JSON"

# Test JSON content
test_info "Test 8a: Verify generated JSON content"

name=$(jq -r '.name' "$package_json_path")
version=$(jq -r '.version' "$package_json_path")
platform=$(jq -r '.os[0]' "$package_json_path")
arch=$(jq -r '.cpu[0]' "$package_json_path")

assert_equals "@jahed/terraform-darwin-arm64" "$name" "Package name should match"
assert_equals "1.13.1" "$version" "Package version should match"
assert_equals "darwin" "$platform" "Platform should match"
assert_equals "arm64" "$arch" "Architecture should match"

# Test required fields
required_fields=("name" "version" "description" "license" "os" "cpu" "files" "engines")
for field in "${required_fields[@]}"; do
  if jq -e ".$field" "$package_json_path" >/dev/null; then
    test_success "Required field exists: $field"
  else
    test_error "Missing required field: $field"
  fi
done

# Test 9: Different platforms and architectures
test_info "Test 9: Different platform combinations"

platforms=("linux:x64" "win32:x64" "freebsd:x64")

for combo in "${platforms[@]}"; do
  IFS=':' read -r test_platform test_arch <<< "$combo"
  
  test_dir="test-$test_platform-$test_arch"
  mkdir -p "$test_dir"
  
  output=$(capture_output node "$SCRIPT_PATH" "@jahed/terraform-$test_platform-$test_arch" "1.13.1" "$test_platform" "$test_arch" "./$test_dir")
  exit_code=$?
  assert_equals 0 "$exit_code" "Should succeed for $test_platform $test_arch"
  
  # Verify platform-specific content
  generated_json="$test_dir/package.json"
  actual_platform=$(jq -r '.os[0]' "$generated_json")
  actual_arch=$(jq -r '.cpu[0]' "$generated_json")
  
  assert_equals "$test_platform" "$actual_platform" "Platform should match for $combo"
  assert_equals "$test_arch" "$actual_arch" "Architecture should match for $combo"
done

# Test 10: Environment variable overrides
test_info "Test 10: Environment variable overrides"

test_dir="test-env-vars"
mkdir -p "$test_dir"

export AUTHOR="Test Author <test@example.com>"
export REPOSITORY="https://github.com/test/repo"
export HOMEPAGE="https://test.example.com"

output=$(capture_output node "$SCRIPT_PATH" "@jahed/terraform-test" "1.13.1" "linux" "x64" "./$test_dir")
exit_code=$?
assert_equals 0 "$exit_code" "Should succeed with environment variables"

# Verify environment variables were used
generated_json="$test_dir/package.json"
actual_author=$(jq -r '.author' "$generated_json")
actual_repo=$(jq -r '.repository' "$generated_json")
actual_homepage=$(jq -r '.homepage' "$generated_json")

assert_equals "Test Author <test@example.com>" "$actual_author" "Should use AUTHOR env var"
assert_equals "https://github.com/test/repo" "$actual_repo" "Should use REPOSITORY env var"
assert_equals "https://test.example.com" "$actual_homepage" "Should use HOMEPAGE env var"

# Test 11: Package validation
test_info "Test 11: Package validation features"

test_dir="test-validation"
mkdir -p "$test_dir"

# Generate a package and verify validation catches issues
node "$SCRIPT_PATH" "@jahed/terraform-validation-test" "1.13.1" "linux" "x64" "./$test_dir"

# Manually corrupt the JSON to test validation
echo "invalid json" > "$test_dir/package.json"

# Test that validation catches the corruption
output=$(capture_output node "$SCRIPT_PATH" "@jahed/terraform-validation-test" "1.13.1" "linux" "x64" "./$test_dir")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail validation with corrupted JSON"

# Test 12: Keywords and metadata
test_info "Test 12: Keywords and metadata verification"

test_dir="test-metadata"
mkdir -p "$test_dir"

node "$SCRIPT_PATH" "@jahed/terraform-metadata-test" "1.13.1" "darwin" "arm64" "./$test_dir"
generated_json="$test_dir/package.json"

# Check that keywords include expected values
keywords=$(jq -r '.keywords | join(",")' "$generated_json")
assert_contains "$keywords" "terraform" "Should include terraform keyword"
assert_contains "$keywords" "darwin" "Should include platform in keywords"
assert_contains "$keywords" "arm64" "Should include architecture in keywords"
assert_contains "$keywords" "binary" "Should include binary keyword"

# Check engines field
node_version=$(jq -r '.engines.node' "$generated_json")
assert_contains "$node_version" "16" "Should specify Node.js 16+ requirement"

# Test 13: Files array
test_info "Test 13: Files array verification"

files=$(jq -r '.files | join(",")' "$generated_json")
assert_contains "$files" "bin" "Should include bin in files array"

# Clean up environment variables
unset AUTHOR REPOSITORY HOMEPAGE

# Summary
report_test_results "generate-package-json.js"