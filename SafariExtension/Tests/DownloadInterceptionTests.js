const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");
const { createStorage } = require("../../BrowserExtension/Tests/extension-storage");
const settingsSource = fs.readFileSync(path.join(__dirname, "../../BrowserExtension/Shared/download-settings.js"), "utf8");

const resourcesDirectory = path.join(__dirname, "..", "Resources");
const sharedResourcesDirectory = path.join(
  __dirname,
  "..",
  "..",
  "BrowserExtension",
  "Shared"
);
const contentSource = fs.readFileSync(
  path.join(sharedResourcesDirectory, "content.js"),
  "utf8"
);
const downloadSupportSource = fs.readFileSync(
  path.join(sharedResourcesDirectory, "download-support.js"),
  "utf8"
);
const pageSource = fs.readFileSync(
  path.join(sharedResourcesDirectory, "page.js"),
  "utf8"
);
const platformSource = fs.readFileSync(
  path.join(resourcesDirectory, "platform.js"),
  "utf8"
);
const backgroundControllerSource = fs.readFileSync(
  path.join(sharedResourcesDirectory, "background-controller.js"),
  "utf8"
);
const backgroundSource = fs.readFileSync(
  path.join(resourcesDirectory, "background.js"),
  "utf8"
);
const bridgeSource = "swifty-download-manager-page-bridge";
const pageOrigin = "https://www.trae.cn";

class FakeEventTarget {
  constructor() {
    this.listeners = new Map();
  }

  addEventListener(type, listener) {
    const listeners = this.listeners.get(type) ?? [];
    listeners.push(listener);
    this.listeners.set(type, listeners);
  }

