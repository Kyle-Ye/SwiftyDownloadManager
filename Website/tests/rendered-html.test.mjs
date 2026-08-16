import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

async function render(pathname = "/") {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request(`http://localhost${pathname}`, {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the SDM landing page", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(
    html,
    /<title>Swifty Download Manager — Download faster\. Resume anytime\.<\/title>/i,
  );
  assert.match(html, /Download faster\./);
  assert.match(html, /Resume anytime\./);
  assert.doesNotMatch(html, /Your files\.|Your rules\./);
  assert.match(html, /<strong>Swifty Download Manager<\/strong>/);
  assert.doesNotMatch(html, /<strong>Swifty<\/strong>\s*<small>Download Manager<\/small>/);
  assert.doesNotMatch(html, /Latest release available/);
  assert.match(
    html,
    /https:\/\/github\.com\/Kyle-Ye\/SwiftyDownloadManager\/releases\/latest/,
  );
  assert.match(html, /Download Latest Version/);
  assert.match(html, /Reassigns byte ranges dynamically/);
  assert.match(html, /Fast by design\./);
  assert.match(html, /Ready to resume\./);
  assert.doesNotMatch(html, /Explore the engines|Live speed/);
  assert.doesNotMatch(html, /Multi-connection transfers|Persistent resume/);
  assert.doesNotMatch(html, /From first click|to final byte/);
  assert.match(html, /Multiple parallel connections/);
  assert.match(html, /Single connection/);
  assert.match(html, /SDM · Up to 8 connections/);
  assert.match(html, /Toward available bandwidth/);
  assert.match(html, /Illustrative comparison/);
  assert.match(html, /8 Range segments/);
  assert.match(html, /Rebalanced live/);
  assert.match(html, /Checkpoint saved/);
  assert.match(html, /Resume from 68%/);
  assert.match(html, /Keep an eye on every download\./);
  assert.match(html, /Even while your Mac is locked\./);
  assert.match(html, /Enable it in Settings/);
  assert.match(html, /Off by default/);
  assert.match(html, /下载状态，/);
  assert.match(html, /抬眼可见。/);
  assert.match(html, /src=["']\/lock-screen-status-en\.jpg["']/);
  assert.match(html, /src=["']\/lock-screen-status-zh\.jpg["']/);
  assert.match(html, /Public repository/);
  assert.match(html, /MIT in 2 years/);
  assert.match(html, /Safari \+ Chrome/);
  assert.match(html, /extensions for Safari and Chrome/i);
  assert.match(html, /Download with SDM/);
  assert.doesNotMatch(html, /Right from Safari/);
  assert.match(html, /SQLite-backed resumable state/);
  assert.match(html, /FSL-1\.1-MIT/);
  assert.match(html, /blob\/main\/LICENSE\.md/);
  assert.doesNotMatch(html, /Download (?:version )?0\.3\.0/i);
  assert.match(html, /No accounts\. No analytics\. No developer data collection\./);
  assert.match(html, /@ 2026 Kyle-Ye/);
  assert.doesNotMatch(html, /© 2026 Swifty Download Manager/);
  assert.match(html, /href=["']\/privacy\/["']>Privacy<\/a>/);
  assert.match(html, /Read the privacy statement/);
  assert.doesNotMatch(html, /Privacy · 隐私/);
  assert.match(html, /data-language-option=["']en["']/);
  assert.match(html, /data-language-option=["']zh["']/);
  assert.match(html, /data-theme-toggle/);
  assert.match(html, /src=["']\/theme\.js["']/);
  assert.match(html, /src=["']\/language\.js["']/);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/i);
});

test("server-renders the bilingual privacy statement", async () => {
  const response = await render("/privacy");
  assert.equal(response.status, 200);

  const html = await response.text();
  assert.match(html, /<title>Privacy · Swifty Download Manager<\/title>/);
  assert.match(html, /Your download and browsing data stays on your device\./);
  assert.match(html, /你的下载与浏览数据只在设备本地处理。/);
  assert.match(html, /No analytics or telemetry/);
  assert.match(html, /无分析与遥测/);
  assert.match(html, /Website privacy/);
  assert.match(html, /网站隐私/);
  assert.match(html, /August 9, 2026/);
  assert.match(html, />Privacy statement</);
  assert.match(html, />Effective\s*</);
  assert.match(html, />Questions</);
  assert.match(html, />Local-only data handling</);
  assert.match(html, /Browser extension data handling/);
  assert.match(html, /Chrome Web Store Limited Use/);
  assert.doesNotMatch(html, /Privacy · 隐私|Effective · 生效日期|Questions · 问题反馈|Zero collection · 零数据收集/);
  assert.match(html, /data-language-option=["']en["']/);
  assert.match(html, /data-language-option=["']zh["']/);
  assert.match(html, /data-theme-toggle/);
  assert.match(html, /src=["']\/theme\.js["']/);
  assert.match(html, /src=["']\/language\.js["']/);
});

test("ships site-specific metadata, distribution config, and local brand assets", async () => {
  const [layout, packageJson, languageScript, themeScript, siteConfig] = await Promise.all([
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
    readFile(new URL("../public/language.js", import.meta.url), "utf8"),
    readFile(new URL("../public/theme.js", import.meta.url), "utf8"),
    readFile(new URL("../app/site-config.ts", import.meta.url), "utf8"),
  ]);

  assert.match(layout, /openGraph:/);
  assert.match(layout, /twitter:/);
  assert.match(layout, /\/og\.png/);
  assert.match(layout, /kyle-ye\.github\.io\/SwiftyDownloadManager/);
  assert.doesNotMatch(layout, /codex-preview|Starter Project|next\/font/);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
  assert.match(languageScript, /sdm-language/);
  assert.match(languageScript, /localStorage\.setItem/);
  assert.match(languageScript, /document\.documentElement\.dataset\.language/);
  assert.match(languageScript, /更快下载。/);
  assert.match(languageScript, /随时续传。/);
  assert.match(languageScript, /锁屏状态/);
  assert.doesNotMatch(languageScript, /你的文件，你做主/);
  assert.match(layout, /src="\/theme\.js"/);
  assert.match(layout, /data-sdm-static/);
  assert.match(themeScript, /sdm-theme/);
  assert.match(themeScript, /prefers-color-scheme: dark/);
  assert.match(themeScript, /localStorage\.setItem/);
  assert.match(themeScript, /document\.documentElement/);
  assert.match(themeScript, /dataset\.theme/);
  assert.match(siteConfig, /releases\/latest/);
  assert.match(siteConfig, /appStore/);
  assert.match(siteConfig, /enabled: false/);
  assert.match(siteConfig, /Download on the App Store/);

  await Promise.all([
    access(new URL("../public/sdm-icon.png", import.meta.url)),
    access(new URL("../public/favicon.svg", import.meta.url)),
    access(new URL("../public/og.png", import.meta.url)),
    access(new URL("../public/lock-screen-status-en.jpg", import.meta.url)),
    access(new URL("../public/lock-screen-status-zh.jpg", import.meta.url)),
    access(new URL("../public/language.js", import.meta.url)),
    access(new URL("../public/theme.js", import.meta.url)),
  ]);
});
