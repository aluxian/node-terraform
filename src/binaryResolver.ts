import path from "path";
import fs from "fs";
import { debug } from "./debug";
import { getPlatformPackage } from "./platform";

/**
 * Resolves the terraform binary from platform-specific package
 * This is a pure esbuild-style implementation with no download fallback
 * 
 * @returns Promise resolving to the path of the terraform binary
 * @throws Error if platform package cannot be resolved
 */
export async function resolveTerraformBinary(): Promise<string> {
  debug("starting terraform binary resolution (platform packages only)");
  
  const platformInfo = await getPlatformPackage();
  debug("platform package info resolved", { platformInfo });
  
  // platformInfo is guaranteed to exist since getPlatformPackage() rejects on null
  
  // Try to resolve the platform package
  let packagePath: string;
  try {
    packagePath = require.resolve(platformInfo.pkg);
    debug("platform package resolved successfully", { packagePath });
  } catch (resolveError) {
    const errorMessage = resolveError instanceof Error ? resolveError.message : resolveError;
    debug("failed to resolve platform package", { 
      package: platformInfo.pkg, 
      error: errorMessage 
    });
    
    throw new Error(
      `Could not find platform-specific terraform package "${platformInfo.pkg}". ` +
      `This package should have been automatically installed as an optional dependency.\n\n` +
      `To fix this:\n` +
      `  1. Reinstall without --no-optional flag: npm install\n` +
      `  2. Or manually install the platform package: npm install ${platformInfo.pkg}\n` +
      `  3. If using yarn, ensure optionalDependencies are enabled\n\n` +
      `Platform packages provide pre-compiled terraform binaries for faster execution.`
    );
  }
  
  // Calculate the binary path relative to the package
  const packageRoot = path.dirname(packagePath);
  const binaryPath = path.resolve(packageRoot, platformInfo.subpath);
  debug("calculated binary path", { binaryPath });
  
  // Verify the binary exists and is accessible
  try {
    fs.accessSync(binaryPath, fs.constants.F_OK | fs.constants.X_OK);
    debug("platform-specific terraform binary found and verified", { path: binaryPath });
    return binaryPath;
  } catch (accessError) {
    const errorMessage = accessError instanceof Error ? accessError.message : accessError;
    debug("platform-specific binary exists but is not accessible", { 
      path: binaryPath, 
      error: errorMessage 
    });
    
    throw new Error(
      `Found platform package "${platformInfo.pkg}" but terraform binary is not accessible at: ${binaryPath}\n` +
      `This may indicate a corrupted installation. Try reinstalling: npm install ${platformInfo.pkg}`
    );
  }
}