  dispatch(type, event) {
    for (const listener of this.listeners.get(type) ?? []) {
      listener.call(this, event);
    }
  }
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

function safariBackgroundHarness() {
  const nativeMessages = [];
  const tabUpdates = [];
  const runtimeOnMessage = eventHook();
  const browser = {
    storage: createStorage(),
    cookies: {
      async getAll() { return [{name: "session", value: "safari-secret", domain: "cdn.example.com", path: "/", secure: true, hostOnly: true}]; },
      async getAllCookieStores() { return [{id: "safari-profile", tabIds: [9]}]; },
    },
    browserAction: { onClicked: eventHook() },
    contextMenus: {
      create() {},
      onClicked: eventHook(),
      removeAll() {
        return Promise.resolve();
      },
    },
    runtime: {
      getURL(resource) {
        return `safari-web-extension://test-extension/${resource}`;
      },
      onMessage: runtimeOnMessage,
      sendNativeMessage(applicationIdentifier, message) {
        nativeMessages.push({ applicationIdentifier, message });
        return Promise.resolve({ accepted: true });
      },
    },
    tabs: {
      update(tabID, options) {
        tabUpdates.push({ options, tabID });
        return Promise.resolve({ id: tabID });
      },
    },
    webNavigation: { onBeforeNavigate: eventHook() },
  };
  const context = vm.createContext({
    Error,
    Object,
    Promise,
    Set,
    String,
    URL,
    browser,
    console,
  });
  vm.runInContext(downloadSupportSource, context);
  vm.runInContext(settingsSource, context);
  vm.runInContext(backgroundControllerSource, context);
  vm.runInContext(backgroundSource, context);

  return { nativeMessages, runtimeOnMessage, tabUpdates };
}

async function pageBridgeHarness({ initialize = true } = {}) {
  const originalOpenCalls = [];
  const postedMessages = [];
  const timeouts = new Map();
  const document = new FakeEventTarget();
  const window = new FakeEventTarget();
  let nextTimeout = 1;

  document.baseURI = `${pageOrigin}/`;
  window.location = { origin: pageOrigin };
  window.open = (...args) => {
    originalOpenCalls.push(args);
    return { opened: true };
  };
  window.postMessage = (message, targetOrigin) => {
    postedMessages.push({ message, targetOrigin });
  };
  window.setTimeout = (callback) => {
    const identifier = nextTimeout++;
    timeouts.set(identifier, callback);
    return identifier;
  };
  window.clearTimeout = (identifier) => {
    timeouts.delete(identifier);
  };

  const context = vm.createContext({
    Date,
    Map,
    Object,
    Set,
    String,
    URL,
    document,
    window,
  });
  // MAIN has its own globals. The helper is loaded only in the isolated
  // content-script world; sharing it here hid the browser's runtime failure.
  vm.runInContext(pageSource, context);

  if (initialize) {
    window.dispatch("message", {
      data: (await contentBridgeHarness()).postedMessages.at(-1).message,
      origin: pageOrigin,
      source: window,
    });
  }
  postedMessages.length = 0;

  return {
    document,
    originalOpenCalls,
    postedMessages,
    timeouts,
    window,
  };
}

function dispatchEligibleClick(document) {
  document.dispatch("click", {
    altKey: false,
    button: 0,
    ctrlKey: false,
    isTrusted: true,
    composedPath: () => [],
    metaKey: false,
    shiftKey: false,
  });
}

function replyToPageBridge(harness, request, accepted) {
  harness.window.dispatch("message", {
    data: {
      source: bridgeSource,
      token: "test-token",
      type: "downloadResponse",
      id: request.message.id,
      accepted,
    },
    origin: pageOrigin,
    source: harness.window,
  });
}

test("programmatic download is captured after a real click", async () => {
  const harness = await pageBridgeHarness();
  dispatchEligibleClick(harness.document);

  const result = harness.window.open(
    "https://cdn.example.com/TRAE_Work_CN-darwin-arm64.dmg",
    "_self"
  );

  assert.equal(result, null);
  assert.equal(harness.originalOpenCalls.length, 0);
  assert.equal(harness.postedMessages.length, 1);
  assert.equal(harness.postedMessages[0].message.type, "downloadRequest");
  assert.equal(
    harness.postedMessages[0].message.url,
    "https://cdn.example.com/TRAE_Work_CN-darwin-arm64.dmg"
  );

  replyToPageBridge(harness, harness.postedMessages[0], true);
  assert.equal(harness.originalOpenCalls.length, 0);
  assert.equal(harness.timeouts.size, 0);
});

test("window.open remains native until the isolated-world bridge is ready", async () => {
  const harness = await pageBridgeHarness({ initialize: false });
  dispatchEligibleClick(harness.document);
  assert.deepEqual(harness.window.open("/file.bin", "_self"), { opened: true });
  assert.equal(harness.postedMessages.length, 0);
  assert.deepEqual(harness.originalOpenCalls, [["/file.bin", "_self"]]);
});

test("the standalone page bridge resolves relative download URLs and keeps inline formats native", async () => {
  const harness = await pageBridgeHarness();
  dispatchEligibleClick(harness.document);
  assert.equal(harness.window.open("/empty.BIN?download=1", "_self"), null);
  assert.equal(harness.postedMessages[0].message.url, `${pageOrigin}/empty.BIN?download=1`);
  for (const url of ["/CMakeLists.txt", "/document.pdf", "/page", "blob:fixture", "javascript:void(0)", "http://["]) {
    assert.deepEqual(harness.window.open(url, "_self"), { opened: true });
  }
  assert.equal(harness.postedMessages.length, 1);
  assert.equal(harness.originalOpenCalls.length, 6);
});

test("rejected programmatic download resumes the original window.open", async () => {
  const harness = await pageBridgeHarness();
  dispatchEligibleClick(harness.document);
  harness.window.open("https://cdn.example.com/file.dmg", "_self", "noopener");

  replyToPageBridge(harness, harness.postedMessages[0], false);

  assert.deepEqual(harness.originalOpenCalls, [[
    "https://cdn.example.com/file.dmg",
    "_self",
    "noopener",
  ]]);
  assert.equal(harness.timeouts.size, 0);
});

test("unanswered programmatic download resumes after the bridge timeout", async () => {
  const harness = await pageBridgeHarness();
  dispatchEligibleClick(harness.document);
  harness.window.open("https://cdn.example.com/file.dmg", "_self");

  const timeout = [...harness.timeouts.values()][0];
  timeout();

  assert.deepEqual(harness.originalOpenCalls, [[
    "https://cdn.example.com/file.dmg",
    "_self",
  ]]);
});

test("ordinary navigation and downloads without a click are not captured", async () => {
  const harness = await pageBridgeHarness();

  harness.window.open("https://example.com/page", "_self");
  harness.window.open("https://cdn.example.com/file.dmg", "_self");

  assert.equal(harness.postedMessages.length, 0);
  assert.equal(harness.originalOpenCalls.length, 2);
});

async function contentBridgeHarness({ response = { accepted: true }, storage = createStorage() } = {}) {
  const runtimeMessages = [];
  const postedMessages = [];
  const document = new FakeEventTarget();
  const window = new FakeEventTarget();

  document.baseURI = `${pageOrigin}/`;
  window.location = {
    href: `${pageOrigin}/`,
    origin: pageOrigin,
  };
  window.postMessage = (message, targetOrigin) => {
    postedMessages.push({ message, targetOrigin });
  };

  class HTMLAnchorElement {}
  class HTMLAreaElement {}
  const browser = {
    storage,
    runtime: {
      sendMessage(message) {
        runtimeMessages.push(message);
        return Promise.resolve(response);
      },
    },
  };

  const context = vm.createContext({
    HTMLAnchorElement,
    HTMLAreaElement,
    Object,
    Promise,
    Set,
    URL,
    browser,
    crypto: { randomUUID: () => "test-token" },
    document,
    window,
  });
  vm.runInContext(platformSource, context);
  vm.runInContext(downloadSupportSource, context);
  vm.runInContext(settingsSource, context);
  vm.runInContext(contentSource, context);
  await new Promise((resolve) => setImmediate(resolve));

  return {
    document, HTMLAnchorElement, storage,
    postedMessages,
    runtimeMessages,
    window,
  };
}

test("content bridge forwards a page download request to the extension", async () => {
  const harness = await contentBridgeHarness();
  dispatchEligibleClick(harness.document);
  assert.equal(harness.postedMessages[0].message.type, "bridgeInitialize");
  harness.postedMessages.length = 0;

  harness.window.dispatch("message", {
    data: {
      source: bridgeSource,
      token: "test-token",
      type: "downloadRequest",
      id: "request-1",
      url: "https://cdn.example.com/file.dmg",
    },
    origin: pageOrigin,
    source: harness.window,
  });
  await Promise.resolve();

  assert.equal(harness.runtimeMessages.length, 1);
  assert.equal(harness.runtimeMessages[0].type, "captureDownload");
  assert.equal(harness.runtimeMessages[0].automatic, true);
  assert.equal(harness.runtimeMessages[0].url, "https://cdn.example.com/file.dmg");
  assert.equal(harness.runtimeMessages[0].sourcePage, `${pageOrigin}/`);
  assert.equal(harness.postedMessages[0].message.type, "downloadResponse");
  assert.equal(harness.postedMessages[0].message.accepted, true);
});

test("content bridge rejects unrecognized download URLs", async () => {
  const harness = await contentBridgeHarness();
  harness.postedMessages.length = 0;

  harness.window.dispatch("message", {
    data: {
      source: bridgeSource,
      token: "test-token",
      type: "downloadRequest",
      id: "request-2",
      url: "https://example.com/page",
    },
    origin: pageOrigin,
    source: harness.window,
  });

  assert.equal(harness.runtimeMessages.length, 0);
  assert.equal(harness.postedMessages[0].message.accepted, false);
});

test("page bridge runs as a main-world content script", async () => {
  const manifest = JSON.parse(
    fs.readFileSync(path.join(resourcesDirectory, "manifest.json"), "utf8")
  );
  assert.ok(manifest.content_scripts.some((contentScript) =>
    contentScript.world === "MAIN" && contentScript.js.includes("Shared/page.js")
  ));
});

test("Safari background keeps runtime downloads on native messaging", async () => {
  const harness = safariBackgroundHarness();
  const response = await harness.runtimeOnMessage.listeners[0](
    {
      type: "captureDownload",
      url: "https://cdn.example.com/file.dmg",
      sourcePage: "https://example.com/downloads",
    },
    { tab: { id: 9, url: "https://example.com/downloads" } }
  );

  assert.equal(response.accepted, true);
  assert.equal(harness.nativeMessages.length, 1);
  assert.equal(
    harness.nativeMessages[0].applicationIdentifier,
    "top.kyleye.swifty-download-manager-app"
  );
  assert.equal(harness.nativeMessages[0].message.type, "download");
  assert.equal(harness.nativeMessages[0].message.requestContext.cookies[0].value, "safari-secret");
  assert.equal(harness.tabUpdates.length, 0);
});

test("ordinary anchor clicks use the background collector without modifying the page URL", async () => {
  const harness = await contentBridgeHarness();
  const link = new harness.HTMLAnchorElement();
  link.href = "https://cdn.example.com/file.xip";
  link.hasAttribute = () => false;
  let prevented = false;
  harness.document.dispatch("click", {isTrusted:true, defaultPrevented:false, button:0,
    composedPath:() => [link], preventDefault() {prevented=true;}, stopImmediatePropagation() {}});
  await Promise.resolve();
  assert(prevented);
  assert.equal(harness.runtimeMessages[0].url, link.href);
  assert.equal(harness.runtimeMessages[0].type, "captureDownload");
  assert.equal(link.href, "https://cdn.example.com/file.xip");
});

test("a page cannot start credential collection without a trusted click", async () => {
  const harness = await contentBridgeHarness();
  harness.window.dispatch("message", {source:harness.window, origin:pageOrigin, data:{source:bridgeSource,
    token:"test-token", type:"downloadRequest", id:"forged", url:"https://cdn.example.com/file.xip"}});
  assert.equal(harness.runtimeMessages.length, 0);
  assert.equal(harness.postedMessages.at(-1).message.accepted, false);
});

test("GitHub source pages and inline formats retain normal clicks and window.open", async () => {
  const urls = [
    "https://github.com/swiftlang/swift/blob/swift-6.4.0-RELEASE/stdlib/public/RuntimeModule/CMakeLists.txt",
    "https://example.com/document.pdf", "https://example.com/file.txt",
    "https://example.com/movie.mp4", "https://example.com/audio.mp3",
    "https://example.com/image.tiff", "https://example.com/source.ts",
  ];
  const content = await contentBridgeHarness();
  const page = await pageBridgeHarness();
  dispatchEligibleClick(page.document);
  for (const url of urls) {
    const link = new content.HTMLAnchorElement();
    link.href = url;
    link.hasAttribute = () => false;
    content.document.dispatch("click", { isTrusted: true, button: 0,
      composedPath: () => [link], preventDefault() { assert.fail("Ordinary navigation was intercepted"); } });
    assert.deepEqual(page.window.open(url, "_blank"), { opened: true });
  }
  assert.equal(content.runtimeMessages.length, 0);
  assert.equal(page.postedMessages.length, 0);
  assert.equal(page.originalOpenCalls.length, urls.length);
});

test("a rejected candidate replays its link so browser targets and attributes are preserved", async () => {
  const harness = await contentBridgeHarness({ response: { accepted: false } });
  const link = new harness.HTMLAnchorElement();
  link.href = "https://example.com/file.zip";
  link.target = "_blank";
  link.hasAttribute = () => true;
  link.getAttribute = () => "file.zip";
  let clicks = 0;
  link.click = () => {
    clicks++;
    assert.equal(link.target, "_blank");
    harness.document.dispatch("click", { isTrusted: false,
      preventDefault() { assert.fail("Fallback must not be intercepted again"); } });
  };
  harness.document.dispatch("click", { isTrusted: true, button: 0, composedPath: () => [link],
    preventDefault() {}, stopImmediatePropagation() {} });
  await Promise.resolve();
  assert.equal(clicks, 1);
  assert.equal(harness.runtimeMessages.length, 1);
  assert.equal(harness.runtimeMessages[0].automatic, true);
  assert.equal(harness.runtimeMessages[0].downloadAttribute, true);
  assert.equal(harness.runtimeMessages[0].filename, "file.zip");
});

test("saved rule changes update both existing link interception and the MAIN-world bridge", async () => {
  const content = await contentBridgeHarness();
  const page = await pageBridgeHarness({ initialize: false });
  function updateBridge() {
    page.window.dispatch("message", { source: page.window, origin: pageOrigin,
      data: content.postedMessages.at(-1).message });
  }
  updateBridge();
  dispatchEligibleClick(page.document);
  const url = `${pageOrigin}/movie.MP4?download=1`;
  assert.deepEqual(page.window.open(url, "_self"), { opened: true });
  const link = new content.HTMLAnchorElement();
  link.href = url;
  link.hasAttribute = () => false;
  let prevented = 0;
  const click = () => content.document.dispatch("click", {
    isTrusted: true, button: 0, composedPath: () => [link],
    preventDefault() { prevented++; }, stopImmediatePropagation() {},
  });
  click();
  assert.equal(prevented, 0);
  await content.storage.local.set({ downloadRules: { candidateExtensions: [], previewExtensions: ["mp4"] } });
  updateBridge();
  assert.equal(page.window.open(url, "_self"), null);
  click();
  assert.equal(prevented, 1);
  assert.equal(content.runtimeMessages.at(-1).url, url);
  await content.storage.local.set({ downloadRules: { candidateExtensions: [], previewExtensions: [] } });
  updateBridge();
  assert.deepEqual(page.window.open(url, "_self"), { opened: true });
  click();
  assert.equal(prevented, 1);
});
