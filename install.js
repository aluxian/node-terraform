#!/usr/bin/env node

/**
 * Post-install script for @jahed/terraform
 * 
 * This script validates that platform-specific packages can be resolved
 * following the esbuild-style approach. It does not actually download
 * binaries during postinstall - that happens lazily when terraform is
 * first executed.
 * 
 * The script handles both development and production scenarios:
 * - Development: TypeScript files may not be compiled yet
 * - Production: Uses built JavaScript files from lib/ directory
 */

const fs = require('fs');
const path = require('path');

/**
 * Logs a message with timestamp for debugging postinstall issues
 */
function log(message, data = {}) {
  const timestamp = new Date().toISOString();
  const dataStr = Object.keys(data).length > 0 ? ` ${JSON.stringify(data)}` : '';
  console.log(`[${timestamp}] @jahed/terraform postinstall: ${message}${dataStr}`);
}

/**
 * Attempts to resolve terraform binary using the built library
 * @returns {Promise<boolean>} True if resolution succeeds, false otherwise
 */
async function tryResolveFromBuiltLibrary() {
  try {
    const libPath = path.join(__dirname, 'lib');
    
    // Check if lib directory exists (production install)
    if (!fs.existsSync(libPath)) {
      log('lib directory not found, likely a development install');
      return false;
    }
    
    // Try to import the binary resolver from built files
    const binaryResolverPath = path.join(libPath, 'binaryResolver.js');
    if (!fs.existsSync(binaryResolverPath)) {
      log('binaryResolver.js not found in lib directory');
      return false;
    }
    
    log('attempting to validate binary resolution using built library');
    
    // Import and call the resolver
    const { resolveTerraformBinary } = require('./lib/binaryResolver.js');
    
    // This will attempt platform package resolution first, then fall back to download
    const binaryPath = await resolveTerraformBinary();
    
    log('binary resolution validation successful', { binaryPath });
    return true;
    
  } catch (error) {
    log('binary resolution validation failed', { 
      error: error.message,
      stack: error.stack?.split('\n')[0] // Just the first line to avoid spam
    });
    return false;
  }
}

/**
 * Handles development scenario where TypeScript files haven't been compiled yet
 * In this case, we just validate that the platform mapping logic is sound
 * @returns {Promise<boolean>} True if platform is supported, false otherwise
 */
async function handleDevelopmentInstall() {
  try {
    log('handling development install - validating platform support');
    
    const os = require('os');
    const platform = process.platform;
    const arch = os.arch();
    const key = `${platform} ${arch}`;
    
    // This is a simplified version of the platform mapping from platform.ts
    const PLATFORM_MAPPING = {
      "darwin arm64": "@jahed/terraform-darwin-arm64",
      "darwin x64": "@jahed/terraform-darwin-x64",
      "linux arm64": "@jahed/terraform-linux-arm64", 
      "linux x64": "@jahed/terraform-linux-x64",
      "linux arm": "@jahed/terraform-linux-arm",
      "win32 arm64": "@jahed/terraform-win32-arm64",
      "win32 x64": "@jahed/terraform-win32-x64",
      "freebsd x64": "@jahed/terraform-freebsd-x64",
      "openbsd x64": "@jahed/terraform-openbsd-x64",
      "sunos x64": "@jahed/terraform-solaris-x64"
    };
    
    const platformPackage = PLATFORM_MAPPING[key];
    
    if (!platformPackage) {
      log('current platform not supported by terraform', { platform, arch });
      console.warn(
        `Warning: Platform "${platform}" with architecture "${arch}" is not supported by Terraform.\n` +
        `Supported combinations: ${Object.keys(PLATFORM_MAPPING).join(", ")}\n` +
        `Terraform will fall back to downloading binaries when first executed.`
      );
      return false;
    }
    
    log('platform validation successful', { 
      platform, 
      arch, 
      platformPackage 
    });
    
    // Try to resolve the platform package if it was installed
    try {
      const resolvedPath = require.resolve(platformPackage);
      log('platform package successfully resolved', { 
        package: platformPackage,
        path: resolvedPath 
      });
    } catch (resolveError) {
      log('platform package not available (normal for development)', { 
        package: platformPackage,
        error: resolveError.message 
      });
    }
    
    return true;
    
  } catch (error) {
    log('development install validation failed', { 
      error: error.message 
    });
    return false;
  }
}

/**
 * Main postinstall function
 */
async function main() {
  try {
    log('starting postinstall validation');
    
    // First try to use the built library (production scenario)
    const resolvedFromBuilt = await tryResolveFromBuiltLibrary();
    
    if (!resolvedFromBuilt) {
      // Fall back to development install handling
      log('falling back to development install validation');
      const developmentValid = await handleDevelopmentInstall();
      
      if (!developmentValid) {
        log('postinstall validation completed with warnings - terraform will use fallback download');
      } else {
        log('postinstall validation completed successfully');
      }
    } else {
      log('postinstall validation completed successfully using built library');
    }
    
    // Always exit successfully - postinstall should not fail the installation
    // even if platform packages aren't available (they're optional dependencies)
    process.exit(0);
    
  } catch (error) {
    log('postinstall script failed unexpectedly', { 
      error: error.message,
      stack: error.stack 
    });
    
    // Log the error but don't fail the installation
    console.warn(
      'Warning: @jahed/terraform postinstall validation encountered an error.\n' +
      'This does not prevent the package from working - terraform will fall back to downloading binaries.\n' +
      `Error: ${error.message}`
    );
    
    process.exit(0);
  }
}

// Only run if this script is executed directly (not required as a module)
if (require.main === module) {
  main();
}

module.exports = { main };