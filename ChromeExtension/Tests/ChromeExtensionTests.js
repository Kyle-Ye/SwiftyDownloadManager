const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");
const { createStorage } = require("../../BrowserExtension/Tests/extension-storage");

const resourcesDirectory = path.join(__dirname, "..", "Resources");
const sharedResourcesDirectory = path.join(
  __dirname,
  "..",
  "..",
  "BrowserExtension",
  "Shared"
);
const safariResourcesDirectory = path.join(
  __dirname,
  "..",
  "..",
  "SafariExtension",
  "Resources"
);
function sourcePath(resource) {
  if (resource.startsWith("Shared/")) {
    return path.join(sharedResourcesDirectory, resource.slice("Shared/".length));
  }
  return path.join(resourcesDirectory, resource);
}

function eventHook() {
  const listeners = [];
  return {
    addListener(listener) {
      listeners.push(listener);
    },
    listeners,
  };
}

function backgroundHarness({ storage = createStorage(), partitionKey, probe = async (url) => ({ ok: true, url,
  headers: new Headers({ "Content-Type": "application/octet-stream" }) }) } = {}) {
  const nativeMessages = [];
  const cookieQueries = [];
  const contextMenuCreates = [];
  const tabUpdates = [];
  const runtimeOnInstalled = eventHook();
  const runtimeOnMessage = eventHook();
  const contextMenusOnClicked = eventHook();
  const actionOnClicked = eventHook();
  const webNavigationOnBeforeNavigate = eventHook();

  const optionsOpened = [];
  const chrome = {
    storage,
    cookies: {
      getPartitionKey: partitionKey,
      async getAll(filter) { cookieQueries.push(filter); return [{name: "session", value: "secret", domain: "cdn.example.com", path: "/", secure: true, hostOnly: true}]; },
      async getAllCookieStores() { return [{id: "profile-1", tabIds: [7, 11]}]; },
    },
    action: { onClicked: actionOnClicked },
    contextMenus: {
      create(options) {
        contextMenuCreates.push(options);
      },
      onClicked: contextMenusOnClicked,
      removeAll() {
        return Promise.resolve();
      },
    },
    runtime: {
      async openOptionsPage() { optionsOpened.push(true); },
      getURL(resource) {
        return `chrome-extension://test-extension/${resource}`;
      },
      onInstalled: runtimeOnInstalled,
      onMessage: runtimeOnMessage,
    },
    tabs: {
      update(tabID, options) {
        tabUpdates.push({ options, tabID });
        return Promise.resolve({ id: tabID });
      },
    },
    webNavigation: { onBeforeNavigate: webNavigationOnBeforeNavigate },
  };

  const context = vm.createContext({
    AbortSignal,
    fetch: probe,
    Error,
    Object,
    Promise,
    Set,
    String,
    URL,
    chrome,
    console,
  });
  context.importScripts = (...resources) => {
    for (const resource of resources) {
      if (resource === "handoff.js") {
        context.SDMChromeHandoff = { async send(payload) { nativeMessages.push(payload); return { accepted: true }; } };
        continue;
      }
      vm.runInContext(fs.readFileSync(sourcePath(resource), "utf8"), context, {
        filename: resource,
      });
    }
  };
  vm.runInContext(
    fs.readFileSync(path.join(resourcesDirectory, "background.js"), "utf8"),
    context,
    { filename: "background.js" }
  );

  return {
    nativeMessages, cookieQueries, storage, optionsOpened,
    actionOnClicked,
    contextMenuCreates,
    contextMenusOnClicked,
    runtimeOnInstalled,
    runtimeOnMessage,
    tabUpdates,
    webNavigationOnBeforeNavigate,
  };
}

