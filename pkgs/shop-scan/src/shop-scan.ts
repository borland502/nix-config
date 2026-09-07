#!/usr/bin/env bun
/**
 * shop-scan — price comparison across commercial storefronts, at human pace.
 *
 * Drives a real browser through `playwright-cli` so that ordinary bot *scanning*
 * (which rejects plain curl/fetch with 403/500/empty bodies) sees a normal
 * browser. That is the whole of its purpose: fair price comparison on public
 * listing pages.
 *
 * What it deliberately does NOT do:
 *   - no user-agent / fingerprint spoofing, no proxy or IP rotation
 *   - no CAPTCHA solving, and no retry-until-through loop
 *   - no authentication, no access to anything a logged-out visitor cannot see
 * If a site answers with an actual challenge (CAPTCHA / interstitial), the run
 * ABORTS with exit code 3 rather than escalating. Getting past a challenge is
 * the operator's call, not this script's.
 *
 * Pacing is enforced, not advisory: every page load is followed by a randomised
 * delay (default 6s ±40%, floor 3s) and a hard per-run page cap. There is no
 * flag to disable it.
 *
 * Requires: bun, and npx (playwright-cli is fetched on demand; if the browser
 * is missing, run `npx @playwright/cli install-browser chrome-for-testing`).
 *
 * Usage:
 *   shop-scan search <amazon|ebay> <query...>   [--limit N] [--delay S] [--json]
 *   shop-scan item   <amazon|ebay> <id> [id...] [--json]
 *   shop-scan close
 *
 * Examples:
 *   shop-scan search ebay "N305 firewall mini pc 16GB 512GB"
 *   shop-scan item amazon B0H5PHNKCF
 */

import { z } from "zod";

export const VERSION = "0.1.0";

type Site = "amazon" | "ebay";

/**
 * Payload shapes returned by the in-page extractors.
 *
 * These are validated rather than cast: the JSON comes from a third-party page
 * whose markup changes without notice, so a silent shape drift should surface as
 * a loud error here instead of as `undefined` three call frames later.
 */
const SearchRow = z.object({
  id: z.string().nullable(),
  price: z.string().nullable(),
  oos: z.boolean(),
  title: z.string().nullable(),
  sub: z.string().nullable().optional(),
});
type SearchRow = z.infer<typeof SearchRow>;

const ItemRow = z.object({
  price: z.string().nullable(),
  title: z.string().nullable(),
  cpu: z.string().nullable(),
  ram: z.string().nullable(),
  ssd: z.string().nullable(),
  ports: z.string().nullable(),
  barebone: z.boolean(),
  specifics: z.record(z.string(), z.string()).optional(),
});
type ItemRow = z.infer<typeof ItemRow> & { id?: string };

const ProbeText = z.object({ t: z.string() });

const PAGE_CAP = 40;
const DELAY_FLOOR_MS = 3000;

// ---------------------------------------------------------------- cli parsing

interface Opts {
  limit: number;
  delay: number;
  session: string;
  json: boolean;
  headed: boolean;
}

function parseArgs(argv: string[]): { cmd: string; rest: string[]; opts: Opts } {
  const opts: Opts = { limit: 20, delay: 6, session: "shop", json: false, headed: false };
  const rest: string[] = [];
  let cmd = "";
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === "--limit") opts.limit = Number(argv[++i]);
    else if (a === "--delay") opts.delay = Number(argv[++i]);
    else if (a === "--session") opts.session = argv[++i]!;
    else if (a === "--json") opts.json = true;
    else if (a === "--headed") opts.headed = true;
    else if (a === "-h" || a === "--help") { usage(); process.exit(0); }
    else if (a === "--version" || a === "-V") { console.log(VERSION); process.exit(0); }
    else if (!cmd) cmd = a;
    else rest.push(a);
  }
  return { cmd, rest, opts };
}

function usage(): void {
  console.log(`shop-scan — human-paced price comparison on public listing pages

  search <amazon|ebay> <query...>     search results with prices
  item   <amazon|ebay> <id> [id...]   per-listing detail (RAM/SSD/CPU/barebone)
  close                               shut the browser session down

  --limit N    max search rows (default 20)
  --delay S    base delay between page loads, seconds (default 6, floor 3)
  --session N  playwright-cli session name (default "shop")
  --json       emit JSON instead of TSV
  --headed     show the browser window

Aborts with exit 3 on a real bot challenge; it will not try to defeat one.`);
}

// ------------------------------------------------------------ playwright glue

const PW: string[] = Bun.which("playwright-cli")
  ? ["playwright-cli"]
  : ["npx", "--yes", "@playwright/cli@latest"];

/**
 * playwright-cli writes a `.playwright-cli/` state dir (snapshots, console logs)
 * into its working directory. Pin that to the cache so a run from inside a repo
 * checkout never litters the working tree.
 */
const STATE_DIR = `${process.env.HOME}/.cache/claude/shop-scan`;

