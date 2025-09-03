#!/bin/bash

# Create platform package structure and copy binary
# Usage: create-package-structure.sh <package_name> <platform> <downloads_dir> [output_base_dir]
# Example: create-package-structure.sh @jahed/terraform-darwin-arm64 darwin downloads ./platform-packages

set -euo pipefail

# Function to show usage
usage() {
  cat << EOF
Usage: $0 <package_name> <platform> <downloads_dir> [output_base_dir]

Creates the directory structure for a platform-specific npm package and copies the binary.

Arguments:
  package_name      Full npm package name (e.g., @jahed/terraform-darwin-arm64)
  platform          Platform name (darwin, linux, win32, freebsd, openbsd, solaris)
  downloads_dir     Directory containing the downloaded terraform binary
  output_base_dir   Base directory for platform packages (default: ./platform-packages)

Examples:
  $0 @jahed/terraform-darwin-arm64 darwin ./downloads
  $0 @jahed/terraform-linux-x64 linux ./temp ./output
  $0 @jahed/terraform-win32-x64 win32 ./downloads ./packages

The script will create:
  \${output_base_dir}/\${package_name}/
  ├── bin/
  │   └── terraform[.exe]
  └── (package.json and README.md created by other scripts)
EOF
}

# Validate arguments
if [[ $# -lt 3 ]]; then
  echo "Error: Missing required arguments" >&2
  usage >&2
  exit 1
fi

PACKAGE_NAME="$1"
PLATFORM="$2"
DOWNLOADS_DIR="$3"
OUTPUT_BASE_DIR="${4:-./platform-packages}"

# Validate package name format
if [[ ! "$PACKAGE_NAME" =~ ^@[a-z0-9-]+/[a-z0-9-]+$ ]]; then
  echo "Error: Invalid package name format: $PACKAGE_NAME" >&2
  echo "Expected format: @scope/package-name" >&2
  exit 1
fi

# Validate platform
case "$PLATFORM" in
  darwin|linux|win32|freebsd|openbsd|solaris)
    ;;
  *)
    echo "Error: Unsupported platform: $PLATFORM" >&2
    echo "Supported platforms: darwin, linux, win32, freebsd, openbsd, solaris" >&2
    exit 1
    ;;
esac

# Validate downloads directory exists
if [[ ! -d "$DOWNLOADS_DIR" ]]; then
  echo "Error: Downloads directory does not exist: $DOWNLOADS_DIR" >&2
  exit 1
fi

# Determine binary name based on platform
if [[ "$PLATFORM" == "win32" ]]; then
  BINARY_NAME="terraform.exe"
else
  BINARY_NAME="terraform"
fi

# Check if binary exists in downloads directory
BINARY_PATH="$DOWNLOADS_DIR/$BINARY_NAME"
if [[ ! -f "$BINARY_PATH" ]]; then
  echo "Error: Binary not found: $BINARY_PATH" >&2
  echo "Available files in $DOWNLOADS_DIR:" >&2
  ls -la "$DOWNLOADS_DIR" >&2
  exit 1
fi

echo "Creating package structure for $PACKAGE_NAME..."

# Create package directory structure
PACKAGE_DIR="$OUTPUT_BASE_DIR/$PACKAGE_NAME"
mkdir -p "$PACKAGE_DIR/bin"

echo "Package directory: $PACKAGE_DIR"

# Copy binary to package
echo "Copying binary: $BINARY_PATH -> $PACKAGE_DIR/bin/$BINARY_NAME"
cp "$BINARY_PATH" "$PACKAGE_DIR/bin/"

# Ensure binary is executable (Unix-like systems)
if [[ "$PLATFORM" != "win32" ]]; then
  chmod +x "$PACKAGE_DIR/bin/$BINARY_NAME"
  
  # Verify it's executable
  if [[ ! -x "$PACKAGE_DIR/bin/$BINARY_NAME" ]]; then
    echo "Error: Failed to make binary executable" >&2
    exit 1
  fi
fi

# Verify the copy was successful
if [[ ! -f "$PACKAGE_DIR/bin/$BINARY_NAME" ]]; then
  echo "Error: Failed to copy binary to package directory" >&2
  exit 1
fi

# Get file size for verification
ORIGINAL_SIZE=$(stat -f%z "$BINARY_PATH" 2>/dev/null || stat -c%s "$BINARY_PATH" 2>/dev/null || echo "unknown")
COPIED_SIZE=$(stat -f%z "$PACKAGE_DIR/bin/$BINARY_NAME" 2>/dev/null || stat -c%s "$PACKAGE_DIR/bin/$BINARY_NAME" 2>/dev/null || echo "unknown")

echo "✓ Binary copied successfully"
echo "  Original size: $ORIGINAL_SIZE bytes"
echo "  Copied size: $COPIED_SIZE bytes"

if [[ "$ORIGINAL_SIZE" != "unknown" && "$COPIED_SIZE" != "unknown" && "$ORIGINAL_SIZE" != "$COPIED_SIZE" ]]; then
  echo "Warning: File sizes don't match!" >&2
  exit 1
fi

echo "✓ Package structure created: $PACKAGE_DIR"
echo "Contents:"
find "$PACKAGE_DIR" -type f -exec ls -la {} \;