test("Chrome package uses a store-ready Manifest V3 layout", () => {
  const manifest = JSON.parse(
    fs.readFileSync(path.join(resourcesDirectory, "manifest.json"), "utf8")
  );

  assert.equal(manifest.manifest_version, 3);
  assert.equal(manifest.minimum_chrome_version, "111");
  assert.equal(manifest.background.service_worker, "background.js");
  assert.ok(manifest.action);
  assert.ok(!manifest.permissions.includes("nativeMessaging"));
  assert.deepEqual(manifest.permissions.sort(), ["contextMenus", "cookies", "storage", "webNavigation"]);
  assert.deepEqual(manifest.host_permissions, ["http://*/*", "https://*/*"]);
  assert.ok(manifest.content_scripts.some((contentScript) =>
    contentScript.world === "MAIN" && contentScript.js.includes("Shared/page.js")
  ));

  const packagedResources = [
    "background.js",
    "handoff.js",
    "platform.js",
    "Shared/background-controller.js",
    "Shared/capture.css",
    "Shared/capture.html",
    "Shared/capture.js",
    "Shared/content.js",
    "Shared/download-support.js",
    "Shared/download-settings.js",
    "Shared/page.js",
    "Shared/options.html",
    "Shared/options.js",
    "Shared/options.css",
    ...Object.values(manifest.icons),
  ];
  for (const resource of packagedResources) {
    assert.ok(fs.existsSync(sourcePath(resource)), resource);
  }

  for (const resource of packagedResources.filter((resource) => resource.endsWith(".js"))) {
    const source = fs.readFileSync(sourcePath(resource), "utf8");
    assert.doesNotThrow(() => new vm.Script(source, { filename: resource }));
  }
});

test("Safari and Chrome manifests load the same shared interception sources", () => {
  const chromeManifest = JSON.parse(
    fs.readFileSync(path.join(resourcesDirectory, "manifest.json"), "utf8")
  );
  const safariManifest = JSON.parse(
    fs.readFileSync(path.join(safariResourcesDirectory, "manifest.json"), "utf8")
  );

  const sharedScripts = (manifest) => manifest.content_scripts
    .flatMap((contentScript) => contentScript.js)
    .filter((resource) => resource.startsWith("Shared/"));

  assert.deepEqual(sharedScripts(chromeManifest), sharedScripts(safariManifest));
  assert.deepEqual(sharedScripts(chromeManifest), [
    "Shared/download-support.js",
    "Shared/download-settings.js",
    "Shared/content.js",
    "Shared/page.js",
  ]);
  for (const manifest of [chromeManifest, safariManifest]) {
    assert.equal(manifest.options_ui.page, "Shared/options.html");
    assert.ok(manifest.permissions.includes("storage"));
    assert.deepEqual(manifest.content_scripts.find((script) => script.world === "MAIN").js,
      ["Shared/page.js"], "The MAIN-world bridge must run without shared helper globals");
  }
});

test("background forwards cookies through the private app handoff", async () => {
  const harness = backgroundHarness();
  const listener = harness.runtimeOnMessage.listeners[0];
  const response = new Promise((resolve) => {
    const keepsChannelOpen = listener(
      {
        type: "captureDownload",
        url: "https://cdn.example.com/release.zip",
        sourcePage: "https://example.com/releases",
      },
      { tab: { id: 7, url: "https://example.com/releases" } },
      resolve
    );
    assert.equal(keepsChannelOpen, true);
  });

  const result = await response;
  assert.equal(result.accepted, true);
  assert.equal(result.error, undefined);
  assert.equal(harness.tabUpdates.length, 0);
  assert.equal(harness.nativeMessages[0].url, "https://cdn.example.com/release.zip");
  assert.equal(harness.nativeMessages[0].requestContext.cookies[0].value, "secret");
  assert.equal(harness.nativeMessages[0].requestContext.referrer, "https://example.com/");
  assert.equal(harness.cookieQueries[0].storeId, "profile-1");
});

