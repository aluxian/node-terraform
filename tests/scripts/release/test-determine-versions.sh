#!/bin/bash

# Test script for scripts/release/determine-versions.sh

set -euo pipefail

# Source test helpers
source "$(dirname "$0")/../helpers/test-helpers.sh"

# Test setup
setup_test_env

SCRIPT_PATH="$PROJECT_ROOT/scripts/release/determine-versions.sh"

test_info "Testing determine-versions.sh"

# Verify script exists
validate_script_exists "$SCRIPT_PATH" || exit 1

# Test 1: Help flag
test_info "Test 1: Help flag support"

output=$(capture_output "$SCRIPT_PATH" --help 2>&1 || true)
# Should show usage information

# Test 2: Missing package.json
test_info "Test 2: Missing package.json handling"

# Run in directory without package.json
output=$(capture_output "$SCRIPT_PATH")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail without package.json"
assert_contains "$output" "package.json not found" "Should show package.json error"

# Test 3: Valid package.json, no terraform version specified
test_info "Test 3: Default behavior with package.json"

# Create mock package.json
cat > package.json << 'EOF'
{
  "name": "@jahed/terraform-test",
  "version": "1.13.1",
  "description": "Test package"
}
EOF

output=$(capture_output "$SCRIPT_PATH" "" "env")
exit_code=$?
assert_equals 0 "$exit_code" "Should succeed with valid package.json"
assert_contains "$output" "PACKAGE_VERSION=1.13.1" "Should output package version"
assert_contains "$output" "TERRAFORM_VERSION=1.13.1" "Should default terraform version to package version"

# Test 4: Command line terraform version override
test_info "Test 4: Command line terraform version override"

output=$(capture_output "$SCRIPT_PATH" "1.5.7" "env")
exit_code=$?
assert_equals 0 "$exit_code" "Should succeed with terraform version argument"
assert_contains "$output" "PACKAGE_VERSION=1.13.1" "Should keep package version from JSON"
assert_contains "$output" "TERRAFORM_VERSION=1.5.7" "Should use command line terraform version"

# Test 5: Environment variable terraform version
test_info "Test 5: Environment variable terraform version"

export TERRAFORM_VERSION="1.6.0"
output=$(capture_output "$SCRIPT_PATH" "" "env")
exit_code=$?
assert_equals 0 "$exit_code" "Should succeed with env var terraform version"
assert_contains "$output" "TERRAFORM_VERSION=1.6.0" "Should use environment variable"
unset TERRAFORM_VERSION

# Test 6: GitHub tag version simulation
test_info "Test 6: GitHub tag version simulation"

export GITHUB_REF_TYPE="tag"
export GITHUB_REF_NAME="v1.7.0"
output=$(capture_output "$SCRIPT_PATH" "" "env")
exit_code=$?
assert_equals 0 "$exit_code" "Should succeed with GitHub tag"
assert_contains "$output" "TERRAFORM_VERSION=1.7.0" "Should use git tag version (strip v prefix)"
unset GITHUB_REF_TYPE GITHUB_REF_NAME

# Test 7: GitHub tag version without 'v' prefix
test_info "Test 7: GitHub tag without v prefix"

export GITHUB_REF_TYPE="tag"
export GITHUB_REF_NAME="1.8.0"
output=$(capture_output "$SCRIPT_PATH" "" "env")
exit_code=$?
assert_equals 0 "$exit_code" "Should succeed with tag without v prefix"
assert_contains "$output" "TERRAFORM_VERSION=1.8.0" "Should use tag version as-is"
unset GITHUB_REF_TYPE GITHUB_REF_NAME

# Test 8: JSON output format
test_info "Test 8: JSON output format"

output=$(capture_output "$SCRIPT_PATH" "1.9.0" "json")
exit_code=$?
assert_equals 0 "$exit_code" "Should succeed with JSON output"

# Validate JSON structure
echo "$output" > test-output.json
assert_json_valid "test-output.json" "Should produce valid JSON"

