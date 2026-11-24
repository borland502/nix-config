export const VERSION = "0.1.0";
// At 1.4x maximum jitter this stays below the 32-bit setTimeout limit.
const MAX_DELAY_SECONDS = 1_533_916;
export interface Opts { limit: number; delay: number; session: string; json: boolean; headed: boolean }

/** Parse and validate options before any browser process is started. */
export function parseArgs(argv: string[]): { cmd: string; rest: string[]; opts: Opts } {
  const opts: Opts = { limit: 20, delay: 6, session: "shop", json: false, headed: false };
  const rest: string[] = [];
  let cmd = "";
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === "--limit" || a === "--delay" || a === "--session") {
      const value = argv[++i];
      if (value === undefined || value.startsWith("--") || value.trim() === "") throw new Error(`${a} requires a value`);
      if (a === "--session") {
        if (!/^[a-zA-Z0-9_-]+$/.test(value)) throw new Error("invalid --session: use letters, digits, underscores or hyphens");
        opts.session = value;
      } else {
        const number = Number(value);
        if (!Number.isFinite(number) || (a === "--limit" ? !Number.isInteger(number) || number <= 0 : number < 0 || number > MAX_DELAY_SECONDS)) {
          throw new Error(a === "--limit" ? "--limit must be a positive finite integer" : `--delay must be a finite number between 0 and ${MAX_DELAY_SECONDS} seconds`);
        }
        if (a === "--limit") opts.limit = number; else opts.delay = number;
      }
    } else if (a === "--json") opts.json = true;
    else if (a === "--headed") opts.headed = true;
    else if (a.startsWith("-")) throw new Error(`unknown option: ${a}`);
    else if (!cmd) cmd = a;
    else rest.push(a);
  }
  return { cmd, rest, opts };
}

export function usage(): void {
  console.log(`shop-scan — human-paced price comparison on public listing pages

  search <amazon|ebay> <query...>     search results with prices
  item   <amazon|ebay> <id> [id...]   per-listing detail (RAM/SSD/CPU/barebone)
  close                               shut the browser session down

  --limit N    max search rows (default 20)
  --delay S    base delay in seconds (default 6, floor 3, max 1533916)
  --session N  playwright-cli session name (default "shop")
  --json       emit JSON instead of TSV
  --headed     show the browser window

Aborts with exit 3 on a real bot challenge; it will not try to defeat one.`);
}
