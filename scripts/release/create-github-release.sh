#!/bin/bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <package_version> <terraform_version> [tarball_path]" >&2
  exit 1
fi

PACKAGE_VERSION="$1"
TERRAFORM_VERSION="$2"
TARBALL_PATH="${3:-}"

TAG_NAME="v$PACKAGE_VERSION"

# Auto-detect repository
if [[ -z "${GITHUB_REPOSITORY:-}" && -d ".git" ]]; then
  ORIGIN_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
  if [[ "$ORIGIN_URL" =~ github\.com[:/]([^/]+/[^/]+) ]]; then
    export GITHUB_REPOSITORY="${BASH_REMATCH[1]%.git}"
  fi
fi

RELEASE_NOTES="Release v${PACKAGE_VERSION} with Terraform ${TERRAFORM_VERSION}

Install with: \`npm install @aluxian/terraform\`

Includes platform-specific binaries for macOS, Linux, Windows, FreeBSD, OpenBSD, and Solaris."

GH_ARGS=("release" "create" "$TAG_NAME" "--title" "v${PACKAGE_VERSION}" "--notes" "$RELEASE_NOTES")

if [[ "${PRERELEASE:-false}" == "true" ]]; then
  GH_ARGS+=("--prerelease")
fi

if [[ "${DRAFT:-false}" == "true" ]]; then
  GH_ARGS+=("--draft")
fi

if [[ -n "$TARBALL_PATH" ]]; then
  GH_ARGS+=("$TARBALL_PATH")
fi

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  echo "DRY RUN: Would create release: ${GH_ARGS[*]}"
else
  gh "${GH_ARGS[@]}"
  echo "✓ Created release v${PACKAGE_VERSION}"
fi