test("context menu and toolbar action open SDM", async () => {
  const harness = backgroundHarness();

  harness.runtimeOnInstalled.listeners[0]();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(harness.contextMenuCreates[0].id, "download-with-sdm");

  harness.contextMenusOnClicked.listeners[0](
    {
      linkUrl: "https://cdn.example.com/archive.dmg",
      menuItemId: "download-with-sdm",
      pageUrl: "https://example.com/downloads",
    },
    { id: 11 }
  );
  await new Promise((resolve) => setImmediate(resolve));

  harness.actionOnClicked.listeners[0]({ id: 12 });
  await Promise.resolve();

  assert.equal(harness.nativeMessages[0].url, "https://cdn.example.com/archive.dmg");
  assert.equal(new URL(harness.tabUpdates[0].options.url).hostname, "open");
});

test("direct file navigation is replaced by the confirmation page", async () => {
  const harness = backgroundHarness();

  harness.webNavigationOnBeforeNavigate.listeners[0]({
    frameId: 0,
    tabId: 42,
    url: "https://cdn.example.com/application.pkg",
  });
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(harness.tabUpdates.length, 1);
  const capturePage = new URL(harness.tabUpdates[0].options.url);
  assert.equal(capturePage.protocol, "chrome-extension:");
  assert.equal(capturePage.pathname, "/Shared/capture.html");
  assert.equal(
    capturePage.searchParams.get("url"),
    "https://cdn.example.com/application.pkg"
  );
});

function confirmationHarness(browser, reply, downloadURL = "https://example.com/file.xip") {
  const elements = new Map(["open-app", "continue-browser", "confirmation", "download-url", "error", "status"].map((id) => [id, {
    hidden: ["confirmation", "continue-browser", "error", "status"].includes(id),
    addEventListener(_type, listener) { this.click = listener; },
  }]));
  const navigations = [], messages = [];
  const context = vm.createContext({ URL, URLSearchParams,
    document: { getElementById(id) { return elements.get(id); } },
    window: { location: { search: `?url=${encodeURIComponent(downloadURL)}`,
      replace(url) { navigations.push(url); } } },
    [browser]: { runtime: { async sendMessage(message) {
      messages.push(message);
      return reply(message);
    } } },
  });
  vm.runInContext(fs.readFileSync(sourcePath("Shared/capture.js"), "utf8"), context);
  return { elements, navigations, messages, downloadURL };
}

test("a rejected handoff leaves the confirmation ready to retry or continue in the browser", async () => {
  for (const browser of ["chrome", "browser"]) {
    let accepted = false;
    const harness = confirmationHarness(browser, (message) => {
      if (message.type === "checkDownload") return { download: true };
      return { accepted: message.type === "continueInBrowser" || accepted };
    });
    await new Promise((resolve) => setImmediate(resolve));
    await harness.elements.get("open-app").click({ preventDefault() {} });
    assert.deepEqual(harness.navigations, [], "An explicit app choice must not start a browser download on failure");
    assert.deepEqual(harness.messages.map((message) => message.type),
      ["checkDownload", "captureDownload"]);
    assert.equal(harness.elements.get("error").hidden, false);
    assert.equal(harness.elements.get("open-app").disabled, false);
    accepted = true;
    await harness.elements.get("open-app").click({ preventDefault() {} });
    assert.equal(harness.messages.filter((message) => message.type === "captureDownload").length, 2);
    assert.equal(harness.elements.get("error").hidden, true);
    assert.equal(harness.elements.get("status").textContent, "Sent to SDM. You can close this tab.");
    await harness.elements.get("continue-browser").click({ preventDefault() {} });
    assert.deepEqual(harness.navigations, [harness.downloadURL]);
  }
});

test("a file download that leaves the confirmation document open does not lock either action", async () => {
  const harness = confirmationHarness("chrome", (message) =>
    message.type === "checkDownload" ? { download: true } : { accepted: true });
  await new Promise((resolve) => setImmediate(resolve));
  for (let attempt = 0; attempt < 2; attempt++) {
    await harness.elements.get("continue-browser").click({ preventDefault() {} });
    assert.equal(harness.elements.get("continue-browser").disabled, false);
    await harness.elements.get("open-app").click({ preventDefault() {} });
    assert.equal(harness.elements.get("open-app").disabled, false);
  }
  assert.deepEqual(harness.navigations, [harness.downloadURL, harness.downloadURL]);
  assert.equal(harness.messages.filter((message) => message.type === "captureDownload").length, 2);
});

