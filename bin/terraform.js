#!/usr/bin/env node

import { spawn } from "child_process";
import path from "path";
import fs from "fs";
import os from "os";
import { createRequire } from "module";

const require = createRequire(import.meta.url);

/**
 * @typedef {Object} PlatformInfo
 * @property {string} pkg - Package name
 * @property {string} subpath - Binary subpath within package
 * @property {string} terraformPlatform - Terraform platform name
 * @property {string} terraformArch - Terraform architecture name
 */

/**
 * Maps Node.js platform and architecture combinations to Terraform package information
 * @type {Record<string, PlatformInfo>}
 */
const PLATFORM_MAPPING = {
  // macOS
  "darwin arm64": {
    pkg: "@aluxian/terraform-darwin-arm64",
    subpath: "bin/terraform",
    terraformPlatform: "darwin",
    terraformArch: "arm64",
  },
  "darwin x64": {
    pkg: "@aluxian/terraform-darwin-x64",
    subpath: "bin/terraform",
    terraformPlatform: "darwin",
    terraformArch: "amd64",
  },

  // Linux
  "linux arm64": {
    pkg: "@aluxian/terraform-linux-arm64",
    subpath: "bin/terraform",
    terraformPlatform: "linux",
    terraformArch: "arm64",
  },
  "linux x64": {
    pkg: "@aluxian/terraform-linux-x64",
    subpath: "bin/terraform",
    terraformPlatform: "linux",
    terraformArch: "amd64",
  },
  "linux arm": {
    pkg: "@aluxian/terraform-linux-arm",
    subpath: "bin/terraform",
    terraformPlatform: "linux",
    terraformArch: "arm",
  },

  // Windows
  "win32 arm64": {
    pkg: "@aluxian/terraform-win32-arm64",
    subpath: "terraform.exe",
    terraformPlatform: "windows",
    terraformArch: "arm64",
  },
  "win32 x64": {
    pkg: "@aluxian/terraform-win32-x64",
    subpath: "terraform.exe",
    terraformPlatform: "windows",
    terraformArch: "amd64",
  },

  // FreeBSD
  "freebsd x64": {
    pkg: "@aluxian/terraform-freebsd-x64",
    subpath: "bin/terraform",
    terraformPlatform: "freebsd",
    terraformArch: "amd64",
  },

  // OpenBSD
  "openbsd x64": {
    pkg: "@aluxian/terraform-openbsd-x64",
    subpath: "bin/terraform",
    terraformPlatform: "openbsd",
    terraformArch: "amd64",
  },

  // Solaris (Node.js reports as 'sunos')
  "sunos x64": {
    pkg: "@aluxian/terraform-solaris-x64",
    subpath: "bin/terraform",
    terraformPlatform: "solaris",
    terraformArch: "amd64",
  },
};

/**
 * Gets the platform package information for the current system
 * @returns {PlatformInfo} PlatformInfo containing package name and binary subpath
 * @throws {Error} If the current platform/architecture combination is not supported
 */
const getPlatformPackage = () => {
  const platform = process.platform;
  const arch = os.arch();
  const key = `${platform} ${arch}`;

  const platformInfo = PLATFORM_MAPPING[key];

  if (!platformInfo) {
    throw new Error(
      `Platform "${platform}" with architecture "${arch}" is not supported.`
    );
  }

  return platformInfo;
};

/**
 * Resolves the terraform binary from platform-specific package
 * This is a pure esbuild-style implementation with no download fallback
 *
 * @returns {Promise<string>} Promise resolving to the path of the terraform binary
 * @throws {Error} If platform package cannot be resolved
 */
async function resolveTerraformBinary() {
  const platformInfo = getPlatformPackage();

  let packagePath;
  try {
    packagePath = require.resolve(platformInfo.pkg);
  } catch (resolveError) {
    throw new Error(
      `Could not find platform-specific terraform package "${platformInfo.pkg}". This package should have been automatically installed as an optional dependency.
To fix this:
  1. Reinstall without --no-optional flag: npm install
  2. Or manually install the platform package: npm install ${platformInfo.pkg}
  3. If using yarn, ensure optionalDependencies are enabled
Platform packages provide pre-compiled terraform binaries for faster execution.`
    );
  }

  // Calculate the binary path relative to the package
  const packageRoot = path.dirname(packagePath);
  const binaryPath = path.resolve(packageRoot, platformInfo.subpath);

  // Verify the binary exists and is accessible
  try {
    fs.accessSync(binaryPath, fs.constants.F_OK | fs.constants.X_OK);
    return binaryPath;
  } catch (accessError) {
    throw new Error(
      `Found platform package "${platformInfo.pkg}" but terraform binary is not accessible at: ${binaryPath}
This may indicate a corrupted installation. Try reinstalling: npm install ${platformInfo.pkg}`
    );
  }
}

try {
  const args = process.argv.slice(2);
  const terraformPath = await resolveTerraformBinary();
  const terraform = spawn(terraformPath, args, {
    stdio: [process.stdin, process.stdout, process.stderr],
  });
  terraform.on("close", (code) => process.exit(code || undefined));
} catch (error) {
  console.error(error);
  process.exit(1);
}
