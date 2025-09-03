#!/bin/bash

# Test script for scripts/release/verify-package-integrity.sh

set -euo pipefail

# Source test helpers
source "$(dirname "$0")/../helpers/test-helpers.sh"

# Test setup
setup_test_env

SCRIPT_PATH="$PROJECT_ROOT/scripts/release/verify-package-integrity.sh"

test_info "Testing verify-package-integrity.sh"

# Verify script exists
validate_script_exists "$SCRIPT_PATH" || exit 1

# Test 1: Missing arguments
test_info "Test 1: Missing arguments handling"

output=$(capture_output "$SCRIPT_PATH")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with no arguments"
assert_contains "$output" "Missing required arguments" "Should show error message"

# Test 2: Non-existent tarball
test_info "Test 2: Non-existent tarball handling"

output=$(capture_output "$SCRIPT_PATH" "./nonexistent.tgz")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with non-existent tarball"
assert_contains "$output" "Tarball file does not exist" "Should show file error"

# Test 3: Invalid tarball
test_info "Test 3: Invalid tarball handling"

echo "not a tarball" > invalid.tgz
output=$(capture_output "$SCRIPT_PATH" "./invalid.tgz")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with invalid tarball"
assert_contains "$output" "Tarball is invalid\|corrupted" "Should detect invalid tarball"

# Test 4: Valid tarball creation and verification
test_info "Test 4: Valid tarball verification"

# Create a valid package structure
mkdir -p test-package/{bin,lib}
create_mock_terraform_binary "test-package/bin/terraform"

# Create valid package.json with optionalDependencies
cat > test-package/package.json << 'EOF'
{
  "name": "@jahed/terraform",
  "version": "1.13.1",
  "description": "Terraform wrapper",
  "license": "MIT",
  "files": ["bin", "lib"],
  "engines": {"node": ">=16.0.0"},
  "optionalDependencies": {
    "@jahed/terraform-darwin-arm64": "1.13.1",
    "@jahed/terraform-linux-x64": "1.13.1"
  }
}
EOF

echo "Mock library file" > test-package/lib/index.js

# Create tarball in npm package format
mkdir package
cp -r test-package/* package/
tar -czf test-package.tgz package/

# Test successful verification
output=$(capture_output "$SCRIPT_PATH" "./test-package.tgz" "1.13.1")
exit_code=$?
assert_equals 0 "$exit_code" "Should pass verification for valid tarball"
assert_contains "$output" "Package integrity verification PASSED" "Should show success message"

# Test 5: Missing package.json in tarball
test_info "Test 5: Missing package.json detection"

mkdir -p broken-package/package/bin
echo "binary" > broken-package/package/bin/terraform
# No package.json
tar -czf broken-package.tgz -C broken-package package/

output=$(capture_output "$SCRIPT_PATH" "./broken-package.tgz")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail without package.json"
assert_contains "$output" "package.json not found" "Should detect missing package.json"

# Test 6: Invalid JSON in package.json
test_info "Test 6: Invalid JSON detection"

mkdir -p invalid-json-package/package
echo "{ invalid json" > invalid-json-package/package/package.json
tar -czf invalid-json-package.tgz -C invalid-json-package package/

output=$(capture_output "$SCRIPT_PATH" "./invalid-json-package.tgz")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with invalid JSON"
assert_contains "$output" "not valid JSON" "Should detect invalid JSON"

# Test 7: Missing required fields
test_info "Test 7: Missing required fields detection"

mkdir -p missing-fields-package/package
cat > missing-fields-package/package/package.json << 'EOF'
{
  "name": "@jahed/terraform",
  "version": "1.13.1"
}
EOF
tar -czf missing-fields-package.tgz -C missing-fields-package package/

output=$(capture_output "$SCRIPT_PATH" "./missing-fields-package.tgz")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with missing required fields"
assert_contains "$output" "missing required field" "Should detect missing fields"

# Test 8: Version mismatch detection
test_info "Test 8: Version mismatch detection"

# Use the valid tarball but check against wrong version
output=$(capture_output "$SCRIPT_PATH" "./test-package.tgz" "1.5.0")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with version mismatch"
assert_contains "$output" "Version mismatch\|expected 1.5.0.*got 1.13.1" "Should detect version mismatch"

# Test 9: Missing optionalDependencies platform packages
test_info "Test 9: Missing platform packages detection"

mkdir -p no-platforms-package/package/bin
create_mock_terraform_binary "no-platforms-package/package/bin/terraform"
cat > no-platforms-package/package/package.json << 'EOF'
{
  "name": "@jahed/terraform",
  "version": "1.13.1",
  "description": "Test",
  "license": "MIT",
  "files": ["bin"],
  "engines": {"node": ">=16.0.0"},
  "optionalDependencies": {}
}
EOF
tar -czf no-platforms-package.tgz -C no-platforms-package package/

output=$(capture_output "$SCRIPT_PATH" "./no-platforms-package.tgz")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail without platform packages"
assert_contains "$output" "Missing expected package" "Should detect missing platform packages"

# Test 10: Files field validation
test_info "Test 10: Files field validation"

# Create package with files that don't exist
mkdir -p bad-files-package/package/bin
create_mock_terraform_binary "bad-files-package/package/bin/terraform"
cat > bad-files-package/package/package.json << 'EOF'
{
  "name": "@jahed/terraform",
  "version": "1.13.1",
  "description": "Test",
  "license": "MIT",
  "files": ["bin", "nonexistent"],
  "engines": {"node": ">=16.0.0"},
  "optionalDependencies": {
    "@jahed/terraform-linux-x64": "1.13.1"
  }
}
EOF
tar -czf bad-files-package.tgz -C bad-files-package package/

output=$(capture_output "$SCRIPT_PATH" "./bad-files-package.tgz")
exit_code=$?
assert_not_equals 0 "$exit_code" "Should fail with missing files"
assert_contains "$output" "No files found for pattern" "Should detect missing files"

# Summary
report_test_results "verify-package-integrity.sh"