test("confirmation prevents duplicate pending requests and unlocks after a transport failure", async () => {
  let reject;
  const harness = confirmationHarness("chrome", (message) => {
    if (message.type === "checkDownload") return { download: true };
    return new Promise((_resolve, rejectRequest) => { reject = rejectRequest; });
  });
  await new Promise((resolve) => setImmediate(resolve));
  const pending = harness.elements.get("open-app").click({ preventDefault() {} });
  assert.equal(harness.elements.get("open-app").disabled, true);
  assert.equal(harness.elements.get("continue-browser").disabled, true);
  await harness.elements.get("open-app").click({ preventDefault() {} });
  await harness.elements.get("continue-browser").click({ preventDefault() {} });
  assert.equal(harness.messages.length, 2);
  reject(new Error("Connection lost"));
  await pending;
  assert.equal(harness.elements.get("open-app").disabled, false);
  assert.equal(harness.elements.get("continue-browser").disabled, false);
  const retry = harness.elements.get("continue-browser").click({ preventDefault() {} });
  assert.equal(harness.messages.at(-1).type, "continueInBrowser");
  reject(new Error("Connection lost"));
  await retry;
  assert.equal(harness.elements.get("open-app").disabled, false);
  assert.equal(harness.elements.get("continue-browser").disabled, false);
});

test("extension confirmation pages use tab cookies without querying an extension-origin partition", async () => {
  for (const scheme of ["chrome-extension", "safari-web-extension"]) {
    let partitionQueries = 0;
    const harness = backgroundHarness({ async partitionKey() {
      partitionQueries++;
      throw new Error('No host permissions for cookies at url: "chrome-extension://test-extension/".');
    } });
    const response = await new Promise((resolve) => harness.runtimeOnMessage.listeners[0](
      { type: "captureDownload", url: "http://127.0.0.1:18736/empty.bin" },
      { url: `${scheme}://test-extension/Shared/capture.html`, tab: { id: 7 } }, resolve));
    assert.equal(response.accepted, true);
    assert.equal(partitionQueries, 0);
    assert.equal(harness.cookieQueries[0].storeId, "profile-1");
    assert.equal(harness.cookieQueries[0].url, "http://127.0.0.1:18736/empty.bin");
    assert.equal(harness.nativeMessages.length, 1);
    assert.equal(harness.nativeMessages[0].requestContext.cookies[0].value, "secret");
  }
});

test("a partition lookup failure for an HTTP page still rejects authenticated handoff", async () => {
  const harness = backgroundHarness({ async partitionKey() { throw new Error("Permission denied"); } });
  const response = await new Promise((resolve) => harness.runtimeOnMessage.listeners[0](
    { type: "captureDownload", url: "https://cdn.example.com/file.xip" },
    { url: "https://example.com/", tab: { id: 7 } }, resolve));
  assert.equal(response.accepted, false);
  assert.equal(harness.nativeMessages.length, 0);
});

test("confirmation stays hidden for inline pages and unverifiable responses", async () => {
  for (const result of [false, undefined, new Error("Offline")]) {
    const harness = confirmationHarness("chrome", (message) => {
      if (message.type === "continueInBrowser") return { accepted: true };
      assert.equal(message.type, "checkDownload");
      if (result instanceof Error) throw result;
      return { download: result };
    });
    assert.equal(harness.elements.get("confirmation").hidden, true);
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(harness.elements.get("confirmation").hidden, true);
    assert.deepEqual(harness.navigations, [harness.downloadURL]);
  }
});

