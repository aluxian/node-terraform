#!/usr/bin/env node

/**
 * Script to update the main package.json optionalDependencies with a specific terraform version
 * Updates all platform package dependencies to the specified version
 *
 * Usage:
 *   node scripts/update-optional-deps.js 1.5.7
 *   node scripts/update-optional-deps.js --version 1.5.7
 *   node scripts/update-optional-deps.js --help
 */

const fs = require("fs");
const path = require("path");

// Import platform mapping from existing validation script
const { PLATFORM_MAPPING } = require("./validate-platform-packages");

function printUsage() {
  console.log(`
Usage: node scripts/update-optional-deps.js <version>

Options:
  <version>              The Terraform version to set (e.g., 1.5.7)
  --version <version>    The Terraform version to set (alternative syntax)
  --help, -h            Show this help message
  --dry-run             Preview changes without writing to package.json
  --backup              Create backup before making changes (default: true)
  --no-backup           Skip creating backup

Examples:
  node scripts/update-optional-deps.js 1.5.7
  node scripts/update-optional-deps.js --version 1.5.7 --dry-run
  node scripts/update-optional-deps.js 1.6.0 --no-backup

Description:
  This script updates the optionalDependencies in package.json to use the
  specified Terraform version across all platform-specific packages.
  
  A backup of the original package.json is created by default unless
  --no-backup is specified.
`);
}

function validateVersion(version) {
  if (!version) {
    console.error("❌ Error: Version is required");
    printUsage();
    process.exit(1);
  }

  // Basic semantic version validation
  const semverRegex = /^\d+\.\d+\.\d+(-[\w.-]+)?(\+[\w.-]+)?$/;
  if (!semverRegex.test(version)) {
    console.error(`❌ Error: Invalid semantic version format: ${version}`);
    console.error("Expected format: X.Y.Z (e.g., 1.5.7)");
    process.exit(1);
  }

  console.log(`✅ Valid version format: ${version}`);
  return version;
}

function createBackup(packageJsonPath) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupPath = `${packageJsonPath}.backup-${timestamp}`;

  try {
    fs.copyFileSync(packageJsonPath, backupPath);
    console.log(
      `📦 Backup created: ${path.relative(process.cwd(), backupPath)}`
    );
    return backupPath;
  } catch (error) {
    console.error(`❌ Failed to create backup: ${error.message}`);
    process.exit(1);
  }
}

function loadPackageJson(packageJsonPath) {
  try {
    const content = fs.readFileSync(packageJsonPath, "utf8");
    return JSON.parse(content);
  } catch (error) {
    console.error(`❌ Failed to read package.json: ${error.message}`);
    process.exit(1);
  }
}

function updateOptionalDependencies(packageJson, version) {
  const optionalDeps = packageJson.optionalDependencies || {};
  const expectedPackages = Object.values(PLATFORM_MAPPING).map((p) => p.npm);

  let updatedCount = 0;
  let addedCount = 0;
  const changes = [];

  // Update existing platform packages
  Object.keys(optionalDeps).forEach((pkg) => {
    if (pkg.startsWith("@jahed/terraform-")) {
      const oldVersion = optionalDeps[pkg];
      optionalDeps[pkg] = version;
      changes.push({
        package: pkg,
        oldVersion,
        newVersion: version,
        action: "updated",
      });
      updatedCount++;
    }
  });

  // Add missing platform packages
  expectedPackages.forEach((pkg) => {
    if (!optionalDeps[pkg]) {
      optionalDeps[pkg] = version;
      changes.push({
        package: pkg,
        oldVersion: null,
        newVersion: version,
        action: "added",
      });
      addedCount++;
    }
  });

  packageJson.optionalDependencies = optionalDeps;

  return {
    updatedPackageJson: packageJson,
    changes,
    stats: {
      updated: updatedCount,
      added: addedCount,
      total: updatedCount + addedCount,
    },
  };
}

function writePackageJson(packageJsonPath, packageJson) {
  try {
    const content = JSON.stringify(packageJson, null, 2) + "\n";
    fs.writeFileSync(packageJsonPath, content, "utf8");
    console.log(`✅ Updated: ${path.relative(process.cwd(), packageJsonPath)}`);
  } catch (error) {
    console.error(`❌ Failed to write package.json: ${error.message}`);
    process.exit(1);
  }
}

function printChanges(changes, stats) {
  console.log("\n📊 Changes Summary:");
  console.log("==================");

  if (changes.length === 0) {
    console.log(
      "No changes needed - all packages already at specified version"
    );
    return;
  }

  // Group changes by action
  const updated = changes.filter((c) => c.action === "updated");
  const added = changes.filter((c) => c.action === "added");

  if (updated.length > 0) {
    console.log(`\n🔄 Updated packages (${updated.length}):`);
    updated.forEach((change) => {
      console.log(
        `   ${change.package}: ${change.oldVersion} → ${change.newVersion}`
      );
    });
  }

  if (added.length > 0) {
    console.log(`\n➕ Added packages (${added.length}):`);
    added.forEach((change) => {
      console.log(`   ${change.package}: ${change.newVersion}`);
    });
  }

  console.log(`\n📈 Total changes: ${stats.total} packages`);
}

function parseArgs(args) {
  const options = {
    version: null,
    dryRun: false,
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
        options.version = args[++i];
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--backup":
        options.backup = true;
        break;
      case "--no-backup":
        options.backup = false;
        break;
      default:
        // If it's not a flag and we don't have a version yet, use it as version
        if (!options.version && !arg.startsWith("--")) {
          options.version = arg;
        }
        break;
    }
  }

  return options;
}

function main() {
  const args = process.argv.slice(2);
  const options = parseArgs(args);

  if (options.help) {
    printUsage();
    process.exit(0);
  }

  console.log("🔧 Update Optional Dependencies\n");

  const version = validateVersion(options.version);
  const packageJsonPath = path.join(__dirname, "..", "package.json");

  console.log(`📁 Package: ${path.relative(process.cwd(), packageJsonPath)}`);
  console.log(`🎯 Target version: ${version}`);
  console.log(
    `🏃 Mode: ${options.dryRun ? "Dry run (preview only)" : "Live update"}`
  );
  console.log(`💾 Backup: ${options.backup ? "Enabled" : "Disabled"}`);

  // Load and validate package.json
  const packageJson = loadPackageJson(packageJsonPath);

  // Update optional dependencies
  const result = updateOptionalDependencies(packageJson, version);

  // Print changes
  printChanges(result.changes, result.stats);

  if (options.dryRun) {
    console.log("\n🔍 Dry run completed - no files were modified");
    process.exit(0);
  }

  if (result.stats.total === 0) {
    console.log("\n✨ No changes needed");
    process.exit(0);
  }

  // Create backup if enabled
  if (options.backup) {
    createBackup(packageJsonPath);
  }

  // Write updated package.json
  writePackageJson(packageJsonPath, result.updatedPackageJson);

  console.log("\n🎉 Successfully updated optionalDependencies");
  console.log("\n💡 Next steps:");
  console.log("   1. Review the changes with: git diff package.json");
  console.log("   2. Test the installation: npm install");
  console.log(
    "   3. Run validation: node scripts/validate-platform-packages.js"
  );
}

if (require.main === module) {
  main();
}

module.exports = {
  validateVersion,
  updateOptionalDependencies,
  parseArgs,
  printChanges,
};