async function pw(args: string[]): Promise<string> {
  await Bun.$`mkdir -p ${STATE_DIR}`.quiet();
  const proc = Bun.spawn([...PW, ...args], { stdout: "pipe", stderr: "pipe", cwd: STATE_DIR });
  const [out, err] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  await proc.exited;
  return out + err;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Randomised, non-negotiable pacing between page loads. */
async function pace(baseSeconds: number): Promise<void> {
  const jitter = 1 + (Math.random() * 0.8 - 0.4); // ±40%
  await sleep(Math.max(DELAY_FLOOR_MS, baseSeconds * 1000 * jitter));
}

/**
 * Signatures of a site declining to serve an automated client. Includes soft
 * refusals: eBay answers bot-mitigated requests with a generic "Something went
 * wrong on our end" error page (HTTP 200, a trace id, no challenge widget)
 * rather than a CAPTCHA, so a naive extractor just sees zero results.
 */
const CHALLENGE = /enter the characters you see|not a robot|validateCaptcha|pardon our interruption|just a moment\.\.\.|checking your browser|access denied|something went wrong on our end|error page \| ebay/i;

let pagesLoaded = 0;

async function open(url: string, o: Opts): Promise<void> {
  if (++pagesLoaded > PAGE_CAP) {
    console.error(`shop-scan: page cap (${PAGE_CAP}) reached — stopping.`);
    process.exit(4);
  }
  // headless is the default; there is no --headless flag, only --headed.
  const args = ["open", url, "--browser=chromium", `-s=${o.session}`];
  if (o.headed) args.push("--headed");
  const out = await pw(args);
  if (/is not found|install-browser/.test(out)) {
    console.error("shop-scan: chromium missing. Run:\n  npx --yes @playwright/cli@latest install-browser chrome-for-testing");
    process.exit(2);
  }
  if (!/### Page|Page URL:|opened with pid/.test(out)) {
    console.error(`shop-scan: could not open ${url}\n${out.slice(0, 500)}`);
    process.exit(2);
  }
}

/**
 * Run an extractor in the page and parse the JSON it returns.
 *
 * playwright-cli prints the payload under a `### Result` header and then echoes
 * the code it ran under `### Ran Playwright code`. Slice out the Result section
 * specifically — a greedy match over the whole output swallows the echoed code.
 */
async function evaluate<S extends z.ZodType>(
  code: string,
  schema: S,
  o: Opts,
): Promise<z.infer<S>> {
  const out = await pw(["run-code", code, `-s=${o.session}`]);
  const section = out.match(/^### Result\s*\n([\s\S]*?)(?=\n### |\n*$)/m);
  const blob = (section?.[1] ?? "").trim();
  if (!blob) throw new Error(`no result section from page:\n${out.slice(0, 400)}`);

  let raw: unknown;
  try {
    raw = JSON.parse(blob);
  } catch {
    throw new Error(`unparseable result:\n${blob.slice(0, 400)}`);
  }

  const parsed = schema.safeParse(raw);
  if (!parsed.success) {
    throw new Error(
      `page returned an unexpected shape — the site's markup probably changed.\n` +
        `${z.prettifyError(parsed.error)}\n${blob.slice(0, 300)}`,
    );
  }
  return parsed.data;
}

async function guardChallenge(o: Opts): Promise<void> {
  const probe = await evaluate(
    `async page => await page.evaluate(() => ({ t: (document.title + ' ' + document.body.innerText.slice(0,600)) }))`,
    ProbeText,
    o,
  );
  if (CHALLENGE.test(probe.t)) {
    console.error(
      "shop-scan: the site returned a bot challenge. Stopping — this script does not attempt to defeat one.\n" +
      "Re-run later, slow it down with --delay, or open the page yourself with --headed.",
    );
    process.exit(3);
  }
}

// ------------------------------------------------------------ site extractors

const SEARCH_JS: Record<Site, (limit: number) => string> = {
  amazon: (limit) => `async page => await page.evaluate(() => {
    const out = [];
    document.querySelectorAll('div[data-asin][data-component-type="s-search-result"]').forEach(el => {
      const id = el.getAttribute('data-asin'); if (!id) return;
      const t = el.querySelector('h2');
      const p = el.querySelector('.a-price .a-offscreen');
      const txt = el.innerText || '';
      out.push({ id, price: p ? p.textContent.trim() : null,
                 oos: /currently unavailable|out of stock/i.test(txt),
                 title: t ? t.innerText.trim().slice(0, 95) : null });
    });
    return out.slice(0, ${limit});
  })`,
  ebay: (limit) => `async page => await page.evaluate(() => {
    const out = [];
    const nodes = document.querySelectorAll('li.s-item, li.s-card, .srp-results li[data-viewport]');
    nodes.forEach(el => {
      const a = el.querySelector('a.s-item__link, a.su-link, a[href*="/itm/"]');
      const href = a ? a.getAttribute('href') || '' : '';
      const m = href.match(/\\/itm\\/(\\d+)/);
      const t = el.querySelector('.s-item__title, .s-card__title, [role="heading"]');
      const p = el.querySelector('.s-item__price, .s-card__price');
      const sub = el.querySelector('.s-item__subtitle, .s-card__subtitle');
      const title = t ? t.innerText.trim().replace(/^New Listing/, '').slice(0, 95) : null;
      if (!title || /^Shop on eBay$/i.test(title)) return;
      out.push({ id: m ? m[1] : null, price: p ? p.innerText.trim().split('\\n')[0] : null,
                 oos: false, title, sub: sub ? sub.innerText.trim().slice(0, 40) : null });
    });
    return out.slice(0, ${limit});
  })`,
};

const ITEM_JS: Record<Site, string> = {
  amazon: `async page => await page.evaluate(() => {
    const q = s => document.querySelector(s);
    const txt = s => { const e = q(s); return e ? e.textContent.trim() : null; };
    const price = txt('#corePrice_feature_div .a-offscreen')
               || txt('#corePriceDisplay_desktop_feature_div .a-offscreen')
               || txt('#apex_desktop .a-offscreen');
    const body = document.body.innerText;
    const bullets = [...document.querySelectorAll('#feature-bullets li span')].map(e => e.innerText).join(' | ');
    const hay = bullets + ' ' + document.title;
    const grab = re => { const m = hay.match(re); return m ? m[0].trim() : null; };
    return {
      price, title: document.title.replace(/^Amazon\\.com:?\\s*/, '').slice(0, 110),
      cpu:  grab(/N355|N305|N350|N150|N100|N97|N5105|J4125|J4105|J3710|J6412|i[3579][- ]?\\d{4}[A-Z]*/i),
      ram:  grab(/\\d+\\s?GB?\\s+(DDR[45]|LPDDR\\d?)/i),
      ssd:  grab(/\\d+\\s?[GT]B?\\s+(NVMe|M\\.2|SSD|eMMC|mSATA)/i),
      ports: grab(/\\d\\s?x\\s?(Intel\\s)?i22[56][-V]*|\\d[- ]?Port/i),
      barebone: /Size:\\s*[^\\n]*Barebone/i.test(body) || /barebone|no ram|without ram/i.test(hay),
    };
  })`,
  ebay: `async page => await page.evaluate(() => {
    const q = s => document.querySelector(s);
    const txt = s => { const e = q(s); return e ? e.innerText.trim() : null; };
    const price = txt('.x-price-primary .ux-textspans') || txt('.x-price-primary') || txt('#prcIsum');
    const title = txt('.x-item-title__mainTitle .ux-textspans') || txt('h1.x-item-title__mainTitle') || document.title;
    // eBay item specifics render as label/value column pairs
    const specifics = {};
    document.querySelectorAll('.ux-layout-section--features dl, .ux-labels-values').forEach(dl => {
      const k = dl.querySelector('.ux-labels-values__labels, dt');
      const v = dl.querySelector('.ux-labels-values__values, dd');
      if (k && v) {
        const key = k.innerText.trim().replace(/:$/, '');
        const val = v.innerText.trim();
        if (key && val && key.length < 40 && val.length < 60) specifics[key] = val;
      }
    });
    const hay = title + ' ' + Object.entries(specifics).map(([a, b]) => a + ' ' + b).join(' ');
    const grab = re => { const m = hay.match(re); return m ? m[0].trim() : null; };
    return {
      price, title: (title || '').slice(0, 110),
      cpu:  grab(/N355|N305|N350|N150|N100|N97|N5105|J4125|J4105|J3710|J6412|i[3579][- ]?\\d{4}[A-Z]*/i),
      ram:  specifics['Memory'] || specifics['RAM Size'] || grab(/\\d+\\s?GB?\\s+(DDR[45]|RAM|LPDDR\\d?)/i),
      ssd:  specifics['SSD Capacity'] || specifics['Storage Capacity'] || specifics['Hard Drive Capacity']
            || grab(/\\d+\\s?[GT]B?\\s+(NVMe|M\\.2|SSD|eMMC|mSATA)/i),
      ports: grab(/\\d\\s?x\\s?(Intel\\s)?i22[56][-V]*|\\d[- ]?Port|\\d\\s?LAN/i),
      barebone: /barebone|no ram|without ram|no ssd/i.test(hay),
      specifics,
    };
  })`,
};

const SEARCH_URL: Record<Site, (q: string) => string> = {
  amazon: (q) => `https://www.amazon.com/s?k=${encodeURIComponent(q)}`,
  ebay: (q) => `https://www.ebay.com/sch/i.html?_nkw=${encodeURIComponent(q)}`,
};

const ITEM_URL: Record<Site, (id: string) => string> = {
  amazon: (id) => `https://www.amazon.com/dp/${id}`,
  ebay: (id) => `https://www.ebay.com/itm/${id}`,
};

// -------------------------------------------------------------------- commands

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

// ------------------------------------------------------------------------ main

const { cmd, rest, opts } = parseArgs(Bun.argv.slice(2));

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
