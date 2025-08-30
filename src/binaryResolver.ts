import { branch, eventually, waterfall } from "@jahed/promises";
import path from "path";
import fs from "fs";
import { debug } from "./debug";
import { getPlatformPackage } from "./platform";
import { getOutputs } from "./getOutputs";
import { install } from "./install";
import { fileExists } from "./fileExists";

/**
 * Attempts to resolve the terraform binary from a platform-specific package
 * @returns Promise resolving to binary path, or null if package resolution failed
 */
async function tryPlatformPackage(): Promise<string | null> {
  try {
    debug("attempting to resolve terraform binary from platform-specific package");
    
    const platformInfo = await getPlatformPackage();
    debug("platform package info resolved", { platformInfo });
    
    // TypeScript doesn't know that resolveNullable throws rather than returning null
    if (!platformInfo) {
      throw new Error("Platform info is null - this should not happen as resolveNullable throws");
    }
    
    // Try to resolve the platform package
    let packagePath: string;
    try {
      packagePath = require.resolve(platformInfo.pkg);
      debug("platform package resolved successfully", { packagePath });
    } catch (resolveError) {
      debug("failed to resolve platform package", { 
        package: platformInfo.pkg, 
        error: resolveError instanceof Error ? resolveError.message : resolveError 
      });
      return null;
    }
    
    // Calculate the binary path relative to the package
    const packageRoot = path.dirname(packagePath);
    const binaryPath = path.resolve(packageRoot, platformInfo.subpath);
    debug("calculated binary path", { binaryPath });
    
    // Verify the binary exists and is accessible
    try {
      await fileExists(binaryPath);
      debug("platform-specific terraform binary found and verified", { path: binaryPath });
      return binaryPath;
    } catch (accessError) {
      debug("platform-specific binary exists but is not accessible", { 
        path: binaryPath, 
        error: accessError instanceof Error ? accessError.message : accessError 
      });
      return null;
    }
    
  } catch (error) {
    debug("platform package resolution failed", { 
      error: error instanceof Error ? error.message : error 
    });
    return null;
  }
}

/**
 * Fallback to the existing download logic when platform package is not available
 * @returns Promise resolving to the downloaded binary path
 */
async function fallbackToDownload(): Promise<string> {
  debug("falling back to download-based terraform resolution");
  
  const outputs = getOutputs();
  debug("using download fallback", { 
    version: outputs.version, 
    targetPath: outputs.path 
  });
  
  // Use the existing install logic which handles downloads and caching
  await install(outputs);
  
  debug("terraform binary installed via download", { path: outputs.path });
  return outputs.path;
}

/**
 * Resolves the terraform binary using esbuild-style resolution strategy:
 * 1. First tries to resolve from platform-specific package using require.resolve()
 * 2. Falls back to existing download logic if platform package not found
 * 
 * @returns Promise resolving to the path of the terraform binary
 */
export async function resolveTerraformBinary(): Promise<string> {
  debug("starting terraform binary resolution");
  
  // First, try to resolve from platform-specific package
  const platformBinaryPath = await tryPlatformPackage();
  
  if (platformBinaryPath) {
    debug("terraform binary resolved from platform-specific package", { 
      path: platformBinaryPath 
    });
    return platformBinaryPath;
  }
  
  // Log why we're falling back
  console.warn(
    "Warning: Could not resolve terraform binary from platform-specific package. " +
    "This may happen if:\n" +
    "  - npm was run with --no-optional (platform packages are optional dependencies)\n" +
    "  - You're using yarn PnP without proper platform package installation\n" +
    "  - The platform package was not installed or is corrupted\n" +
    "Falling back to downloading terraform binary..."
  );
  
  // Fallback to download logic
  return fallbackToDownload();
}