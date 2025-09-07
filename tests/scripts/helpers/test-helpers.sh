#!/bin/bash

# Common test helper functions and utilities
# Source this file in test scripts: source "$(dirname "$0")/../helpers/test-helpers.sh"

# Test framework globals
TEST_TEMP_DIR=""
TEST_FAILURES=0
TEST_SUCCESSES=0

# Colors (only if terminal supports it)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
fi

# Logging functions
test_info() {
  echo -e "${BLUE}[INFO]${NC} $1" >&2
}

test_success() {
  echo -e "${GREEN}[PASS]${NC} $1" >&2
  TEST_SUCCESSES=$((TEST_SUCCESSES + 1))
}

test_error() {
  echo -e "${RED}[FAIL]${NC} $1" >&2
  TEST_FAILURES=$((TEST_FAILURES + 1))
}

test_warning() {
  echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

# Test assertions
assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Values should be equal}"
  
  if [[ "$expected" == "$actual" ]]; then
    test_success "$message (expected: '$expected', actual: '$actual')"
  else
    test_error "$message (expected: '$expected', actual: '$actual')"
    return 1
  fi
}

assert_not_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Values should not be equal}"
  
  if [[ "$expected" != "$actual" ]]; then
    test_success "$message"
  else
    test_error "$message (both values: '$expected')"
    return 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-String should contain substring}"
  
  if [[ "$haystack" == *"$needle"* ]]; then
    test_success "$message"
  else
    test_error "$message (haystack: '$haystack', needle: '$needle')"
    return 1
  fi
}

assert_file_exists() {
  local file_path="$1"
  local message="${2:-File should exist}"
  
  if [[ -f "$file_path" ]]; then
    test_success "$message: $file_path"
  else
    test_error "$message: $file_path"
    return 1
  fi
}

assert_file_not_exists() {
  local file_path="$1"
  local message="${2:-File should not exist}"
  
  if [[ ! -f "$file_path" ]]; then
    test_success "$message: $file_path"
  else
    test_error "$message: $file_path"
    return 1
  fi
}

assert_dir_exists() {
  local dir_path="$1"
  local message="${2:-Directory should exist}"
  
  if [[ -d "$dir_path" ]]; then
    test_success "$message: $dir_path"
  else
    test_error "$message: $dir_path"
    return 1
  fi
}

assert_executable() {
  local file_path="$1"
  local message="${2:-File should be executable}"
  
  if [[ -x "$file_path" ]]; then
    test_success "$message: $file_path"
  else
    test_error "$message: $file_path"
    return 1
  fi
}

assert_exit_code() {
  local expected_code="$1"
  local actual_code="$2"
  local message="${3:-Exit code should match}"
  
  if [[ "$expected_code" -eq "$actual_code" ]]; then
    test_success "$message (exit code: $actual_code)"
  else
    test_error "$message (expected: $expected_code, actual: $actual_code)"
    return 1
  fi
}

assert_json_valid() {
  local json_file="$1"
  local message="${2:-JSON should be valid}"
  
  if jq . "$json_file" >/dev/null 2>&1; then
    test_success "$message: $json_file"
  else
    test_error "$message: $json_file"
    return 1
  fi
}

# Test environment setup
setup_test_env() {
  # Create temporary directory
  TEST_TEMP_DIR=$(mktemp -d)
  test_info "Test temp directory: $TEST_TEMP_DIR"
  
  # Ensure cleanup happens
  trap cleanup_test_env EXIT
  
  # Change to temp directory
  cd "$TEST_TEMP_DIR"
}

cleanup_test_env() {
  if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
    if [[ "${KEEP_TEMP_DIRS:-false}" == "true" ]]; then
      test_info "Keeping temp directory for debugging: $TEST_TEMP_DIR"
    else
      rm -rf "$TEST_TEMP_DIR"
    fi
  fi
}

