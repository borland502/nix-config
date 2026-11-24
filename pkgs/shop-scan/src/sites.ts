import { z } from "zod";

export type Site = "amazon" | "ebay";

/**
 * Payload shapes returned by the in-page extractors.
 *
 * These are validated rather than cast: the JSON comes from a third-party page
 * whose markup changes without notice, so a silent shape drift should surface as
 * a loud error here instead of as `undefined` three call frames later.
 */
export const SearchRow = z.object({
  id: z.string().nullable(),
  price: z.string().nullable(),
  oos: z.boolean(),
  title: z.string().nullable(),
  sub: z.string().nullable().optional(),
});
export type SearchRow = z.infer<typeof SearchRow>;

export const ItemRow = z.object({
  price: z.string().nullable(),
  title: z.string().nullable(),
  cpu: z.string().nullable(),
  ram: z.string().nullable(),
  ssd: z.string().nullable(),
  ports: z.string().nullable(),
  barebone: z.boolean(),
  specifics: z.record(z.string(), z.string()).optional(),
});
export type ItemRow = z.infer<typeof ItemRow> & { id?: string };

export const ProbeText = z.object({ t: z.string() });

export const SEARCH_JS: Record<Site, (limit: number) => string> = {
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

export const ITEM_JS: Record<Site, string> = {
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

export const SEARCH_URL: Record<Site, (q: string) => string> = {
  amazon: (q) => `https://www.amazon.com/s?k=${encodeURIComponent(q)}`,
  ebay: (q) => `https://www.ebay.com/sch/i.html?_nkw=${encodeURIComponent(q)}`,
};

export const ITEM_URL: Record<Site, (id: string) => string> = {
  amazon: (id) => `https://www.amazon.com/dp/${id}`,
  ebay: (id) => `https://www.ebay.com/itm/${id}`,
};
