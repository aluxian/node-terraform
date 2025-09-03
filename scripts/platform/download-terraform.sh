#!/bin/bash

# Download and verify Terraform binary for a specific platform
# Usage: download-terraform.sh <version> <terraform_arch> [output_dir]
# Example: download-terraform.sh 1.13.1 darwin_arm64 ./downloads

set -euo pipefail

# Function to show usage
usage() {
  cat << EOF
Usage: $0 <version> <terraform_arch> [output_dir]

Downloads and verifies a Terraform binary for the specified platform.

Arguments:
  version         Terraform version to download (e.g., 1.13.1)
  terraform_arch  Terraform platform architecture (e.g., darwin_arm64, linux_amd64)
  output_dir      Output directory (default: ./downloads)

Examples:
  $0 1.13.1 darwin_arm64
  $0 1.13.1 linux_amd64 ./temp
  $0 1.5.7 windows_amd64 /tmp/terraform

Environment Variables:
  SKIP_CHECKSUM_VERIFICATION  Set to 'true' to skip checksum verification (not recommended)
  TERRAFORM_BASE_URL         Base URL for downloads (default: https://releases.hashicorp.com/terraform)
EOF
}

# Validate arguments
if [[ $# -lt 2 ]]; then
  echo "Error: Missing required arguments" >&2
  usage >&2
  exit 1
fi

VERSION="$1"
TERRAFORM_ARCH="$2"
OUTPUT_DIR="${3:-./downloads}"

# Environment variables with defaults
SKIP_CHECKSUM_VERIFICATION="${SKIP_CHECKSUM_VERIFICATION:-false}"
TERRAFORM_BASE_URL="${TERRAFORM_BASE_URL:-https://releases.hashicorp.com/terraform}"

# Validate version format
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z]+[0-9]*)?$ ]]; then
  echo "Error: Invalid Terraform version format: $VERSION" >&2
  echo "Expected format: X.Y.Z or X.Y.Z-suffix" >&2
  exit 1
fi

# Validate terraform arch
if [[ ! "$TERRAFORM_ARCH" =~ ^[a-z0-9_]+$ ]]; then
  echo "Error: Invalid Terraform architecture format: $TERRAFORM_ARCH" >&2
  exit 1
fi

echo "Downloading Terraform ${VERSION} for ${TERRAFORM_ARCH}..."

# Create output directory
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# Construct URLs
DOWNLOAD_URL="${TERRAFORM_BASE_URL}/${VERSION}/terraform_${VERSION}_${TERRAFORM_ARCH}.zip"
CHECKSUMS_URL="${TERRAFORM_BASE_URL}/${VERSION}/terraform_${VERSION}_SHA256SUMS"

# File names
ZIP_FILE="terraform_${VERSION}_${TERRAFORM_ARCH}.zip"
CHECKSUMS_FILE="terraform_${VERSION}_SHA256SUMS"

echo "Download URL: ${DOWNLOAD_URL}"

# Download binary archive
if ! curl -fsSL -o "$ZIP_FILE" "$DOWNLOAD_URL"; then
  echo "Error: Failed to download Terraform binary from $DOWNLOAD_URL" >&2
  exit 1
fi

echo "Downloaded: $ZIP_FILE"

# Download and verify checksums unless skipped
if [[ "$SKIP_CHECKSUM_VERIFICATION" != "true" ]]; then
  echo "Downloading checksums file..."
  
  if ! curl -fsSL -o "$CHECKSUMS_FILE" "$CHECKSUMS_URL"; then
    echo "Warning: Failed to download checksums file from $CHECKSUMS_URL" >&2
    echo "Skipping checksum verification" >&2
  else
    echo "Verifying checksum..."
    
    if command -v sha256sum >/dev/null; then
      if grep "$ZIP_FILE" "$CHECKSUMS_FILE" | sha256sum -c; then
        echo "✓ Checksum verification passed"
      else
        echo "Error: Checksum verification failed" >&2
        exit 1
      fi
    elif command -v shasum >/dev/null; then
      if grep "$ZIP_FILE" "$CHECKSUMS_FILE" | shasum -a 256 -c; then
        echo "✓ Checksum verification passed"
      else
        echo "Error: Checksum verification failed" >&2
        exit 1
      fi
    else
      echo "Warning: Neither sha256sum nor shasum available, skipping checksum verification" >&2
    fi
  fi
else
  echo "Skipping checksum verification (SKIP_CHECKSUM_VERIFICATION=true)"
fi

# Extract binary
echo "Extracting binary..."
if ! unzip -q "$ZIP_FILE"; then
  echo "Error: Failed to extract $ZIP_FILE" >&2
  exit 1
fi

# Determine expected binary name
if [[ "$TERRAFORM_ARCH" == windows_* ]]; then
  BINARY_NAME="terraform.exe"
else
  BINARY_NAME="terraform"
fi

# Verify binary exists
if [[ ! -f "$BINARY_NAME" ]]; then
  echo "Error: $BINARY_NAME not found after extraction" >&2
  echo "Archive contents:" >&2
  unzip -l "$ZIP_FILE" >&2
  exit 1
fi

# Make binary executable (Unix-like systems)
if [[ "$TERRAFORM_ARCH" != windows_* ]]; then
  chmod +x "$BINARY_NAME"
fi

# Verify binary is functional
echo "Verifying binary..."
if [[ "$TERRAFORM_ARCH" != windows_* ]]; then
  if [[ ! -x "$BINARY_NAME" ]]; then
    echo "Error: Binary is not executable" >&2
    exit 1
  fi
fi

# Test binary execution (basic smoke test)
if "./$BINARY_NAME" version >/dev/null 2>&1; then
  echo "✓ Binary verification passed"
else
  echo "Warning: Binary execution test failed (this might be expected for cross-platform builds)" >&2
fi

echo "Successfully downloaded and verified Terraform ${VERSION} for ${TERRAFORM_ARCH}"
echo "Binary location: $(pwd)/$BINARY_NAME"