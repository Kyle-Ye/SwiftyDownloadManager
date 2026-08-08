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
  vm.runInContext(backgroundControllerSource, context);
  vm.runInContext(backgroundSource, context);

  return { nativeMessages, runtimeOnMessage, tabUpdates };
}

function pageBridgeHarness() {
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
  vm.runInContext(downloadSupportSource, context);
  vm.runInContext(pageSource, context);

  window.dispatch("message", {
    data: {
      source: bridgeSource,
      token: "test-token",
      type: "bridgeInitialize",
    },
    origin: pageOrigin,
    source: window,
  });
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

test("programmatic download is captured after a real click", () => {
  const harness = pageBridgeHarness();
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

test("rejected programmatic download resumes the original window.open", () => {
  const harness = pageBridgeHarness();
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

test("unanswered programmatic download resumes after the bridge timeout", () => {
  const harness = pageBridgeHarness();
  dispatchEligibleClick(harness.document);
  harness.window.open("https://cdn.example.com/file.dmg", "_self");

  const timeout = [...harness.timeouts.values()][0];
  timeout();

  assert.deepEqual(harness.originalOpenCalls, [[
    "https://cdn.example.com/file.dmg",
    "_self",
  ]]);
});

test("ordinary navigation and downloads without a click are not captured", () => {
  const harness = pageBridgeHarness();

  harness.window.open("https://example.com/page", "_self");
  harness.window.open("https://cdn.example.com/file.dmg", "_self");

  assert.equal(harness.postedMessages.length, 0);
  assert.equal(harness.originalOpenCalls.length, 2);
});

function contentBridgeHarness() {
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
    runtime: {
      sendMessage(message) {
        runtimeMessages.push(message);
        return Promise.resolve({ accepted: true });
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
  vm.runInContext(contentSource, context);

  return {
    postedMessages,
    runtimeMessages,
    window,
  };
}

test("content bridge forwards a page download request to the extension", async () => {
  const harness = contentBridgeHarness();
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
  assert.equal(harness.runtimeMessages[0].url, "https://cdn.example.com/file.dmg");
  assert.equal(harness.runtimeMessages[0].sourcePage, `${pageOrigin}/`);
  assert.equal(harness.postedMessages[0].message.type, "downloadResponse");
  assert.equal(harness.postedMessages[0].message.accepted, true);
});

test("content bridge rejects unrecognized download URLs", () => {
  const harness = contentBridgeHarness();
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

test("page bridge runs as a main-world content script", () => {
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
  assert.equal(harness.tabUpdates.length, 0);
});