test("Continue in browser grants a bypass without sending a download to SDM", async () => {
  const background = backgroundHarness();
  const sender = { tab: { id: 42 }, url: "chrome-extension://test-extension/Shared/capture.html" };
  const listener = background.runtimeOnMessage.listeners[0];
  const harness = confirmationHarness("chrome", (message) => new Promise((resolve) => listener(message, sender, resolve)));
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(harness.elements.get("confirmation").hidden, false);
  harness.elements.get("continue-browser").click({ preventDefault() {} });
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(harness.navigations, [harness.downloadURL]);
  assert.equal(background.nativeMessages.length, 0);
  const navigate = background.webNavigationOnBeforeNavigate.listeners[0];
  await navigate({ frameId: 0, tabId: 42, url: harness.downloadURL });
  assert.equal(background.tabUpdates.length, 0);
  await navigate({ frameId: 0, tabId: 43, url: harness.downloadURL });
  assert.equal(background.tabUpdates.length, 1, "Bypass must stay in its tab");
  await navigate({ frameId: 0, tabId: 42, url: harness.downloadURL });
  assert.equal(background.tabUpdates.length, 2, "Bypass must be one use");
});

test("invalid confirmation URLs do not expose either download action", () => {
  for (const url of ["javascript:alert(1)", "not a URL"]) {
    const harness = confirmationHarness("chrome", () => assert.fail("Unexpected message"), url);
    assert.equal(harness.elements.get("confirmation").hidden, true);
    assert.equal(harness.elements.get("continue-browser").hidden, true);
    assert.equal(harness.elements.get("error").hidden, false);
  }
});

const ordinaryURLs = [
  "https://github.com/swiftlang/swift/blob/swift-6.4.0-RELEASE/stdlib/public/RuntimeModule/CMakeLists.txt",
  "https://example.com/document.pdf", "https://example.com/video.mp4",
  "https://example.com/audio.mp3", "https://example.com/image.tiff",
  "https://example.com/source.ts", "https://example.com/data.csv",
];

test("GitHub source and browser-viewable formats never enter the navigation interstitial", async () => {
  const harness = backgroundHarness();
  for (const url of ordinaryURLs) {
    await harness.webNavigationOnBeforeNavigate.listeners[0]({ frameId: 0, tabId: 42, url });
  }
  assert.equal(harness.tabUpdates.length, 0);
});

test("automatic capture requires a confirmed response, not a filename suffix", async () => {
  const cases = [
    [{ "Content-Type": "text/html" }, false],
    [{ "Content-Type": "text/plain" }, false],
    [{ "Content-Type": "application/pdf" }, false],
    [{ "Content-Type": "video/mp4" }, false],
    [{ "Content-Type": "application/unknown" }, false],
    [{}, false],
    [{ "Content-Type": "application/zip", "Content-Disposition": "inline; filename=a.zip" }, false],
    [{ "Content-Type": "application/zip" }, true],
    [{ "Content-Type": "Application/Octet-Stream; charset=binary" }, true],
    [{ "Content-Type": "text/plain", "Content-Disposition": "Attachment; filename=CMakeLists.txt" }, true],
  ];
  for (const [headers, expected] of cases) {
    const probes = [];
    const harness = backgroundHarness({ async probe(url, options) {
      probes.push({ url, options });
      return { ok: true, url, headers: new Headers(headers) };
    } });
    const url = "https://cdn.example.com/preview.zip";
    const response = await new Promise((resolve) => harness.runtimeOnMessage.listeners[0](
      { type: "captureDownload", automatic: true, url },
      { url: "https://example.com/", tab: { id: 7 } }, resolve));
    assert.equal(response.accepted, expected, JSON.stringify(headers));
    assert.equal(harness.nativeMessages.length, expected ? 1 : 0);
    assert.equal(harness.cookieQueries.length, expected ? 1 : 0);
    assert.equal(probes[0].options.method, "HEAD");
    assert.equal(probes[0].options.credentials, "include");
    assert.ok(probes[0].options.signal instanceof AbortSignal);
    if (!expected) {
      await harness.webNavigationOnBeforeNavigate.listeners[0]({ frameId: 0, tabId: 7, url });
      assert.equal(harness.tabUpdates.length, 0);
    }
  }
});

