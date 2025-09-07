#!/bin/bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <version> <terraform_arch> [output_dir]" >&2
  exit 1
fi

VERSION="$1"
TERRAFORM_ARCH="$2"
OUTPUT_DIR="${3:-./downloads}"

TERRAFORM_BASE_URL="${TERRAFORM_BASE_URL:-https://releases.hashicorp.com/terraform}"

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# Construct URLs and file names
DOWNLOAD_URL="${TERRAFORM_BASE_URL}/${VERSION}/terraform_${VERSION}_${TERRAFORM_ARCH}.zip"
CHECKSUMS_URL="${TERRAFORM_BASE_URL}/${VERSION}/terraform_${VERSION}_SHA256SUMS"
ZIP_FILE="terraform_${VERSION}_${TERRAFORM_ARCH}.zip"
CHECKSUMS_FILE="terraform_${VERSION}_SHA256SUMS"

echo "Downloading Terraform ${VERSION} for ${TERRAFORM_ARCH}..."

# Download binary
curl -fsSL -o "$ZIP_FILE" "$DOWNLOAD_URL"

# Download and verify checksums (unless skipped)
if [[ "${SKIP_CHECKSUM_VERIFICATION:-false}" != "true" ]]; then
  curl -fsSL -o "$CHECKSUMS_FILE" "$CHECKSUMS_URL"
  if command -v sha256sum >/dev/null; then
    grep "$ZIP_FILE" "$CHECKSUMS_FILE" | sha256sum -c -q
  elif command -v shasum >/dev/null; then
    grep "$ZIP_FILE" "$CHECKSUMS_FILE" | shasum -a 256 -c -q
  fi
fi

# Extract binary
unzip -q "$ZIP_FILE"

# Determine binary name and make executable
if [[ "$TERRAFORM_ARCH" == windows_* ]]; then
  BINARY_NAME="terraform.exe"
else
  BINARY_NAME="terraform"
  chmod +x "$BINARY_NAME"
fi

echo "✓ Downloaded and verified Terraform ${VERSION} for ${TERRAFORM_ARCH}"