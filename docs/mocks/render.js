#!/usr/bin/env node
// Render each mock page to a PNG beside it.
//
// Usage: node docs/mocks/render.js [page.html ...]   (default: every page)
//
// Needs Playwright with Chromium (a global install works when NODE_PATH
// points at it; `make mocks` sets that up). Each page's <body> carries
// data-width (CSS px) and data-scale (device pixel ratio).
//
// MOCK_FONT_CACHE=<dir> serves the Google Fonts CSS and font files from a
// local directory instead of the network, for sandboxes that can reach
// neither. Each stylesheet is keyed by its request URL, as
// <dir>/css-<first 16 hex of the URL's sha256>.css, since pages ask for
// different families; font files are each fonts.gstatic.com path with '/'
// replaced by '_'. A file missing from the cache fails the request, and so
// the render, rather than falling back to system fonts.

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const dir = __dirname;
const pages = process.argv.slice(2).length
  ? process.argv.slice(2).map((p) => path.resolve(p))
  : fs.readdirSync(dir).filter((f) => f.endsWith('.html')).sort().map((f) => path.join(dir, f));

function cssCacheName(url) {
  return `css-${crypto.createHash('sha256').update(url).digest('hex').slice(0, 16)}.css`;
}

function fulfillFromCache(route, file, contentType) {
  if (!fs.existsSync(file)) {
    console.error(`not in MOCK_FONT_CACHE: ${route.request().url()} (expected ${file})`);
    return route.abort();
  }
  return route.fulfill({ contentType, body: fs.readFileSync(file) });
}

async function routeFonts(context, cache) {
  await context.route('https://fonts.googleapis.com/**', (route) =>
    fulfillFromCache(route, path.join(cache, cssCacheName(route.request().url())), 'text/css'));
  await context.route('https://fonts.gstatic.com/**', (route) => {
    const name = new URL(route.request().url()).pathname.slice(1).replace(/\//g, '_');
    return fulfillFromCache(route, path.join(cache, name), 'font/woff2');
  });
}

(async () => {
  const browser = await chromium.launch();
  let failed = false;
  for (const page of pages) {
    const html = fs.readFileSync(page, 'utf8');
    const width = Number((html.match(/data-width="(\d+)"/) || [])[1] || 1200);
    const scale = Number((html.match(/data-scale="([\d.]+)"/) || [])[1] || 2);
    const context = await browser.newContext({
      viewport: { width, height: 400 },
      deviceScaleFactor: scale,
    });
    if (process.env.MOCK_FONT_CACHE) await routeFonts(context, process.env.MOCK_FONT_CACHE);
    const tab = await context.newPage();
    tab.on('requestfailed', (r) => {
      failed = true;
      console.error(`${path.basename(page)}: failed to load ${r.url()}`);
    });
    // Several mocks build their content in inline scripts, so an exception
    // there would otherwise screenshot a half-built page.
    tab.on('pageerror', (e) => {
      failed = true;
      console.error(`${path.basename(page)}: script error: ${e.message}`);
    });
    // An HTTP error (a 404 or 429 from the font service) still counts as a
    // successful request to Playwright, so check the status as well.
    tab.on('response', (r) => {
      if (/^https?:/.test(r.url()) && !r.ok()) {
        failed = true;
        console.error(`${path.basename(page)}: HTTP ${r.status()} for ${r.url()}`);
      }
    });
    await tab.goto('file://' + page, { waitUntil: 'networkidle' });
    // fonts.ready also resolves after a font fails to decode, so check each
    // face's status too.
    const broken = await tab.evaluate(async () => {
      await document.fonts.ready;
      return [...document.fonts]
        .filter((f) => f.status === 'error')
        .map((f) => `${f.family} ${f.weight} ${f.style}`);
    });
    for (const f of broken) {
      failed = true;
      console.error(`${path.basename(page)}: font failed to load: ${f}`);
    }
    const out = page.replace(/\.html$/, '.png');
    await tab.screenshot({ path: out, fullPage: true });
    console.log(`${path.relative(process.cwd(), out)} (${width}px @${scale}x)`);
    await context.close();
  }
  await browser.close();
  process.exit(failed ? 1 : 0);
})();