test("HEAD failure, HTTP errors, and HTTPS downgrades default to the browser", async () => {
  for (const probe of [
    async () => { throw new Error("Timeout or unsupported HEAD"); },
    async (url) => ({ ok: false, url, headers: new Headers({ "Content-Disposition": "attachment" }) }),
    async () => ({ ok: true, url: "http://example.com/file.zip", headers: new Headers({ "Content-Type": "application/zip" }) }),
  ]) {
    const harness = backgroundHarness({ probe });
    const result = await new Promise((resolve) => harness.runtimeOnMessage.listeners[0](
      { type: "captureDownload", automatic: true, url: "https://example.com/file.zip" },
      { tab: { id: 7 } }, resolve));
    assert.equal(result.accepted, false);
    assert.equal(harness.nativeMessages.length, 0);
  }
});

test("only a same-origin download attribute can skip the response check", async () => {
  for (const sameOrigin of [true, false]) {
    let probes = 0;
    const harness = backgroundHarness({ async probe(url) {
      probes++;
      return { ok: true, url, headers: new Headers({ "Content-Type": "text/html" }) };
    } });
    const response = await new Promise((resolve) => harness.runtimeOnMessage.listeners[0](
      { type: "captureDownload", automatic: true, downloadAttribute: true, url: "https://example.com/page" },
      { url: sameOrigin ? "https://example.com/" : "https://another.example/", tab: { id: 7 } }, resolve));
    assert.equal(response.accepted, sameOrigin);
    assert.equal(probes, sameOrigin ? 0 : 1);
  }
});

test("Chrome handoff encrypts browser context and authenticates the app receipt", async () => {
  const crypto = require("node:crypto");
  const payload = { type: "download", url: "https://example.com/file.xip", requestContext: {
    cookies: [{ name: "session", value: "PRIVATE_COOKIE_VALUE" }],
  } };
  let ticket, opened, decoded, wire;
  class FakeWebSocket {
    constructor(url, protocol) {
      assert.equal(url, "ws://127.0.0.1:10027");
      assert.equal(protocol, "sdm.handoff.v1");
      queueMicrotask(() => this.onopen());
    }
    send(text) {
      wire = text;
      const envelope = JSON.parse(text);
      assert.equal(envelope.id, ticket.searchParams.get("id"));
      const key = Buffer.from(ticket.searchParams.get("key"), "base64");
      const sealed = Buffer.from(envelope.sealed, "base64");
      const decipher = crypto.createDecipheriv("aes-256-gcm", key, sealed.subarray(0, 12));
      decipher.setAAD(Buffer.from(envelope.id));
      decipher.setAuthTag(sealed.subarray(-16));
      decoded = JSON.parse(Buffer.concat([decipher.update(sealed.subarray(12, -16)), decipher.final()]));
      const nonce = crypto.randomBytes(12);
      const cipher = crypto.createCipheriv("aes-256-gcm", key, nonce);
      cipher.setAAD(Buffer.from(envelope.id));
      const response = Buffer.concat([nonce, cipher.update('{"accepted":true}'), cipher.final(), cipher.getAuthTag()]);
      queueMicrotask(() => this.onmessage({ data: response.toString("base64") }));
    }
    close() {}
  }
  const context = vm.createContext({
    crypto: crypto.webcrypto, Uint8Array, TextEncoder, TextDecoder, URL, btoa, atob,
    setTimeout, clearTimeout, WebSocket: FakeWebSocket,
    chrome: { tabs: { async update(id, options) {
      opened = id; ticket = new URL(options.url);
      assert.equal(ticket.hostname, "handoff");
      assert(!options.url.includes("PRIVATE_COOKIE_VALUE"));
      assert(!options.url.includes("example.com"));
    } } },
  });
  vm.runInContext(fs.readFileSync(sourcePath("Shared/download-support.js"), "utf8"), context);
  vm.runInContext(fs.readFileSync(sourcePath("handoff.js"), "utf8"), context);
  const result = await context.SDMChromeHandoff.send(payload, { id: 5 });
  assert.equal(result.accepted, true);
  assert.equal(opened, 5);
  assert.deepEqual(decoded, payload);
  assert(!wire.includes("PRIVATE_COOKIE_VALUE"));
  assert(!wire.includes(ticket.searchParams.get("key")));
});

