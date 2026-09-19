const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

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

function backgroundHarness() {
  const nativeMessages = [];
  const cookieQueries = [];
  const contextMenuCreates = [];
  const tabUpdates = [];
  const runtimeOnInstalled = eventHook();
  const runtimeOnMessage = eventHook();
  const contextMenusOnClicked = eventHook();
  const actionOnClicked = eventHook();
  const webNavigationOnBeforeNavigate = eventHook();

  const chrome = {
    cookies: {
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
    nativeMessages, cookieQueries,
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
  assert.deepEqual(manifest.permissions.sort(), ["contextMenus", "cookies", "webNavigation"]);
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
    "Shared/page.js",
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
    "Shared/content.js",
    "Shared/download-support.js",
    "Shared/page.js",
  ]);
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
  await Promise.resolve();

  assert.equal(harness.tabUpdates.length, 1);
  const capturePage = new URL(harness.tabUpdates[0].options.url);
  assert.equal(capturePage.protocol, "chrome-extension:");
  assert.equal(capturePage.pathname, "/Shared/capture.html");
  assert.equal(
    capturePage.searchParams.get("url"),
    "https://cdn.example.com/application.pkg"
  );
});

test("the shared confirmation page returns rejected handoffs to the browser", async () => {
  for (const browser of ["chrome", "browser"]) {
    const elements = new Map(["open-app", "download-url", "error"].map((id) => [id, {
      addEventListener(_type, listener) { this.click = listener; },
    }]));
    const navigations = [];
    const downloadURL = "https://example.com/file.xip";
    const context = vm.createContext({ URL, URLSearchParams,
      document: { getElementById(id) { return elements.get(id); } },
      window: { location: { search: `?url=${encodeURIComponent(downloadURL)}`,
        assign(url) { navigations.push(url); } } },
      [browser]: { runtime: { async sendMessage(message) {
        assert.equal(message.type, "captureDownload");
        assert.equal(message.url, downloadURL);
        return { accepted: false };
      } } },
    });
    vm.runInContext(fs.readFileSync(sourcePath("Shared/capture.js"), "utf8"), context);
    await elements.get("open-app").click({ preventDefault() {} });
    assert.deepEqual(navigations, [downloadURL]);
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

for (const browserName of ["chrome", "safari"]) {
  test(`${browserName} collector preserves the tab's store and partition, and rejects cookie-read failure`, async () => {
    const queryCalls = [], payloads = [], updates = [], listeners = [];
    let denied = false;
    const api = {
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
