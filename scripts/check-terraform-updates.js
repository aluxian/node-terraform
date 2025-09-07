#!/usr/bin/env node

/**
 * Script to check HashiCorp releases API for new Terraform versions
 * Compares against current optionalDependencies versions in package.json
 *
 * Usage:
 *   node scripts/check-terraform-updates.js
 *   node scripts/check-terraform-updates.js --check
 *   node scripts/check-terraform-updates.js --list
 *   node scripts/check-terraform-updates.js --latest
 *   node scripts/check-terraform-updates.js --help
 */

import fs from "fs";
import path from "path";
import https from "https";
import { fileURLToPath } from "url";

// Import platform mapping from existing validation script
import { PLATFORM_MAPPING } from "./validate-platform-packages.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function printUsage() {
  console.log(`
Usage: node scripts/check-terraform-updates.js [options]

Options:
  --check               Check if updates are available (default)
  --list [limit]        List available versions (optionally limit results)
  --latest              Show only the latest version
  --include-prerelease  Include pre-release versions (alpha, beta, rc)
  --help, -h           Show this help message
  --timeout <ms>       HTTP request timeout in milliseconds (default: 10000)
  --format <format>    Output format: table, json, simple (default: table)

Examples:
  node scripts/check-terraform-updates.js
  node scripts/check-terraform-updates.js --latest
  node scripts/check-terraform-updates.js --list 10
  node scripts/check-terraform-updates.js --check --format json
  node scripts/check-terraform-updates.js --include-prerelease

Description:
  This script checks the HashiCorp releases API for new Terraform versions
  and compares them against the current versions in package.json.
  
  The script handles API rate limiting and provides comprehensive error
  handling for network issues.
`);
}

function makeHttpRequest(url, timeout = 10000) {
  return new Promise((resolve, reject) => {
    const request = https.get(
      url,
      {
        headers: {
          "User-Agent": "node-terraform-version-checker/1.0.0",
          Accept: "application/json",
        },
        timeout,
      },
      (response) => {
        let data = "";

        response.on("data", (chunk) => {
          data += chunk;
        });

        response.on("end", () => {
          if (response.statusCode === 200) {
            try {
              resolve(JSON.parse(data));
            } catch (error) {
              reject(
                new Error(`Failed to parse JSON response: ${error.message}`)
              );
            }
          } else if (response.statusCode === 429) {
            reject(
              new Error(
                "Rate limited by HashiCorp API. Please try again later."
              )
            );
          } else {
            reject(
              new Error(
                `HTTP ${response.statusCode}: ${response.statusMessage}`
              )
            );
          }
        });
      }
    );

    request.on("timeout", () => {
      request.destroy();
      reject(new Error(`Request timed out after ${timeout}ms`));
    });

    request.on("error", (error) => {
      reject(new Error(`Network error: ${error.message}`));
    });
  });
}

async function fetchTerraformReleases() {
  const url = "https://api.releases.hashicorp.com/v1/releases/terraform";

  console.log("🌐 Fetching Terraform releases from HashiCorp API...");

  try {
    const data = await makeHttpRequest(url);

    if (!data || !Array.isArray(data)) {
      throw new Error("Invalid API response format");
    }

    console.log(`✅ Successfully fetched ${data.length} releases`);
    return data;
  } catch (error) {
    console.error(`❌ Failed to fetch releases: ${error.message}`);

    if (error.message.includes("Rate limited")) {
      console.error(
        "💡 Tip: The HashiCorp API has rate limits. Try again in a few minutes."
      );
    } else if (
      error.message.includes("Network error") ||
      error.message.includes("timeout")
    ) {
      console.error("💡 Tip: Check your internet connection and try again.");
    }

    throw error;
  }
}

