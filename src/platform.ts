import { reason, resolveNullable } from "@jahed/promises";
import os from "os";

export interface PlatformInfo {
  pkg: string;
  subpath: string;
}

/**
 * Maps Node.js platform and architecture combinations to Terraform package information
 */
const PLATFORM_MAPPING: Record<string, PlatformInfo | null> = {
  // macOS
  "darwin arm64": {
    pkg: "@jahed/terraform-darwin-arm64",
    subpath: "bin/terraform",
  },
  "darwin x64": {
    pkg: "@jahed/terraform-darwin-x64", 
    subpath: "bin/terraform",
  },
  
  // Linux
  "linux arm64": {
    pkg: "@jahed/terraform-linux-arm64",
    subpath: "bin/terraform",
  },
  "linux x64": {
    pkg: "@jahed/terraform-linux-x64",
    subpath: "bin/terraform",
  },
  "linux arm": {
    pkg: "@jahed/terraform-linux-arm",
    subpath: "bin/terraform",
  },
  
  // Windows
  "win32 arm64": {
    pkg: "@jahed/terraform-win32-arm64",
    subpath: "terraform.exe",
  },
  "win32 x64": {
    pkg: "@jahed/terraform-win32-x64",
    subpath: "terraform.exe",
  },
  
  // FreeBSD
  "freebsd x64": {
    pkg: "@jahed/terraform-freebsd-x64",
    subpath: "bin/terraform",
  },
  
  // OpenBSD
  "openbsd x64": {
    pkg: "@jahed/terraform-openbsd-x64",
    subpath: "bin/terraform",
  },
  
  // Solaris (Node.js reports as 'sunos')
  "sunos x64": {
    pkg: "@jahed/terraform-solaris-x64",
    subpath: "bin/terraform",
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

export { getPlatformPackage };