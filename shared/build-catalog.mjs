import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { product, categories, tools, notchModules, counts } from "./catalog.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");

// Sanity: the storefront promises 94 tools and 24 notch modules.
const expected = { tools: 94, notch: 24 };
for (const [key, value] of Object.entries(expected)) {
  const actual = counts[key];
  if (actual !== value) {
    console.error(`catalog error: expected ${value} ${key}, found ${actual}`);
    process.exitCode = 1;
  }
}

const slugs = new Set();
for (const tool of tools) {
  if (slugs.has(tool.slug)) {
    console.error(`duplicate slug: ${tool.slug}`);
    process.exitCode = 1;
  }
  slugs.add(tool.slug);
  if (!categories.some((c) => c.id === tool.category)) {
    console.error(`unknown category on ${tool.slug}: ${tool.category}`);
    process.exitCode = 1;
  }
}

const payload = {
  product,
  categories,
  tools,
  notchModules,
  counts,
  generatedAt: new Date().toISOString(),
};

const json = JSON.stringify(payload, null, 2) + "\n";
const outputs = [
  join(root, "shared", "catalog.json"),
  join(root, "apps", "nookit", "Sources", "Nookit", "Resources", "catalog.json"),
  join(root, "web", "lib", "catalog.json"),
];
for (const out of outputs) {
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, json);
  console.log("wrote", out);
}

console.log(
  `${counts.tools} tools · ${counts.implementedTools} implemented · ${counts.notch} notch modules`,
);
