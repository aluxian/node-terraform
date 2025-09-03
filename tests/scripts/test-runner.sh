#!/bin/bash

# Test runner for all scripts
# Usage: test-runner.sh [test_pattern] [--verbose] [--fail-fast]
# Example: test-runner.sh platform --verbose

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TESTS_DIR="$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Options
VERBOSE=false
FAIL_FAST=false
TEST_PATTERN=""

# Functions
error() {
  echo -e "${RED}❌ Error: $1${NC}" >&2
}

warning() {
  echo -e "${YELLOW}⚠️  Warning: $1${NC}" >&2
}

success() {
  echo -e "${GREEN}✅ $1${NC}"
}

info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

usage() {
  cat << EOF
Usage: $0 [test_pattern] [options]

Runs tests for extracted scripts with optional filtering and reporting.

Arguments:
  test_pattern    Run only tests matching this pattern (optional)

Options:
  --verbose       Show detailed output from tests
  --fail-fast     Stop on first test failure
  --help          Show this help message

Examples:
  $0                    # Run all tests
  $0 platform           # Run only platform script tests
  $0 release --verbose  # Run release tests with verbose output
  $0 --fail-fast        # Stop on first failure

Test Structure:
  tests/scripts/
  ├── platform/         # Platform script tests
  ├── release/          # Release script tests
  ├── fixtures/         # Test fixtures and mock data
  └── helpers/          # Common test utilities

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose)
      VERBOSE=true
      shift
      ;;
    --fail-fast)
      FAIL_FAST=true
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    -*)
      error "Unknown option: $1"
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$TEST_PATTERN" ]]; then
        TEST_PATTERN="$1"
      else
        error "Multiple test patterns not supported"
        exit 1
      fi
      shift
      ;;
  esac
done

# Environment setup
export PROJECT_ROOT
export VERBOSE

cd "$PROJECT_ROOT"

info "Script Test Runner"
info "=================="
info "Project root: $PROJECT_ROOT"
info "Tests directory: $TESTS_DIR"
if [[ -n "$TEST_PATTERN" ]]; then
  info "Test pattern: $TEST_PATTERN"
fi
info "Verbose: $VERBOSE"
info "Fail fast: $FAIL_FAST"
echo ""

# Find test files
find_test_files() {
  local pattern="$1"
  local test_files=()
  
  # Look for test files in subdirectories
  while IFS= read -r -d '' file; do
    # Apply pattern filter if specified
    if [[ -n "$pattern" && ! "$file" =~ $pattern ]]; then
      continue
    fi
    test_files+=("$file")
  done < <(find "$TESTS_DIR" -name "test-*.sh" -type f -print0 | sort -z)
  
  printf '%s\n' "${test_files[@]}"
}

# Run a single test
run_test() {
  local test_file="$1"
  local test_name
  test_name=$(basename "$test_file" .sh)
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  info "Running test: $test_name"
  
  # Create isolated environment for test
  local test_env_vars=(
    "TEST_NAME=$test_name"
    "TEST_FILE=$test_file"
    "PROJECT_ROOT=$PROJECT_ROOT"
    "TESTS_DIR=$TESTS_DIR"
  )
  
  # Run test with timeout
  local start_time
  start_time=$(date +%s)
  
  if [[ "$VERBOSE" == "true" ]]; then
    if env "${test_env_vars[@]}" bash "$test_file"; then
      TESTS_PASSED=$((TESTS_PASSED + 1))
      local end_time
      end_time=$(date +%s)
      local duration=$((end_time - start_time))
      success "✓ $test_name (${duration}s)"
    else
      TESTS_FAILED=$((TESTS_FAILED + 1))
      FAILED_TESTS+=("$test_name")
      error "✗ $test_name"
      
      if [[ "$FAIL_FAST" == "true" ]]; then
        error "Stopping due to --fail-fast"
        return 1
      fi
    fi
  else
    # Capture output for non-verbose mode
    local output
    local exit_code=0
    
    output=$(env "${test_env_vars[@]}" bash "$test_file" 2>&1) || exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
      TESTS_PASSED=$((TESTS_PASSED + 1))
      local end_time
      end_time=$(date +%s)
      local duration=$((end_time - start_time))
      success "✓ $test_name (${duration}s)"
    else
      TESTS_FAILED=$((TESTS_FAILED + 1))
      FAILED_TESTS+=("$test_name")
      error "✗ $test_name"
      
      # Show test output on failure
      echo "Test output:"
      echo "$output"
      echo ""
      
      if [[ "$FAIL_FAST" == "true" ]]; then
        error "Stopping due to --fail-fast"
        return 1
      fi
    fi
  fi
  
  return 0
}

# Main execution
main() {
  # Find all test files
  local test_files=()
  while IFS= read -r file; do
    test_files+=("$file")
  done < <(find_test_files "$TEST_PATTERN")
  
  if [[ ${#test_files[@]} -eq 0 ]]; then
    warning "No test files found"
    if [[ -n "$TEST_PATTERN" ]]; then
      warning "Pattern '$TEST_PATTERN' didn't match any tests"
    fi
    exit 0
  fi
  
  info "Found ${#test_files[@]} test files"
  echo ""
  
  # Run all tests
  for test_file in "${test_files[@]}"; do
    if ! run_test "$test_file"; then
      # run_test handles fail-fast internally
      break
    fi
  done
  
  # Summary
  echo ""
  info "Test Summary"
  info "============"
  info "Tests run: $TESTS_RUN"
  success "Passed: $TESTS_PASSED"
  
  if [[ $TESTS_FAILED -gt 0 ]]; then
    error "Failed: $TESTS_FAILED"
    echo ""
    error "Failed tests:"
    for failed_test in "${FAILED_TESTS[@]}"; do
      error "  - $failed_test"
    done
    echo ""
    exit 1
  else
    success "All tests passed!"
  fi
}

# Check if we have any test files at all
if [[ ! -d "$TESTS_DIR" ]]; then
  error "Tests directory not found: $TESTS_DIR"
  exit 1
fi

main "$@"