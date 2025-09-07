#!/usr/bin/env node

import { spawn } from "child_process";
import { resolveTerraformBinary } from "../src/binaryResolver.js";

const args = process.argv.slice(2);

try {
  // Use the new esbuild-style binary resolution system
  // This tries platform packages first, then falls back to download
  const terraformPath = await resolveTerraformBinary();

  const terraform = spawn(terraformPath, args, {
    stdio: [process.stdin, process.stdout, process.stderr],
  });

  terraform.on("close", (code) => process.exit(code || undefined));
} catch (error) {
  console.error(error);
  process.exit(1);
}