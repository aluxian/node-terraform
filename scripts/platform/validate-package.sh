#!/bin/bash

# Validate platform package structure and contents
# Usage: validate-package.sh <package_dir> <package_name> <platform> <binary_name>
# Example: validate-package.sh ./platform-packages/@aluxian/terraform-darwin-arm64 @aluxian/terraform-darwin-arm64 darwin terraform

set -euo pipefail

# Function to show usage
usage() {
  cat << EOF
Usage: $0 <package_dir> <package_name> <platform> <binary_name>

Validates the structure and contents of a platform-specific npm package.

Arguments:
  package_dir   Path to the package directory
  package_name  Full npm package name (e.g., @aluxian/terraform-darwin-arm64)
  platform      Platform name (darwin, linux, win32, freebsd, openbsd, solaris)
  binary_name   Expected binary name (terraform or terraform.exe)

Examples:
  $0 ./platform-packages/@aluxian/terraform-darwin-arm64 @aluxian/terraform-darwin-arm64 darwin terraform
  $0 ./packages/linux-x64 @aluxian/terraform-linux-x64 linux terraform
  $0 ./win32-package @aluxian/terraform-win32-x64 win32 terraform.exe

Validation checks:
  - Required files exist (package.json, README.md, binary)
  - package.json structure and content
  - Binary is executable (Unix-like systems)
  - File permissions and sizes
  - Package directory structure
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
if [[ $# -lt 4 ]]; then
  error "Missing required arguments"
  usage >&2
  exit 1
fi

PACKAGE_DIR="$1"
PACKAGE_NAME="$2"
PLATFORM="$3"
BINARY_NAME="$4"

# Validate inputs
if [[ ! "$PACKAGE_NAME" =~ ^@[a-z0-9-]+/[a-z0-9-]+$ ]]; then
  error "Invalid package name format: $PACKAGE_NAME"
  echo "Expected format: @scope/package-name" >&2
  exit 1
fi

case "$PLATFORM" in
  darwin|linux|win32|freebsd|openbsd|solaris)
    ;;
  *)
    error "Unsupported platform: $PLATFORM"
    echo "Supported platforms: darwin, linux, win32, freebsd, openbsd, solaris" >&2
    exit 1
    ;;
esac

if [[ "$BINARY_NAME" != "terraform" && "$BINARY_NAME" != "terraform.exe" ]]; then
  error "Invalid binary name: $BINARY_NAME"
  echo "Expected: terraform or terraform.exe" >&2
  exit 1
fi

# Start validation
info "Validating package: $PACKAGE_NAME"
info "Package directory: $PACKAGE_DIR"
info "Platform: $PLATFORM"
info "Binary name: $BINARY_NAME"

VALIDATION_ERRORS=0

# Check package directory exists
if [[ ! -d "$PACKAGE_DIR" ]]; then
  error "Package directory does not exist: $PACKAGE_DIR"
  exit 1
fi

success "Package directory exists"

# Check required files
REQUIRED_FILES=("package.json" "README.md" "bin/$BINARY_NAME")

for file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "$PACKAGE_DIR/$file" ]]; then
    error "Required file missing: $file"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
  else
    success "Required file exists: $file"
  fi
done

# Validate package.json
PACKAGE_JSON_PATH="$PACKAGE_DIR/package.json"
if [[ -f "$PACKAGE_JSON_PATH" ]]; then
  # Check if valid JSON
  if ! jq . "$PACKAGE_JSON_PATH" >/dev/null 2>&1; then
    error "package.json is not valid JSON"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
  else
    success "package.json is valid JSON"
    
    # Check required fields
    REQUIRED_FIELDS=("name" "version" "description" "license" "os" "cpu" "files" "engines")
    
    for field in "${REQUIRED_FIELDS[@]}"; do
      if ! jq -e ".$field" "$PACKAGE_JSON_PATH" >/dev/null 2>&1; then
        error "package.json missing required field: $field"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
      else
        success "package.json has required field: $field"
      fi
    done
    
    # Validate specific field values
    ACTUAL_NAME=$(jq -r '.name' "$PACKAGE_JSON_PATH")
    if [[ "$ACTUAL_NAME" != "$PACKAGE_NAME" ]]; then
      error "package.json name mismatch: expected '$PACKAGE_NAME', got '$ACTUAL_NAME'"
      VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    else
      success "package.json name matches expected: $PACKAGE_NAME"
    fi
    
    # Check OS restriction
    if ! jq -e ".os | index(\"$PLATFORM\")" "$PACKAGE_JSON_PATH" >/dev/null 2>&1; then
      error "package.json missing platform '$PLATFORM' in os field"
      VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    else
      success "package.json includes correct platform in os field"
    fi
    
    # Check files array includes 'bin'
    if ! jq -e '.files | index("bin")' "$PACKAGE_JSON_PATH" >/dev/null 2>&1; then
      error "package.json files array missing 'bin'"
      VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    else
      success "package.json files array includes 'bin'"
    fi
  fi
