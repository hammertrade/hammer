#!/usr/bin/env node
// Rebrand the whole project in one go: name, ticker, domain, X handle, GitHub repo.
//
//   node tools/rebrand.mjs --name Hammer --ticker HAMMER --domain hammertrade.xyz --x HammerTradeXYZ --github you/hammer
//
// The current values live in brand.json; the script swaps them for the new ones everywhere
// (site, locales, relayer, contracts, scripts, docs) and then rewrites brand.json.
// LICENSE is never touched: MIT requires the original copyright notice to stay.
//
// Contracts: the name is the EIP-712 domain name traders sign against. Rebrand BEFORE you deploy;
// changing it after deployment breaks every signature the site makes.

import { readFileSync, writeFileSync, readdirSync, statSync } from "node:fs";
import { join, relative, extname } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const brandFile = join(root, "brand.json");
const current = JSON.parse(readFileSync(brandFile, "utf8"));

const args = Object.fromEntries(
  process.argv.slice(2).join(" ").split(/\s*--/).filter(Boolean).map((a) => {
    const [k, ...v] = a.split(/\s+/);
    return [k, v.join(" ")];
  }),
);
const next = {
  name: args.name ?? current.name,
  ticker: (args.ticker ?? current.ticker).toUpperCase(),
  domain: args.domain ?? current.domain,
  x: (args.x ?? current.x).replace(/^@/, ""),
  github: args.github ?? current.github,
};

if (next.name.length > 31) throw new Error("name must fit in 31 bytes (it is a Solidity short string)");

const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
// Order matters: longer, more specific strings first.
const rules = [
  [new RegExp(escape(current.github), "g"), next.github],
  [new RegExp(escape(current.domain), "g"), next.domain],
  [new RegExp(`\\b${escape(current.x)}\\b`, "g"), next.x],
  [new RegExp(`\\b${escape(current.ticker)}\\b`, "g"), next.ticker],
  [new RegExp(`\\b${escape(current.name)}\\b`, "g"), next.name],
  // Lower case: server paths, service and key folder names (/opt/hammer, hammer-relayer, ~/keys/hammer-eth).
  [new RegExp(`\\b${escape(current.name.toLowerCase())}\\b`, "g"), next.name.toLowerCase()],
];

const skipDirs = new Set([".git", "node_modules", "out", "cache", "dist", "deployable", "data", "broadcast"]);
// Foundry's libraries live in the top-level lib/; web/src/lib is the site's own code and is rebranded.
const skipPaths = new Set([join(root, "lib")]);
// Files left as they are: the licence, the notes, the theme script.
const skipFiles = new Set(["LICENSE", "brand.json", "rebrand.mjs", "package-lock.json", "darken.py", "launch.sh"]); // launch.sh runs rebrand while bash is still reading it
const textExt = new Set([".ts", ".tsx", ".mjs", ".js", ".json", ".jsonc", ".sol", ".md", ".html", ".css", ".svg", ".toml", ".service", ".sh", ".headers", ".example", ".production", ""]);

let changed = 0;
function walk(dir) {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    const st = statSync(path);
    if (st.isDirectory()) { if (!skipDirs.has(entry) && !skipPaths.has(path) && !/^(cache|out)-/.test(entry)) walk(path); continue; }
    if (skipFiles.has(entry)) continue;
    const ext = entry.startsWith(".env") ? "" : extname(entry);
    if (!textExt.has(ext)) continue;
    const before = readFileSync(path, "utf8");
    let after = before;
    for (const [re, to] of rules) after = after.replace(re, to);
    if (after !== before) { writeFileSync(path, after); changed++; console.log("  " + relative(root, path)); }
  }
}

walk(root);
writeFileSync(brandFile, JSON.stringify(next, null, 2) + "\n");
console.log(`\n${changed} files: ${current.name}/${current.ticker} -> ${next.name}/${next.ticker}, ${next.domain}, @${next.x}, ${next.github}`);
