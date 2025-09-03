#!/bin/bash

# Test script for scripts/platform/download-terraform.sh

set -euo pipefail

# Source test helpers
source "$(dirname "$0")/../helpers/test-helpers.sh"

# Test setup
setup_test_env

SCRIPT_PATH="$PROJECT_ROOT/scripts/platform/download-terraform.sh"

test_info "Testing download-terraform.sh"

# Verify script exists
validate_script_exists "$SCRIPT_PATH" || exit 1

# Test 1: Invalid arguments
test_info "Test 1: Invalid arguments handling"

output=$(capture_output "$SCRIPT_PATH")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with no arguments"
assert_contains "$output" "Error: Missing required arguments" "Should show error message"

# Test 2: Invalid version format
test_info "Test 2: Invalid version format"

output=$(capture_output "$SCRIPT_PATH" "invalid.version" "linux_amd64")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with invalid version"
assert_contains "$output" "Invalid Terraform version format" "Should show version error"

# Test 3: Invalid architecture format
test_info "Test 3: Invalid architecture format"

output=$(capture_output "$SCRIPT_PATH" "1.13.1" "invalid-arch")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with invalid architecture"
assert_contains "$output" "Invalid Terraform architecture format" "Should show arch error"

# Test 4: Help usage
test_info "Test 4: Help usage"

# Test usage output when no args provided
output=$(capture_output "$SCRIPT_PATH")
assert_contains "$output" "Usage:" "Should show usage when no arguments"
assert_contains "$output" "Examples:" "Should show examples in usage"

# Test 5: Mock successful download (with mocked URLs)
test_info "Test 5: Mock successful download"

# Setup mock HTTP environment
setup_mock_http
create_mock_terraform_release "1.13.1" "linux_amd64"

# Set environment to skip real HTTP and use file:// URLs
export SKIP_CHECKSUM_VERIFICATION="true"
export TERRAFORM_BASE_URL="file://$TEST_TEMP_DIR/mock-releases"

# Test with our mock environment
downloads_dir="$TEST_TEMP_DIR/downloads"
output=$(capture_output "$SCRIPT_PATH" "1.13.1" "linux_amd64" "$downloads_dir")
exit_code=$?

# For this test, we expect it to fail because file:// URLs don't work with curl
# But we can test the argument parsing and initial validation
assert_contains "$output" "Downloading Terraform 1.13.1 for linux_amd64" "Should show download message"

# Test 6: Directory creation
test_info "Test 6: Output directory creation"

custom_dir="$TEST_TEMP_DIR/custom-output"
# The script should create the directory, but will fail on download
output=$(capture_output "$SCRIPT_PATH" "1.13.1" "linux_amd64" "$custom_dir")

# Directory should be created even if download fails
assert_dir_exists "$custom_dir" "Should create output directory"

# Test 7: Environment variable handling
test_info "Test 7: Environment variable handling"

export SKIP_CHECKSUM_VERIFICATION="true"
output=$(capture_output "$SCRIPT_PATH" "1.13.1" "linux_amd64" "./test-downloads")

assert_contains "$output" "Skipping checksum verification" "Should respect SKIP_CHECKSUM_VERIFICATION"

# Test 8: Platform-specific binary names
test_info "Test 8: Platform-specific binary name detection"

# Test Windows platform
windows_dir="$TEST_TEMP_DIR/windows-test"
output=$(capture_output "$SCRIPT_PATH" "1.13.1" "windows_amd64" "$windows_dir")

# Should mention terraform.exe for Windows
assert_contains "$output" "terraform.exe\|Binary location.*terraform.exe" "Should reference terraform.exe for Windows"

# Test 9: Version validation edge cases
test_info "Test 9: Version validation edge cases"

# Test pre-release version
output=$(capture_output "$SCRIPT_PATH" "1.13.1-alpha1" "linux_amd64")
exit_code=$?
# Pre-release versions should be valid
assert_contains "$output" "Downloading Terraform 1.13.1-alpha1" "Should accept pre-release versions"

# Test 10: Script help flag (if implemented)
test_info "Test 10: Help flag support"

# Many scripts support --help
if "$SCRIPT_PATH" --help 2>/dev/null | grep -q "Usage:"; then
  test_success "Script supports --help flag"
else
  test_warning "Script doesn't support --help flag (optional)"
fi

# Summary
report_test_results "download-terraform.sh"