else
  error "package.json file not found"
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Validate README.md
README_PATH="$PACKAGE_DIR/README.md"
if [[ -f "$README_PATH" ]]; then
  README_SIZE=$(wc -c < "$README_PATH")
  if [[ $README_SIZE -lt 500 ]]; then
    warning "README.md seems small ($README_SIZE bytes)"
  else
    success "README.md has reasonable size ($README_SIZE bytes)"
  fi
  
  # Check for package name in README
  if grep -q "$PACKAGE_NAME" "$README_PATH"; then
    success "README.md contains package name"
  else
    warning "README.md doesn't contain package name"
  fi
else
  error "README.md file not found"
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Validate binary
BINARY_PATH="$PACKAGE_DIR/bin/$BINARY_NAME"
if [[ -f "$BINARY_PATH" ]]; then
  success "Binary exists: $BINARY_NAME"
  
  # Check file size
  BINARY_SIZE=$(stat -f%z "$BINARY_PATH" 2>/dev/null || stat -c%s "$BINARY_PATH" 2>/dev/null || echo "unknown")
  info "Binary size: $BINARY_SIZE bytes"
  
  # Check if binary is too small (likely invalid)
  if [[ "$BINARY_SIZE" != "unknown" && $BINARY_SIZE -lt 10000000 ]]; then # 10MB
    warning "Binary seems small for Terraform ($BINARY_SIZE bytes)"
  fi
  
  # Check executable permissions (Unix-like systems)
  if [[ "$PLATFORM" != "win32" ]]; then
    if [[ -x "$BINARY_PATH" ]]; then
      success "Binary is executable"
    else
      error "Binary is not executable"
      VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
    
    # Check if it's not a symlink or directory
    if [[ -L "$BINARY_PATH" ]]; then
      error "Binary is a symlink (should be a regular file)"
      VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    elif [[ -d "$BINARY_PATH" ]]; then
      error "Binary path is a directory (should be a file)"
      VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
  fi
  
  # Try to detect file type
  if command -v file >/dev/null; then
    FILE_TYPE=$(file "$BINARY_PATH" 2>/dev/null || echo "unknown")
    info "Binary file type: $FILE_TYPE"
    
    # Basic checks based on platform
    case "$PLATFORM" in
      darwin)
        if [[ "$FILE_TYPE" == *"Mach-O"* ]]; then
          success "Binary appears to be a valid macOS executable"
        else
          warning "Binary doesn't appear to be a macOS executable"
        fi
        ;;
      linux|freebsd|openbsd|solaris)
        if [[ "$FILE_TYPE" == *"ELF"* ]]; then
          success "Binary appears to be a valid Unix executable"
        else
          warning "Binary doesn't appear to be a Unix executable"
        fi
        ;;
      win32)
        if [[ "$FILE_TYPE" == *"PE32"* || "$FILE_TYPE" == *"executable"* ]]; then
          success "Binary appears to be a valid Windows executable"
        else
          warning "Binary doesn't appear to be a Windows executable"
        fi
        ;;
    esac
  fi
else
  error "Binary file not found: bin/$BINARY_NAME"
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Check for unexpected files
info "Checking for unexpected files..."
EXPECTED_FILES=("package.json" "README.md" "bin" "bin/$BINARY_NAME")
UNEXPECTED_FILES=()

while IFS= read -r -d '' file; do
  relative_path="${file#$PACKAGE_DIR/}"
  if [[ ! " ${EXPECTED_FILES[*]} " =~ " ${relative_path} " ]]; then
    UNEXPECTED_FILES+=("$relative_path")
  fi
done < <(find "$PACKAGE_DIR" -type f -print0)

if [[ ${#UNEXPECTED_FILES[@]} -gt 0 ]]; then
  warning "Unexpected files found:"
  for file in "${UNEXPECTED_FILES[@]}"; do
    warning "  $file"
  done
else
  success "No unexpected files found"
fi

# Summary
echo ""
info "Validation Summary"
info "=================="
info "Package: $PACKAGE_NAME"
info "Platform: $PLATFORM"
info "Validation errors: $VALIDATION_ERRORS"

if [[ $VALIDATION_ERRORS -eq 0 ]]; then
  success "Package validation PASSED"
  exit 0
else
  error "Package validation FAILED with $VALIDATION_ERRORS errors"
  exit 1
fi