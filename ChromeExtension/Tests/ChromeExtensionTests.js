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
  const contextMenuCreates = [];
  const tabUpdates = [];
  const runtimeOnInstalled = eventHook();
  const runtimeOnMessage = eventHook();
  const contextMenusOnClicked = eventHook();
  const actionOnClicked = eventHook();
  const webNavigationOnBeforeNavigate = eventHook();

  const chrome = {
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
  assert.deepEqual(manifest.permissions.sort(), ["contextMenus", "webNavigation"]);
  assert.deepEqual(manifest.host_permissions, ["http://*/*", "https://*/*"]);
  assert.ok(manifest.content_scripts.some((contentScript) =>
    contentScript.world === "MAIN" && contentScript.js.includes("Shared/page.js")
  ));

  const packagedResources = [
    "background.js",
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

test("background forwards page downloads through the app callback scheme", async () => {
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
  assert.equal(harness.tabUpdates.length, 1);
  const callback = new URL(harness.tabUpdates[0].options.url);
  assert.equal(callback.protocol, "swifty-download-manager:");
  assert.equal(callback.hostname, "download");
  assert.equal(callback.searchParams.get("browser"), "chrome");
  assert.equal(
    callback.searchParams.get("url"),
    "https://cdn.example.com/release.zip"
  );
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
  await Promise.resolve();

  harness.actionOnClicked.listeners[0]({ id: 12 });
  await Promise.resolve();

  assert.equal(new URL(harness.tabUpdates[0].options.url).hostname, "download");
  assert.equal(new URL(harness.tabUpdates[1].options.url).hostname, "open");
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
