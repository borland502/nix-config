import { test, expect } from "bun:test";
import { mkdtemp, mkdir, writeFile, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { open, pace, ScanError } from "../src/browser";

async function run(args: string[], scenario = "ok") {
  const dir = await mkdtemp(join(tmpdir(), "shop-scan-test-"));
  const bin = join(dir, "bin");
  await mkdir(bin);
  const log = join(dir, "calls");
  if (scenario !== "no-executable") await writeFile(join(bin, "playwright-cli"), `#!/bin/sh
echo "$1" >> "$TEST_LOG"
if [ "$TEST_SCENARIO" = fail ]; then echo diagnostic >&2; exit 7; fi
if [ "$TEST_SCENARIO" = noisy ]; then echo warning >&2; fi
if [ "$1" = open ]; then echo '### Page'; exit 0; fi
if [ "$1" = close ]; then exit 0; fi
case "$TEST_SCENARIO" in
 challenge) printf '### Result\\n{"t":"not a robot"}\\n';;
 missing) printf '### No result\\n';;
 malformed) printf '### Result\\nnot-json\\n';;
 shape) printf '### Result\\n{"t":42}\\n';;
 *) case "$2" in *document.title*) printf '### Result\\n{"t":"ordinary page"}\\n';; *) printf '### Result\\n[{"id":"x","price":"$1","oos":false,"title":"item"}]\\n### Ran Playwright code\\n[echo]\\n';; esac;;
esac
`, { mode: 0o755 });
  const proc = Bun.spawn([process.execPath, "run", "src/shop-scan.ts", ...args], { cwd: process.cwd(), env: { ...process.env, HOME: dir, PATH: scenario === "no-executable" ? bin : `${bin}:${process.env.PATH}`, TEST_LOG: log, TEST_SCENARIO: scenario }, stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, code] = await Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text(), proc.exited]);
  const calls = await readFile(log, "utf8").catch(() => "");
  await rm(dir, { recursive: true, force: true });
  return { stdout, stderr, code, calls };
}

test("rejects invalid options before starting a browser", async () => {
  for (const args of [["--limit"], ["--limit", "NaN"], ["--limit", "Infinity"], ["--limit", "0"], ["--limit", "1.2"], ["--delay", "-1"], ["--delay", "Infinity"], ["--delay", "NaN"], ["--delay", " "], ["--session"], ["--session", ""], ["--session", "bad name"], ["--bogus"]]) {
    const result = await run(["search", "amazon", "test", ...args]);
    expect(result.code).not.toBe(0);
    expect(result.calls).toBe("");
    expect(result.stderr).toContain("shop-scan:");
  }
});

test("propagates browser failures including close without success output", async () => {
  for (const args of [["search", "amazon", "test", "--json"], ["close"]]) {
    const result = await run(args, "fail");
    expect(result.code).not.toBe(0);
    expect(result.stderr).toContain("diagnostic");
    expect(result.stdout).toBe("");
  }
});

test("parses only result section and preserves JSON output", async () => {
  const result = await run(["search", "amazon", "test", "--json"]);
  expect(result.code).toBe(0);
  expect(JSON.parse(result.stdout)).toEqual([{ id: "x", price: "$1", oos: false, title: "item" }]);
});

test("rejects missing, malformed and invalid result payloads", async () => {
  for (const scenario of ["missing", "malformed", "shape"]) {
    const result = await run(["search", "amazon", "test", "--json"], scenario);
    expect(result.code).not.toBe(0);
    expect(result.stdout).toBe("");
    expect(result.stderr).toContain(scenario === "missing" ? "no result section" : scenario === "malformed" ? "unparseable result" : "unexpected shape");
  }
});

test("stops at a challenge before running the extractor", async () => {
  const result = await run(["search", "ebay", "test", "--json"], "challenge");
  expect(result.code).toBe(3);
  expect(result.calls.trim().split("\n")).toEqual(["open", "run-code"]);
  expect(result.stdout).toBe("");
});

test("successful stderr does not corrupt JSON output", async () => {
  const result = await run(["search", "amazon", "test", "--json"], "noisy");
  expect(result.code).toBe(0);
  expect(JSON.parse(result.stdout)).toHaveLength(1);
  expect(result.stderr).toContain("warning");
});

test("pacing retains the three second floor and jitter", async () => {
  const waits: number[] = [];
  const wait = async (ms: number) => { waits.push(ms); };
  await pace(0, wait, () => 0);
  await pace(6, wait, () => 0);
  await pace(6, wait, () => 1);
  expect(waits).toEqual([3000, 3600, 8400]);
});

test("page cap stops before a 41st browser request", async () => {
  let calls = 0;
  const runner = async () => { calls++; return "### Page"; };
  const options = { limit: 20, delay: 6, session: "shop", json: false, headed: false };
  for (let i = 0; i < 40; i++) await open("https://example.invalid", options, runner);
  await expect(open("https://example.invalid", options, runner)).rejects.toMatchObject({ exitCode: 4 } satisfies Partial<ScanError>);
  expect(calls).toBe(40);
});

test("rejects delay values that would overflow the timer at maximum jitter", async () => {
  for (const value of ["1533917", "1e100"]) {
    const result = await run(["search", "amazon", "test", "--delay", value]);
    expect(result.code).toBe(1);
    expect(result.stderr).toContain("--delay");
    expect(result.calls).toBe("");
  }
  const boundary = await run(["search", "amazon", "test", "--delay", "1533916"]);
  expect(boundary.code).toBe(0);
  const waits: number[] = [];
  await pace(1533916, async (ms) => { waits.push(ms); }, () => 1);
  expect(waits[0]).toBeLessThanOrEqual(2147483647);
  expect(waits[0]).toBeGreaterThanOrEqual(3000);
});

test("reports an unavailable browser executable as a browser failure", async () => {
  const result = await run(["close"], "no-executable");
  expect(result.code).toBe(2);
  expect(result.stdout).toBe("");
  expect(result.stderr).toContain("npx");
  expect(result.stderr).toContain("playwright-cli");
});