function parseVersion(version) {
  const match = version.match(/^(\d+)\.(\d+)\.(\d+)(?:-(.+))?$/);
  if (!match) return null;

  return {
    major: parseInt(match[1]),
    minor: parseInt(match[2]),
    patch: parseInt(match[3]),
    prerelease: match[4] || null,
    original: version,
  };
}

function compareVersions(a, b) {
  const vA = parseVersion(a);
  const vB = parseVersion(b);

  if (!vA || !vB) return 0;

  // Compare major.minor.patch
  if (vA.major !== vB.major) return vB.major - vA.major;
  if (vA.minor !== vB.minor) return vB.minor - vA.minor;
  if (vA.patch !== vB.patch) return vB.patch - vA.patch;

  // Handle pre-release versions
  if (vA.prerelease && !vB.prerelease) return 1;
  if (!vA.prerelease && vB.prerelease) return -1;
  if (vA.prerelease && vB.prerelease) {
    return vB.prerelease.localeCompare(vA.prerelease);
  }

  return 0;
}

function filterReleases(releases, options) {
  let filtered = releases.filter((release) => {
    // Filter out pre-releases unless explicitly requested
    if (!options.includePrerelease && release.version.includes("-")) {
      return false;
    }

    // Ensure version is valid
    return parseVersion(release.version) !== null;
  });

  // Sort by version (newest first)
  filtered.sort((a, b) => compareVersions(a.version, b.version));

  return filtered;
}

function getCurrentVersion() {
  const packageJsonPath = path.join(__dirname, "..", "package.json");

  try {
    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
    const optionalDeps = packageJson.optionalDependencies || {};

    // Get version from any platform package (they should all be the same)
    const platformPackages = Object.keys(optionalDeps).filter((pkg) =>
      pkg.startsWith("@jahed/terraform-")
    );

    if (platformPackages.length === 0) {
      return null;
    }

    return optionalDeps[platformPackages[0]];
  } catch (error) {
    console.warn(
      `⚠️  Could not read current version from package.json: ${error.message}`
    );
    return null;
  }
}

function formatTable(data, headers) {
  if (data.length === 0) return "";

  // Calculate column widths
  const widths = headers.map((header, i) => {
    const values = [header, ...data.map((row) => String(row[i] || ""))];
    return Math.max(...values.map((v) => v.length));
  });

  // Create rows
  const rows = [];

  // Header row
  const headerRow = headers
    .map((header, i) => header.padEnd(widths[i]))
    .join(" │ ");
  rows.push(headerRow);

  // Separator
  const separator = widths.map((width) => "─".repeat(width)).join("─┼─");
  rows.push(separator);

  // Data rows
  data.forEach((row) => {
    const dataRow = row
      .map((cell, i) => String(cell || "").padEnd(widths[i]))
      .join(" │ ");
    rows.push(dataRow);
  });

  return rows.join("\n");
}

function outputResults(releases, currentVersion, options) {
  if (options.format === "json") {
    const output = {
      current_version: currentVersion,
      releases: releases.map((r) => ({
        version: r.version,
        timestamp_created: r.timestamp_created,
        url: r.url_shasums,
      })),
    };
    console.log(JSON.stringify(output, null, 2));
    return;
  }

  if (options.format === "simple") {
    releases.forEach((release) => {
      console.log(release.version);
    });
    return;
  }

  // Table format (default)
  if (releases.length === 0) {
    console.log("No releases found matching criteria");
    return;
  }

  const headers = ["Version", "Date", "Status"];
  const data = releases.map((release) => {
    const date = new Date(release.timestamp_created)
      .toISOString()
      .split("T")[0];
    let status = "";

    if (currentVersion) {
      const comparison = compareVersions(release.version, currentVersion);
      if (comparison < 0) status = "🆕 Newer";
      else if (comparison === 0) status = "📌 Current";
      else status = "⬇️  Older";
    }

    return [release.version, date, status];
  });

  console.log("\n" + formatTable(data, headers));
}

