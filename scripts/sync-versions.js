#!/usr/bin/env node

/**
 * Comprehensive script to synchronize versions between main and platform packages
 * Can update both package.json and platform package dependencies
 *
 * Usage:
 *   node scripts/sync-versions.js
 *   node scripts/sync-versions.js --version 1.5.7
 *   node scripts/sync-versions.js --latest
 *   node scripts/sync-versions.js --dry-run
 *   node scripts/sync-versions.js --help
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

// Import from other scripts
import { PLATFORM_MAPPING } from "./validate-platform-packages.js";
import {
  fetchTerraformReleases,
  filterReleases,
} from "./check-terraform-updates.js";
import {
  updateOptionalDependencies,
  validateVersion,
} from "./update-optional-deps.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function printUsage() {
  console.log(`
Usage: node scripts/sync-versions.js [options]

Options:
  --version <version>   Sync to a specific Terraform version (e.g., 1.5.7)
  --latest              Sync to the latest available Terraform version
  --main-to-platforms   Update platform packages to match main package version
  --platforms-to-main   Update main package to match platform packages version
  --check               Check current version synchronization status
  --dry-run             Preview changes without making modifications
  --force               Skip confirmations and validation prompts
  --backup              Create backup before making changes (default: true)
  --no-backup           Skip creating backup
  --help, -h           Show this help message

Examples:
  node scripts/sync-versions.js --check
  node scripts/sync-versions.js --latest --dry-run
  node scripts/sync-versions.js --version 1.6.0
  node scripts/sync-versions.js --main-to-platforms
  node scripts/sync-versions.js --latest --force --no-backup

Description:
  This script helps synchronize versions across the main package and all
  platform-specific packages. It can fetch the latest Terraform version,
  update package.json, and ensure consistency across all dependencies.
  
  By default, it will analyze the current state and suggest actions.
`);
}

function getCurrentVersions() {
  const packageJsonPath = path.join(__dirname, "..", "package.json");

  try {
    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
    const optionalDeps = packageJson.optionalDependencies || {};

    const terraformPackages = Object.keys(optionalDeps).filter((pkg) =>
      pkg.startsWith("@jahed/terraform-")
    );

    const platformVersions = {};
    terraformPackages.forEach((pkg) => {
      platformVersions[pkg] = optionalDeps[pkg];
    });

    return {
      mainVersion: packageJson.version,
      platformVersions,
      packageJson,
    };
  } catch (error) {
    throw new Error(`Failed to read package.json: ${error.message}`);
  }
}

function analyzeVersionState(versions) {
  const { mainVersion, platformVersions } = versions;
  const platformPackages = Object.keys(platformVersions);

  if (platformPackages.length === 0) {
    return {
      status: "no-platforms",
      message: "No platform packages found in optionalDependencies",
      consistent: false,
    };
  }

  // Check if all platform packages have the same version
  const uniquePlatformVersions = [...new Set(Object.values(platformVersions))];
  const platformsConsistent = uniquePlatformVersions.length === 1;

  if (!platformsConsistent) {
    return {
      status: "platforms-inconsistent",
      message: "Platform packages have different versions",
      consistent: false,
      versions: uniquePlatformVersions,
      details: platformVersions,
    };
  }

  const platformVersion = uniquePlatformVersions[0];
  const mainMatchesPlatforms = mainVersion === platformVersion;

  return {
    status: mainMatchesPlatforms ? "synchronized" : "out-of-sync",
    message: mainMatchesPlatforms
      ? "All versions are synchronized"
      : "Main package version differs from platform packages",
    consistent: platformsConsistent,
    synchronized: mainMatchesPlatforms,
    mainVersion,
    platformVersion,
    details: {
      mainVersion,
      platformVersion,
      platformCount: platformPackages.length,
    },
  };
}

function printVersionStatus(analysis) {
  console.log("📊 Version Status Analysis:");
  console.log("===========================");

  switch (analysis.status) {
    case "synchronized":
      console.log("✅ All versions are synchronized");
      console.log(`   Main package: ${analysis.mainVersion}`);
      console.log(`   Platform packages: ${analysis.platformVersion}`);
      console.log(`   Platform count: ${analysis.details.platformCount}`);
      break;

    case "out-of-sync":
      console.log("⚠️  Versions are out of sync");
      console.log(`   Main package: ${analysis.mainVersion}`);
      console.log(`   Platform packages: ${analysis.platformVersion}`);
      console.log(`   Platform count: ${analysis.details.platformCount}`);
      break;

    case "platforms-inconsistent":
      console.error("❌ Platform packages have inconsistent versions:");
      Object.entries(analysis.details).forEach(([pkg, version]) => {
        console.error(`   ${pkg}: ${version}`);
      });
      break;

    case "no-platforms":
      console.error("❌ No platform packages found");
      break;
  }
}

async function getLatestTerraformVersion() {
  console.log("🔍 Fetching latest Terraform version...");

  try {
    const releases = await fetchTerraformReleases();
    const filtered = filterReleases(releases, { includePrerelease: false });

    if (filtered.length === 0) {
      throw new Error("No stable releases found");
    }

    const latest = filtered[0];
    console.log(`✅ Latest Terraform version: ${latest.version}`);

    const releaseDate = new Date(latest.timestamp_created).toLocaleDateString();
    console.log(`   Released: ${releaseDate}`);

    return latest.version;
  } catch (error) {
    throw new Error(`Failed to fetch latest version: ${error.message}`);
  }
}

function createBackup(packageJsonPath) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupPath = `${packageJsonPath}.sync-backup-${timestamp}`;

  try {
    fs.copyFileSync(packageJsonPath, backupPath);
    console.log(
      `💾 Backup created: ${path.relative(process.cwd(), backupPath)}`
    );
    return backupPath;
  } catch (error) {
    throw new Error(`Failed to create backup: ${error.message}`);
  }
}

function syncMainToVersion(packageJson, targetVersion) {
  const originalVersion = packageJson.version;
  packageJson.version = targetVersion;

  return {
    type: "main-version-sync",
    changes: [
      {
        package: "main",
        oldVersion: originalVersion,
        newVersion: targetVersion,
        action: "updated",
      },
    ],
  };
}

function syncPlatformsToVersion(packageJson, targetVersion) {
  const optionalDeps = packageJson.optionalDependencies || {};
  const changes = [];

  Object.keys(optionalDeps).forEach((pkg) => {
    if (pkg.startsWith("@jahed/terraform-")) {
      const oldVersion = optionalDeps[pkg];
      optionalDeps[pkg] = targetVersion;
      changes.push({
        package: pkg,
        oldVersion,
        newVersion: targetVersion,
        action: "updated",
      });
    }
  });

  return {
    type: "platform-version-sync",
    changes,
  };
}

function writePackageJson(packageJsonPath, packageJson) {
  const content = JSON.stringify(packageJson, null, 2) + "\n";
  fs.writeFileSync(packageJsonPath, content, "utf8");
}

function printChanges(results) {
  results.forEach((result) => {
    if (result.changes.length === 0) return;

    console.log(`\n📝 ${result.type}:`);
    result.changes.forEach((change) => {
      console.log(
        `   ${change.package}: ${change.oldVersion} → ${change.newVersion}`
      );
    });
  });

  const totalChanges = results.reduce(
    (sum, result) => sum + result.changes.length,
    0
  );
  console.log(`\n📈 Total changes: ${totalChanges}`);
}

function confirmChanges(message) {
  // In a real implementation, you might use readline for interactive confirmation
  // For now, we'll just log the message and assume confirmation in non-interactive mode
  console.log(`\n❓ ${message}`);
  console.log("   (Use --force to skip confirmations)");
  return true; // Simplified for this implementation
}

function parseArgs(args) {
  const options = {
    mode: "check", // check, version, latest, main-to-platforms, platforms-to-main
    version: null,
    dryRun: false,
    force: false,
    backup: true,
    help: false,
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    switch (arg) {
      case "--help":
      case "-h":
        options.help = true;
        break;
      case "--version":
        options.mode = "version";
        options.version = args[++i];
        break;
      case "--latest":
        options.mode = "latest";
        break;
      case "--main-to-platforms":
        options.mode = "main-to-platforms";
        break;
      case "--platforms-to-main":
        options.mode = "platforms-to-main";
        break;
      case "--check":
        options.mode = "check";
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--force":
        options.force = true;
        break;
      case "--backup":
        options.backup = true;
        break;
      case "--no-backup":
        options.backup = false;
        break;
    }
  }

  return options;
}

async function main() {
  const args = process.argv.slice(2);
  const options = parseArgs(args);

  if (options.help) {
    printUsage();
    process.exit(0);
  }

  console.log("🔄 Version Synchronization Tool\n");

  try {
    // Get current version state
    const versions = getCurrentVersions();
    const analysis = analyzeVersionState(versions);

    printVersionStatus(analysis);

    if (options.mode === "check") {
      if (analysis.status === "synchronized") {
        console.log("\n✨ All versions are synchronized!");
        process.exit(0);
      } else {
        console.log("\n💡 Suggested actions:");
        if (analysis.status === "out-of-sync") {
          console.log("   - Sync main to platforms: --main-to-platforms");
          console.log("   - Sync platforms to main: --platforms-to-main");
          console.log("   - Update to latest: --latest");
        } else if (analysis.status === "platforms-inconsistent") {
          console.log("   - Fix platform consistency first");
          console.log("   - Then sync to desired version: --version X.Y.Z");
        }
        process.exit(1);
      }
    }

    // Determine target version based on mode
    let targetVersion;
    const results = [];

    switch (options.mode) {
      case "version":
        if (!options.version) {
          console.error("❌ Version is required when using --version");
          process.exit(1);
        }
        targetVersion = validateVersion(options.version);
        break;

      case "latest":
        targetVersion = await getLatestTerraformVersion();
        break;

      case "main-to-platforms":
        targetVersion = analysis.mainVersion;
        break;

      case "platforms-to-main":
        if (analysis.status === "platforms-inconsistent") {
          console.error(
            "❌ Cannot sync to platform version - platforms are inconsistent"
          );
          process.exit(1);
        }
        targetVersion = analysis.platformVersion;
        break;

      default:
        console.error(`❌ Unknown mode: ${options.mode}`);
        process.exit(1);
    }

    console.log(`\n🎯 Target version: ${targetVersion}`);

    // Determine what needs to be updated
    const packageJsonPath = path.join(__dirname, "..", "package.json");
    const packageJson = JSON.parse(JSON.stringify(versions.packageJson)); // Deep copy

    if (
      options.mode !== "platforms-to-main" &&
      analysis.mainVersion !== targetVersion
    ) {
      results.push(syncMainToVersion(packageJson, targetVersion));
    }

    if (
      options.mode !== "main-to-platforms" &&
      analysis.platformVersion !== targetVersion
    ) {
      results.push(syncPlatformsToVersion(packageJson, targetVersion));
    }

    if (results.length === 0 || results.every((r) => r.changes.length === 0)) {
      console.log(
        "\n✨ No changes needed - versions are already synchronized!"
      );
      process.exit(0);
    }

    // Show planned changes
    console.log("\n📋 Planned changes:");
    printChanges(results);

    if (options.dryRun) {
      console.log("\n🔍 Dry run completed - no files were modified");
      process.exit(0);
    }

    // Confirm changes unless forced
    if (!options.force) {
      const confirmed = confirmChanges("Proceed with these changes?");
      if (!confirmed) {
        console.log("❌ Operation cancelled");
        process.exit(0);
      }
    }

    // Create backup if requested
    if (options.backup) {
      createBackup(packageJsonPath);
    }

    // Apply changes
    writePackageJson(packageJsonPath, packageJson);

    console.log("\n✅ Successfully synchronized versions!");
    console.log("\n💡 Next steps:");
    console.log("   1. Review changes: git diff package.json");
    console.log("   2. Test installation: npm install");
    console.log(
      "   3. Run validation: node scripts/validate-platform-packages.js"
    );
  } catch (error) {
    console.error(`\n💥 Error: ${error.message}`);
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

export {
  getCurrentVersions,
  analyzeVersionState,
  getLatestTerraformVersion,
  syncMainToVersion,
  syncPlatformsToVersion,
  parseArgs,
};
