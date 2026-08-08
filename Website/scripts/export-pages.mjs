import { cp, mkdir, rm, writeFile } from "node:fs/promises";

const outputRoot = new URL("../out/", import.meta.url);
const clientRoot = new URL("../dist/client/", import.meta.url);
const basePath = process.env.GITHUB_PAGES_BASE_PATH ?? "/SwiftyDownloadManager";

function addBasePath(html) {
  const normalizedBase = basePath === "/" ? "" : basePath.replace(/\/$/, "");
  const staticScripts = [];
  let rewritten = html.replace(
    /\b(href|src)=(["'])\/(?!\/)/g,
    `$1=$2${normalizedBase}/`,
  );

  rewritten = rewritten.replace(
    /<script\b(?=[^>]*\bdata-sdm-static(?:=["'][^"']*["'])?)[^>]*>[\s\S]*?<\/script>/gi,
    (script) => {
      const token = `SDM_STATIC_SCRIPT_${staticScripts.length}`;
      staticScripts.push(script);
      return token;
    },
  );

  rewritten = rewritten
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "")
    .replace(/<link\b[^>]*\brel=["']modulepreload["'][^>]*\/?\s*>/gi, "");

  rewritten = rewritten.replace(
    /<html\b/,
    '<html data-sdm-static-export="true"',
  );

  staticScripts.forEach((script, index) => {
    rewritten = rewritten.replace(`SDM_STATIC_SCRIPT_${index}`, script);
  });

  return rewritten;
}

async function loadWorker() {
  const workerURL = new URL("../dist/server/index.js", import.meta.url);
  workerURL.searchParams.set("export", `${Date.now()}`);
  return (await import(workerURL.href)).default;
}

async function renderRoute(worker, pathname, destination) {
  const response = await worker.fetch(
    new Request(`https://kyle-ye.github.io${pathname}`, {
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

  if (!response.ok) {
    throw new Error(`Unable to render ${pathname}: ${response.status}`);
  }

  await mkdir(new URL("./", destination), { recursive: true });
  await writeFile(destination, addBasePath(await response.text()));
}

await rm(outputRoot, { recursive: true, force: true });
await mkdir(outputRoot, { recursive: true });
await cp(clientRoot, outputRoot, { recursive: true });

const worker = await loadWorker();
await renderRoute(worker, "/", new URL("index.html", outputRoot));
await renderRoute(worker, "/privacy", new URL("privacy/index.html", outputRoot));
await writeFile(new URL(".nojekyll", outputRoot), "");

console.log(`GitHub Pages export ready at ${outputRoot.pathname}`);
