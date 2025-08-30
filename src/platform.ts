import { reason, resolveNullable } from "@jahed/promises";
import os from "os";

export interface PlatformInfo {
  pkg: string;
  subpath: string;
  terraformPlatform: string;
  terraformArch: string;
}

/**
 * Maps Node.js platform and architecture combinations to Terraform package information
 */
const PLATFORM_MAPPING: Record<string, PlatformInfo | null> = {
  // macOS
  "darwin arm64": {
    pkg: "@jahed/terraform-darwin-arm64",
    subpath: "bin/terraform",
    terraformPlatform: "darwin",
    terraformArch: "arm64",
  },
  "darwin x64": {
    pkg: "@jahed/terraform-darwin-x64", 
    subpath: "bin/terraform",
    terraformPlatform: "darwin",
    terraformArch: "amd64",
  },
  
  // Linux
  "linux arm64": {
    pkg: "@jahed/terraform-linux-arm64",
    subpath: "bin/terraform",
    terraformPlatform: "linux",
    terraformArch: "arm64",
  },
  "linux x64": {
    pkg: "@jahed/terraform-linux-x64",
    subpath: "bin/terraform",
    terraformPlatform: "linux",
    terraformArch: "amd64",
  },
  "linux arm": {
    pkg: "@jahed/terraform-linux-arm",
    subpath: "bin/terraform",
    terraformPlatform: "linux",
    terraformArch: "arm",
  },
  
  // Windows
  "win32 arm64": {
    pkg: "@jahed/terraform-win32-arm64",
    subpath: "terraform.exe",
    terraformPlatform: "windows",
    terraformArch: "arm64",
  },
  "win32 x64": {
    pkg: "@jahed/terraform-win32-x64",
    subpath: "terraform.exe",
    terraformPlatform: "windows",
    terraformArch: "amd64",
  },
  
  // FreeBSD
  "freebsd x64": {
    pkg: "@jahed/terraform-freebsd-x64",
    subpath: "bin/terraform",
    terraformPlatform: "freebsd",
    terraformArch: "amd64",
  },
  
  // OpenBSD
  "openbsd x64": {
    pkg: "@jahed/terraform-openbsd-x64",
    subpath: "bin/terraform",
    terraformPlatform: "openbsd",
    terraformArch: "amd64",
  },
  
  // Solaris (Node.js reports as 'sunos')
  "sunos x64": {
    pkg: "@jahed/terraform-solaris-x64",
    subpath: "bin/terraform",
    terraformPlatform: "solaris",
    terraformArch: "amd64",
  },
  
  // Unsupported platforms explicitly set to null
  "aix x64": null,
  "android arm64": null,
  "android arm": null,
  "android x64": null,
  "cygwin x64": null,
  "netbsd x64": null,
  "haiku x64": null,
};

/**
 * Gets the platform package information for the current system
 * @returns Promise resolving to PlatformInfo containing package name and binary subpath
 * @throws Error if the current platform/architecture combination is not supported
 */
const getPlatformPackage = () => {
  const platform = process.platform;
  const arch = os.arch();
  const key = `${platform} ${arch}`;
  
  const platformInfo = PLATFORM_MAPPING[key];
  
  return resolveNullable(
    platformInfo,
    reason(
      `Platform "${platform}" with architecture "${arch}" is not supported by Terraform. ` +
      `Supported combinations: ${Object.keys(PLATFORM_MAPPING)
        .filter(k => PLATFORM_MAPPING[k] !== null)
        .join(", ")}`
    )
  );
};

/**
 * Gets the Terraform platform name for the current system  
 * @returns Promise resolving to terraform platform name (e.g., "darwin", "linux", "windows")
 * @throws Error if the current platform/architecture combination is not supported
 */
const getTerraformPlatform = async () => {
  const platformInfo = await getPlatformPackage();
  
  // TypeScript doesn't know that resolveNullable throws rather than returning null
  if (!platformInfo) {
    throw new Error("Platform info is null - this should not happen as resolveNullable throws");
  }
  
  return platformInfo.terraformPlatform;
};

/**
 * Gets the Terraform architecture name for the current system
 * @returns Promise resolving to terraform architecture name (e.g., "amd64", "arm64", "arm")  
 * @throws Error if the current platform/architecture combination is not supported
 */
const getTerraformArchitecture = async () => {
  const platformInfo = await getPlatformPackage();
  
  // TypeScript doesn't know that resolveNullable throws rather than returning null
  if (!platformInfo) {
    throw new Error("Platform info is null - this should not happen as resolveNullable throws");
  }
  
  return platformInfo.terraformArch;
};

export { getPlatformPackage, getTerraformPlatform, getTerraformArchitecture };