# Mock helpers
create_mock_terraform_binary() {
  local binary_path="$1"
  local version="${2:-1.13.1}"
  
  mkdir -p "$(dirname "$binary_path")"
  
  cat > "$binary_path" << EOF
#!/bin/bash
case "\$1" in
  version|--version|-version)
    echo "Terraform v$version"
    ;;
  *)
    echo "Mock terraform called with: \$*"
    ;;
esac
EOF
  
  chmod +x "$binary_path"
}

create_mock_package_json() {
  local file_path="$1"
  local name="${2:-@aluxian/terraform-test}"
  local version="${3:-1.13.1}"
  local platform="${4:-linux}"
  local arch="${5:-x64}"
  
  mkdir -p "$(dirname "$file_path")"
  
  cat > "$file_path" << EOF
{
  "name": "$name",
  "version": "$version",
  "description": "Mock terraform package for $platform $arch",
  "license": "MIT",
  "os": ["$platform"],
  "cpu": ["$arch"],
  "files": ["bin"],
  "engines": {
    "node": ">=16.0.0"
  }
}
EOF
}

create_mock_terraform_zip() {
  local zip_path="$1"
  local binary_name="${2:-terraform}"
  local version="${3:-1.13.1}"
  
  local temp_dir
  temp_dir=$(mktemp -d)
  
  # Create mock binary
  create_mock_terraform_binary "$temp_dir/$binary_name" "$version"
  
  # Create zip
  (cd "$temp_dir" && zip -q "$zip_path" "$binary_name")
  
  rm -rf "$temp_dir"
}

# HTTP mocking (basic)
setup_mock_http() {
  # Set environment variables to use mock URLs
  export TERRAFORM_BASE_URL="file://$TEST_TEMP_DIR/mock-releases"
  mkdir -p "$TEST_TEMP_DIR/mock-releases/1.13.1"
}

create_mock_terraform_release() {
  local version="$1"
  local platform="$2"
  
  local releases_dir="$TEST_TEMP_DIR/mock-releases/$version"
  mkdir -p "$releases_dir"
  
  # Create mock zip
  create_mock_terraform_zip "$releases_dir/terraform_${version}_${platform}.zip" \
    "$(if [[ "$platform" == windows_* ]]; then echo "terraform.exe"; else echo "terraform"; fi)" \
    "$version"
  
  # Create mock checksums
  (cd "$releases_dir" && sha256sum "terraform_${version}_${platform}.zip" > "terraform_${version}_SHA256SUMS")
}

# Test result reporting
report_test_results() {
  local test_name="${1:-Unknown Test}"
  
  echo ""
  test_info "Test Results for: $test_name"
  test_info "================================"
  test_info "Successes: $TEST_SUCCESSES"
  
  if [[ $TEST_FAILURES -gt 0 ]]; then
    test_error "Failures: $TEST_FAILURES"
    return 1
  else
    test_success "All assertions passed!"
    return 0
  fi
}

# Utility functions
run_script() {
  local script_path="$1"
  shift
  
  bash "$script_path" "$@"
}

capture_output() {
  local command=("$@")
  local output
  local exit_code
  
  output=$("${command[@]}" 2>&1) || exit_code=$?
  echo "$output"
  return ${exit_code:-0}
}

# Validation helpers
validate_script_exists() {
  local script_path="$1"
  
  if [[ ! -f "$script_path" ]]; then
    test_error "Script not found: $script_path"
    return 1
  fi
  
  if [[ ! -x "$script_path" ]]; then
    test_error "Script not executable: $script_path"
    return 1
  fi
  
  test_success "Script exists and is executable: $script_path"
  return 0
}

# Check if all required tools are available
check_test_dependencies() {
  local missing_tools=()
  
  # Required tools
  for tool in jq curl zip unzip; do
    if ! command -v "$tool" >/dev/null; then
      missing_tools+=("$tool")
    fi
  done
  
  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    test_error "Missing required tools: ${missing_tools[*]}"
    return 1
  fi
  
  test_success "All test dependencies available"
  return 0
}