function checkForUpdates(releases, currentVersion) {
  if (!currentVersion) {
    console.log("⚠️  No current version found in package.json");
    return { hasUpdates: false, updateCount: 0 };
  }

  const newerReleases = releases.filter(
    (release) => compareVersions(release.version, currentVersion) < 0
  );

  console.log(`\n📊 Update Check Results:`);
  console.log(`Current version: ${currentVersion}`);
  console.log(`Available updates: ${newerReleases.length}`);

  if (newerReleases.length > 0) {
    console.log(`Latest version: ${newerReleases[0].version}`);

    const latestDate = new Date(
      newerReleases[0].timestamp_created
    ).toLocaleDateString();
    console.log(`Released: ${latestDate}`);

    console.log("\n🔄 To update to the latest version, run:");
    console.log(
      `node scripts/update-optional-deps.js ${newerReleases[0].version}`
    );
  } else {
    console.log("\n✅ You are using the latest version!");
  }

  return {
    hasUpdates: newerReleases.length > 0,
    updateCount: newerReleases.length,
    latestVersion:
      newerReleases.length > 0 ? newerReleases[0].version : currentVersion,
  };
}

function parseArgs(args) {
  const options = {
    mode: "check", // check, list, latest
    limit: null,
    includePrerelease: false,
    help: false,
    timeout: 10000,
    format: "table", // table, json, simple
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    switch (arg) {
      case "--help":
      case "-h":
        options.help = true;
        break;
      case "--check":
        options.mode = "check";
        break;
      case "--list":
        options.mode = "list";
        // Check if next arg is a number (limit)
        if (args[i + 1] && !isNaN(parseInt(args[i + 1]))) {
          options.limit = parseInt(args[++i]);
        }
        break;
      case "--latest":
        options.mode = "latest";
        break;
      case "--include-prerelease":
        options.includePrerelease = true;
        break;
      case "--timeout":
        options.timeout = parseInt(args[++i]) || 10000;
        break;
      case "--format":
        const format = args[++i];
        if (["table", "json", "simple"].includes(format)) {
          options.format = format;
        } else {
          console.error(
            `❌ Invalid format: ${format}. Use: table, json, simple`
          );
          process.exit(1);
        }
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

  console.log("🔍 Terraform Version Checker\n");

  try {
    // Fetch releases from API
    const allReleases = await fetchTerraformReleases();

    // Filter releases based on options
    const filteredReleases = filterReleases(allReleases, options);

    // Get current version
    const currentVersion = getCurrentVersion();

    if (currentVersion) {
      console.log(`📌 Current version: ${currentVersion}`);
    }

    // Apply limit if specified
    const releases = options.limit
      ? filteredReleases.slice(0, options.limit)
      : filteredReleases;

    // Handle different modes
    switch (options.mode) {
      case "latest":
        if (releases.length > 0) {
          if (options.format === "simple") {
            console.log(releases[0].version);
          } else {
            console.log(
              `\n🚀 Latest Terraform version: ${releases[0].version}`
            );
            const date = new Date(
              releases[0].timestamp_created
            ).toLocaleDateString();
            console.log(`📅 Released: ${date}`);
          }
        } else {
          console.log("No releases found");
        }
        break;

      case "list":
        console.log(
          `\n📋 Available Terraform versions (showing ${releases.length}):`
        );
        outputResults(releases, currentVersion, options);
        break;

      case "check":
      default:
        const result = checkForUpdates(releases, currentVersion);

        if (options.format === "json") {
          console.log(JSON.stringify(result, null, 2));
        }

        // Exit with appropriate code for CI/CD usage
        process.exit(result.hasUpdates ? 1 : 0);
    }
  } catch (error) {
    console.error(`\n💥 Error: ${error.message}`);
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

export {
  fetchTerraformReleases,
  parseVersion,
  compareVersions,
  filterReleases,
  getCurrentVersion,
  checkForUpdates,
  parseArgs,
};
