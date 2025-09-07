const { spawn } = require("child_process");
const { resolveTerraformBinary } = require("./binaryResolver");

const cli = async () => {
  const args = process.argv.slice(2);

  // Use the new esbuild-style binary resolution system
  // This tries platform packages first, then falls back to download
  const terraformPath = await resolveTerraformBinary();

  const terraform = spawn(terraformPath, args, {
    stdio: [process.stdin, process.stdout, process.stderr],
  });

  terraform.on("close", (code) => process.exit(code || undefined));
};

cli().catch((error) => {
  console.error(error);
  process.exit(1);
});