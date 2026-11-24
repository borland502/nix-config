#!/usr/bin/env bun
import { z } from "zod";
import { VERSION, parseArgs, usage } from "./args";
import type { Opts } from "./args";
import { ScanError, pw, open, pace, evaluate, guardChallenge } from "./browser";
import { SearchRow, ItemRow, SEARCH_JS, ITEM_JS, SEARCH_URL, ITEM_URL } from "./sites";
import type { Site } from "./sites";

function isSite(s: string): s is Site {
  return s === "amazon" || s === "ebay";
}

async function cmdSearch(site: Site, query: string, o: Opts): Promise<void> {
  await open(SEARCH_URL[site](query), o);
  await guardChallenge(o);
  const rows = await evaluate(SEARCH_JS[site](o.limit), z.array(SearchRow), o);
  if (o.json) { console.log(JSON.stringify(rows, null, 2)); return; }
  for (const r of rows) {
    if (!r.price || r.oos) continue;
    console.log([r.price, r.id ?? "-", (r.title ?? "").slice(0, 88)].join("\t"));
  }
}

async function cmdItem(site: Site, ids: string[], o: Opts): Promise<void> {
  const results: ItemRow[] = [];
  for (const [i, id] of ids.entries()) {
    if (i > 0) await pace(o.delay);
    await open(ITEM_URL[site](id), o);
    await guardChallenge(o);
    const r = await evaluate(ITEM_JS[site], ItemRow, o);
    results.push({ id, ...r });
    if (!o.json) {
      console.log(
        [ id, r.price ?? "-", r.barebone ? "BAREBONE" : "configured",
          r.cpu ?? "-", r.ram ?? "-", r.ssd ?? "-", r.ports ?? "-",
          (r.title ?? "").slice(0, 60) ].join("\t"),
      );
    }
  }
  if (o.json) console.log(JSON.stringify(results, null, 2));
}

const args = Bun.argv.slice(2);
if (args.includes("--help") || args.includes("-h")) { usage(); process.exit(0); }
if (args.includes("--version") || args.includes("-V")) { console.log(VERSION); process.exit(0); }
try {
  const { cmd, rest, opts } = parseArgs(args);

  if (!cmd) { usage(); process.exit(1); }

  if (cmd === "close") {
    await pw(["close", `-s=${opts.session}`]);
    console.log(`session ${opts.session} closed`);
    process.exit(0);
  }

  const site = rest[0];
  if (!site || !isSite(site)) {
    console.error(`shop-scan: first argument must be "amazon" or "ebay"`);
    process.exit(1);
  }

  if (cmd === "search") {
    const q = rest.slice(1).join(" ");
    if (!q) { console.error("shop-scan: search needs a query"); process.exit(1); }
    await cmdSearch(site, q, opts);
  } else if (cmd === "item") {
    const ids = rest.slice(1);
    if (!ids.length) { console.error("shop-scan: item needs at least one id"); process.exit(1); }
    await cmdItem(site, ids, opts);
  } else {
    usage();
    process.exit(1);
  }

} catch (error) {
  console.error(`shop-scan: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(error instanceof ScanError ? error.exitCode : 1);
}
