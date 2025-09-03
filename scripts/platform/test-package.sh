#!/bin/bash

# Test platform package installability and basic functionality
# Usage: test-package.sh <package_dir> [test_type]
# Example: test-package.sh ./platform-packages/@jahed/terraform-darwin-arm64 full

set -euo pipefail

# Function to show usage
usage() {
  cat << EOF
Usage: $0 <package_dir> [test_type]

Tests the installability and basic functionality of a platform-specific npm package.

Arguments:
  package_dir  Path to the package directory containing package.json
  test_type    Type of test to run (default: basic)
               - basic: npm pack dry-run only
               - full: npm pack + install test in temp directory
               - smoke: basic + binary execution test

Examples:
  $0 ./platform-packages/@jahed/terraform-darwin-arm64
  $0 ./platform-packages/@jahed/terraform-linux-x64 full
  $0 ./packages/win32-x64 smoke

Test Types:
  basic   - Validates package can be packed (quick, safe)
  full    - Creates actual tarball and tests installation
  smoke   - Includes binary execution test (may fail for cross-platform)

Environment Variables:
  SKIP_BINARY_TEST  Set to 'true' to skip binary execution tests
  TEST_TIMEOUT      Timeout for tests in seconds (default: 30)
EOF
}

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Validate arguments
if [[ $# -lt 1 ]]; then
  error "Missing required arguments"
  usage >&2
  exit 1
fi

PACKAGE_DIR="$1"
TEST_TYPE="${2:-basic}"

# Environment variables
SKIP_BINARY_TEST="${SKIP_BINARY_TEST:-false}"
TEST_TIMEOUT="${TEST_TIMEOUT:-30}"

# Validate package directory
if [[ ! -d "$PACKAGE_DIR" ]]; then
  error "Package directory does not exist: $PACKAGE_DIR"
  exit 1
fi

if [[ ! -f "$PACKAGE_DIR/package.json" ]]; then
  error "package.json not found in $PACKAGE_DIR"
  exit 1
fi

# Validate test type
case "$TEST_TYPE" in
  basic|full|smoke)
    ;;
  *)
    error "Invalid test type: $TEST_TYPE"
    echo "Valid types: basic, full, smoke" >&2
    exit 1
    ;;
esac

cd "$PACKAGE_DIR"

# Get package info
PACKAGE_NAME=$(jq -r '.name' package.json)
PACKAGE_VERSION=$(jq -r '.version' package.json)

info "Testing package: $PACKAGE_NAME@$PACKAGE_VERSION"
info "Test type: $TEST_TYPE"
info "Working directory: $(pwd)"

# Basic test: npm pack dry-run
info "Running basic installability test..."

if timeout "$TEST_TIMEOUT" npm pack --dry-run >/dev/null 2>&1; then
  success "npm pack dry-run passed"
else
  error "npm pack dry-run failed"
  echo "Running with verbose output:" >&2
  npm pack --dry-run
  exit 1
fi

# Exit early if only basic test requested
if [[ "$TEST_TYPE" == "basic" ]]; then
  success "Basic test completed successfully"
  exit 0
fi

# Full test: create actual tarball and test installation
if [[ "$TEST_TYPE" == "full" || "$TEST_TYPE" == "smoke" ]]; then
  info "Running full installation test..."
  
  # Create temporary directory for testing
  TEMP_TEST_DIR=$(mktemp -d)
  trap "rm -rf '$TEMP_TEST_DIR'" EXIT
  
  info "Test directory: $TEMP_TEST_DIR"
  
  # Create tarball
  TARBALL_NAME=$(npm pack --silent)
  if [[ ! -f "$TARBALL_NAME" ]]; then
    error "Failed to create tarball"
    exit 1
  fi
  
  success "Created tarball: $TARBALL_NAME"
  
  # Move tarball to test directory
  mv "$TARBALL_NAME" "$TEMP_TEST_DIR/"
  cd "$TEMP_TEST_DIR"
  
  # Create minimal test package.json
  cat > package.json << EOF
{
  "name": "test-install",
  "private": true,
  "dependencies": {
    "$PACKAGE_NAME": "file:./$TARBALL_NAME"
  }
}
EOF
  
  # Test installation
  info "Testing npm install..."
  if timeout "$TEST_TIMEOUT" npm install --silent; then
    success "npm install passed"
  else
    error "npm install failed"
    exit 1
  fi
  
  # Verify installed files
  NODE_MODULES_PKG="node_modules/$PACKAGE_NAME"
  if [[ ! -d "$NODE_MODULES_PKG" ]]; then
    error "Package not found in node_modules after install"
    exit 1
  fi
  
  success "Package installed successfully in node_modules"
  
  # Check binary exists after installation
  BINARY_PATH="$NODE_MODULES_PKG/bin"
  if [[ -d "$BINARY_PATH" ]]; then
    success "Binary directory exists in installed package"
    
    # List binary contents
    info "Binary directory contents:"
    ls -la "$BINARY_PATH" || true
  else
    error "Binary directory missing in installed package"
    exit 1
  fi
fi

# Smoke test: try to execute binary
if [[ "$TEST_TYPE" == "smoke" && "$SKIP_BINARY_TEST" != "true" ]]; then
  info "Running smoke test (binary execution)..."
  
  # Find the binary
  BINARY_FILES=($(find "$NODE_MODULES_PKG/bin" -name "terraform*" -type f 2>/dev/null || true))
  
  if [[ ${#BINARY_FILES[@]} -eq 0 ]]; then
    error "No terraform binary found in installed package"
    exit 1
  fi
  
  BINARY_FILE="${BINARY_FILES[0]}"
  info "Testing binary: $BINARY_FILE"
  
  # Test binary execution (with timeout to prevent hangs)
  if timeout 10 "$BINARY_FILE" version >/dev/null 2>&1; then
    success "Binary execution test passed"
  else
    warning "Binary execution test failed (this may be expected for cross-platform packages)"
    info "Binary file info:"
    file "$BINARY_FILE" 2>/dev/null || echo "file command not available"
  fi
fi

success "Package testing completed successfully"
info "Test summary:"
info "  Package: $PACKAGE_NAME@$PACKAGE_VERSION"
info "  Test type: $TEST_TYPE"
info "  Result: PASSED"