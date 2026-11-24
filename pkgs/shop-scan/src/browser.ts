import { z } from "zod";
import type { Opts } from "./args";
import { ProbeText } from "./sites";

const PAGE_CAP = 40;
const DELAY_FLOOR_MS = 3000;
export class ScanError extends Error {
  constructor(message: string, public readonly exitCode: number) { super(message); }
}

export const PLAYWRIGHT_CLI_VERSION = "0.1.25";
const PW: string[] = Bun.which("playwright-cli")
  ? ["playwright-cli"]
  : ["npx", "--yes", `@playwright/cli@${PLAYWRIGHT_CLI_VERSION}`];

/**
 * playwright-cli writes a `.playwright-cli/` state dir (snapshots, console logs)
 * into its working directory. Pin that to the cache so a run from inside a repo
 * checkout never litters the working tree.
 */
const STATE_DIR = `${process.env.HOME}/.cache/claude/shop-scan`;

export async function pw(args: string[]): Promise<string> {
  await Bun.$`mkdir -p ${STATE_DIR}`.quiet();
  let proc: ReturnType<typeof Bun.spawn<"pipe", "pipe", "pipe">>;
  try {
    proc = Bun.spawn([...PW, ...args], { stdout: "pipe", stderr: "pipe", cwd: STATE_DIR });
  } catch (error) {
    const detail = (error instanceof Error ? error.message : String(error)).slice(0, 500);
    throw new ScanError(`could not launch playwright-cli via ${PW[0]}: ${detail}`, 2);
  }
  const [out, err] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const status = await proc.exited;
  if (status !== 0) {
    const detail = (err.trim() || out.trim()).slice(0, 500);
    const hint = /is not found|install-browser/i.test(err + out)
      ? `\nInstall Chromium with: npx --yes @playwright/cli@${PLAYWRIGHT_CLI_VERSION} install-browser chrome-for-testing` : "";
    throw new ScanError(`playwright-cli ${args[0]} failed (exit ${status})${detail ? `: ${detail}` : ""}${hint}`, 2);
  }
  if (err) process.stderr.write(err);
  return out;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Randomised, non-negotiable pacing between page loads. */
export async function pace(baseSeconds: number, wait = sleep, random = Math.random): Promise<void> {
  const jitter = 1 + (random() * 0.8 - 0.4); // ±40%
  await wait(Math.max(DELAY_FLOOR_MS, baseSeconds * 1000 * jitter));
}

/**
 * Signatures of a site declining to serve an automated client. Includes soft
 * refusals: eBay answers bot-mitigated requests with a generic "Something went
 * wrong on our end" error page (HTTP 200, a trace id, no challenge widget)
 * rather than a CAPTCHA, so a naive extractor just sees zero results.
 */
const CHALLENGE = /enter the characters you see|not a robot|validateCaptcha|pardon our interruption|just a moment\.\.\.|checking your browser|access denied|something went wrong on our end|error page \| ebay/i;

let pagesLoaded = 0;

export async function open(url: string, o: Opts, run = pw): Promise<void> {
  if (++pagesLoaded > PAGE_CAP) {
    throw new ScanError(`page cap (${PAGE_CAP}) reached — stopping.`, 4);
  }
  // headless is the default; there is no --headless flag, only --headed.
  const args = ["open", url, "--browser=chromium", `-s=${o.session}`];
  if (o.headed) args.push("--headed");
  const out = await run(args);
  if (/is not found|install-browser/i.test(out)) {
    throw new ScanError(`chromium missing. Run:\n  npx --yes @playwright/cli@${PLAYWRIGHT_CLI_VERSION} install-browser chrome-for-testing`, 2);
  }
  if (!/### Page|Page URL:|opened with pid/.test(out)) {
    throw new ScanError(`could not open ${url}\n${out.slice(0, 500)}`, 2);
  }
}

/**
 * Run an extractor in the page and parse the JSON it returns.
 *
 * playwright-cli prints the payload under a `### Result` header and then echoes
 * the code it ran under `### Ran Playwright code`. Slice out the Result section
 * specifically — a greedy match over the whole output swallows the echoed code.
 */
export async function evaluate<S extends z.ZodType>(
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

export async function guardChallenge(o: Opts): Promise<void> {
  const probe = await evaluate(
    `async page => await page.evaluate(() => ({ t: (document.title + ' ' + document.body.innerText.slice(0,600)) }))`,
    ProbeText,
    o,
  );
  if (CHALLENGE.test(probe.t)) {
    throw new ScanError(
      "the site returned a bot challenge. Stopping — this script does not attempt to defeat one.\n" +
      "Re-run later, slow it down with --delay, or open the page yourself with --headed.", 3,
    );
  }
}