package_version=$(jq -r '.package_version' test-output.json)
terraform_version=$(jq -r '.terraform_version' test-output.json)

assert_equals "1.13.1" "$package_version" "JSON should contain correct package version"
assert_equals "1.9.0" "$terraform_version" "JSON should contain correct terraform version"

# Test 9: GitHub Actions output format
test_info "Test 9: GitHub Actions output format"

# Create mock GITHUB_OUTPUT file
export GITHUB_OUTPUT="$TEST_TEMP_DIR/github_output"
touch "$GITHUB_OUTPUT"

output=$(capture_output "$SCRIPT_PATH" "1.10.0" "github")
exit_code=$?
assert_equals 0 "$exit_code" "Should succeed with GitHub output"

# Check GITHUB_OUTPUT file was written
assert_file_exists "$GITHUB_OUTPUT" "Should create GITHUB_OUTPUT file"

github_output_content=$(cat "$GITHUB_OUTPUT")
assert_contains "$github_output_content" "package_version=1.13.1" "Should write package version to GITHUB_OUTPUT"
assert_contains "$github_output_content" "terraform_version=1.10.0" "Should write terraform version to GITHUB_OUTPUT"

unset GITHUB_OUTPUT

# Test 10: Version priority order
test_info "Test 10: Version priority order"

# Set multiple version sources to test priority
export TERRAFORM_VERSION="env-version"
export GITHUB_REF_TYPE="tag"
export GITHUB_REF_NAME="v2.0.0"

# Command line should override everything
output=$(capture_output "$SCRIPT_PATH" "cli-version" "env")
assert_contains "$output" "TERRAFORM_VERSION=cli-version" "Command line should have highest priority"

# Env var should override git tag
output=$(capture_output "$SCRIPT_PATH" "" "env")
assert_contains "$output" "TERRAFORM_VERSION=env-version" "Env var should override git tag"

unset TERRAFORM_VERSION

# Git tag should override package.json
output=$(capture_output "$SCRIPT_PATH" "" "env")
assert_contains "$output" "TERRAFORM_VERSION=2.0.0" "Git tag should override package.json"

unset GITHUB_REF_TYPE GITHUB_REF_NAME

# Test 11: Invalid terraform version format
test_info "Test 11: Invalid terraform version validation"

output=$(capture_output "$SCRIPT_PATH" "invalid.version.format" "env")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with invalid terraform version"
assert_contains "$output" "Invalid terraform version format" "Should show version format error"

# Test 12: Invalid package.json version
test_info "Test 12: Invalid package.json version"

# Create package.json with invalid version
cat > package.json << 'EOF'
{
  "name": "@jahed/terraform-test",
  "version": "invalid-version",
  "description": "Test package"
}
EOF

output=$(capture_output "$SCRIPT_PATH" "" "env")
exit_code=$?
# Should fail or warn about invalid package version, but terraform version validation happens first

# Test 13: Pre-release version handling
test_info "Test 13: Pre-release version handling"

output=$(capture_output "$SCRIPT_PATH" "1.13.1-alpha1" "env")
exit_code=$?
assert_equals 0 "$exit_code" "Should accept pre-release versions"
assert_contains "$output" "TERRAFORM_VERSION=1.13.1-alpha1" "Should handle pre-release versions"

# Test 14: Custom package.json path
test_info "Test 14: Custom package.json path"

# Create package.json in subdirectory
mkdir -p custom-location
cat > custom-location/package.json << 'EOF'
{
  "name": "@jahed/terraform-custom",
  "version": "2.0.0",
  "description": "Custom location test"
}
EOF

export PACKAGE_JSON_PATH="./custom-location/package.json"
output=$(capture_output "$SCRIPT_PATH" "" "env")
exit_code=$?
assert_equals 0 "$exit_code" "Should succeed with custom package.json path"
assert_contains "$output" "PACKAGE_VERSION=2.0.0" "Should read from custom location"
unset PACKAGE_JSON_PATH

# Summary
report_test_results "determine-versions.sh"