test("preview opt-in affects navigation and automatic handoff, and an opt-out stops both", async () => {
  const harness = backgroundHarness({ async probe(url) {
    return { ok: true, url, headers: new Headers({ "Content-Type": "video/mp4", "Content-Disposition": "inline" }) };
  } });
  const url = "https://cdn.example.com/movie.MP4?token=test";
  const navigate = () => harness.webNavigationOnBeforeNavigate.listeners[0]({ frameId: 0, tabId: 7, url });
  const capture = () => new Promise((resolve) => harness.runtimeOnMessage.listeners[0](
    { type: "captureDownload", automatic: true, url }, { tab: { id: 7 }, url: "https://example.com/" }, resolve));
  await navigate();
  assert.equal(harness.tabUpdates.length, 0, "MP4 is off by default");
  // Adding mp4 to the conservative list still respects inline responses.
  await harness.storage.local.set({ downloadRules: { candidateExtensions: ["mp4"], previewExtensions: [] } });
  assert.equal((await capture()).accepted, false);
  await navigate(); // Consume the failed-check bypass.
  await harness.storage.local.set({ downloadRules: { candidateExtensions: [], previewExtensions: ["mp4"] } });
  await navigate();
  assert.equal(harness.tabUpdates.length, 1);
  assert.equal(new URL(harness.tabUpdates[0].options.url).searchParams.get("url"), url);
  assert.equal((await capture()).accepted, true);
  assert.equal(harness.nativeMessages.length, 1);
  await harness.storage.local.set({ downloadRules: { candidateExtensions: [], previewExtensions: [] } });
  await navigate();
  assert.equal(harness.tabUpdates.length, 1);
  assert.equal((await capture()).accepted, false);
  assert.equal(harness.nativeMessages.length, 1, "Stale page requests must respect saved opt-outs");
});

test("preview opt-in still rejects login pages, HEAD errors and HTTPS downgrades", async () => {
  for (const probe of [
    async (url) => ({ ok: true, url, headers: new Headers({ "Content-Type": "text/html" }) }),
    async (url) => ({ ok: false, url, headers: new Headers({ "Content-Type": "video/mp4" }) }),
    async () => ({ ok: true, url: "http://example.com/movie.mp4", headers: new Headers({ "Content-Type": "video/mp4" }) }),
    async () => { throw new Error("HEAD unavailable"); },
  ]) {
    const harness = backgroundHarness({ probe, storage: createStorage({ previewExtensions: ["mp4"] }) });
    const response = await new Promise((resolve) => harness.runtimeOnMessage.listeners[0](
      { type: "captureDownload", automatic: true, url: "https://example.com/movie.mp4" },
      { tab: { id: 7 } }, resolve));
    assert.equal(response.accepted, false);
    assert.equal(harness.nativeMessages.length, 0);
    assert.equal(harness.cookieQueries.length, 0);
  }
});

test("cold-start rules do not redirect a superseded navigation", async () => {
  const storage = createStorage();
  let finishRead;
  storage.local.get = () => new Promise((resolve) => { finishRead = resolve; });
  const harness = backgroundHarness({ storage });
  const navigate = harness.webNavigationOnBeforeNavigate.listeners[0];
  const older = navigate({ frameId: 0, tabId: 7, url: "https://example.com/old.zip" });
  const current = navigate({ frameId: 0, tabId: 7, url: "https://example.com/page" });
  finishRead({});
  await Promise.all([older, current]);
  assert.equal(harness.tabUpdates.length, 0);
});

test("page context menu opens the extension settings", async () => {
  const harness = backgroundHarness();
  harness.runtimeOnInstalled.listeners[0]();
  await new Promise((resolve) => setImmediate(resolve));
  assert.ok(harness.contextMenuCreates.some((menu) => menu.id === "sdm-download-settings"));
  harness.contextMenusOnClicked.listeners[0]({ menuItemId: "sdm-download-settings" }, { id: 7 });
  assert.equal(harness.optionsOpened.length, 1);
  assert.equal(harness.nativeMessages.length, 0);
});

for (const browserName of ["chrome", "safari"]) {
  test(`${browserName} collector preserves the tab's store and partition, and rejects cookie-read failure`, async () => {
    const queryCalls = [], payloads = [], updates = [], listeners = [];
    let denied = false;
    const api = {
      storage: createStorage(),
      runtime: { id: "sdm", getURL: (path) => `chrome-extension://sdm/${path}`, onInstalled: eventHook() },
      tabs: { async update(id, options) { updates.push(options.url); } },
      contextMenus: { async removeAll() {}, create() {}, onClicked: eventHook() },
      webNavigation: { onBeforeNavigate: eventHook() },
      cookies: {
        async getAllCookieStores() { return [{ id: "private-profile", tabIds: [8] }, { id: "default", tabIds: [1] }]; },
        async getPartitionKey() { return { partitionKey: { topLevelSite: "https://example.com", hasCrossSiteAncestor: false } }; },
        async getAll(filter) {
          if (denied) throw new Error("Permission denied");
          queryCalls.push(filter);
          return [{name: filter.partitionKey ? "partition" : "session", value: "secret", domain: "cdn.example.com", path: "/", hostOnly: true, secure: true},
            {name: "expired", value: "old", expirationDate: 1}];
        },
      },
    };
    const context = vm.createContext({ URL, navigator: { userAgent: "Fixture Browser" } });
    vm.runInContext(fs.readFileSync(sourcePath("Shared/download-support.js"), "utf8"), context);
    vm.runInContext(fs.readFileSync(sourcePath("Shared/background-controller.js"), "utf8"), context);
    vm.runInContext(fs.readFileSync(sourcePath("Shared/download-settings.js"), "utf8"), context);
    context.SDMBackgroundController.start({api, browser: browserName, action:{onClicked:eventHook()},
      addMessageListener(listener) { listeners.push(listener); }, registerContextMenuOnInstall: true,
      async sendToApp(payload) { payloads.push(payload); return {accepted:true}; }});
    const sender = { id: "sdm", tab: { id: 8 }, url: "https://example.com/account?private=1", frameId: 2 };
    const message = {type:"captureDownload", url:"https://cdn.example.com/file.xip"};
    assert.equal((await listeners[0](message, sender)).accepted, true);
    assert.equal(queryCalls.length, 2);
    assert(queryCalls.every((q) => q.storeId === "private-profile" && q.url === message.url));
    assert.equal(queryCalls[1].partitionKey.topLevelSite, "https://example.com");
    assert.deepEqual(Array.from(payloads[0].requestContext.cookies, (c) => c.name), ["session", "partition"]);
    assert.equal(payloads[0].requestContext.referrer, "https://example.com/");
    assert.equal(payloads[0].requestContext.userAgent, "Fixture Browser");
    denied = true;
    assert.equal((await listeners[0](message, sender)).accepted, false);
    assert.equal(payloads.length, 1, "Permission failure must not create an anonymous task");
    api.webNavigation.onBeforeNavigate.listeners[0]({frameId:0, tabId:8, url:message.url});
    assert.equal(updates.length, 0, "Browser fallback must not be immediately recaptured");
  });
}
