const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");
const { createStorage } = require("./extension-storage");
const source = (name) => fs.readFileSync(path.join(__dirname, "../Shared", name), "utf8");

function harness() {
  const context = vm.createContext({ URL });
  vm.runInContext(source("download-support.js"), context);
  vm.runInContext(source("download-settings.js"), context);
  return { support: context.SDMDownloadSupport, settings: context.SDMDownloadSettings };
}

test("extension lists accept dots, case and separators, reject ambiguous patterns, and preserve an empty list", () => {
  const { support } = harness();
  assert.deepEqual([...support.parseExtensionList(".MP4, zip; mp4\n.DMG")], ["dmg", "mp4", "zip"]);
  for (const invalid of ["*.mp4", "tar.gz", "https://example.com/video.mp4", "mp4?x=1", "*", [4]]) {
    assert.throws(() => support.parseExtensionList(invalid));
  }
  const rules = support.normalizeDownloadRules({ candidateExtensions: "", previewExtensions: "" });
  assert.equal(support.isDownloadCandidateURL("https://example.com/a.zip", undefined, rules), false);
});

test("matching uses only the final path suffix, with defaults excluding previewable formats", () => {
  const { support } = harness();
  for (const url of ["https://example.com/a.ZIP?name=a.mp4#x", "https://example.com/a.tar.gz"]) {
    assert.equal(support.isDownloadCandidateURL(url), true);
  }
  for (const url of ["https://example.com/download?name=a.zip", "https://example.com/a.zip/", "https://example.com/a.mp4", "https://example.com/a.pdf", "blob:https://example.com/a.zip"]) {
    assert.equal(support.isDownloadCandidateURL(url), false, url);
  }
  const rules = support.normalizeDownloadRules({ candidateExtensions: [], previewExtensions: ["mp4"] });
  assert.equal(support.isDownloadCandidateURL("/movie.MP4", "https://example.com/", rules), true);
  assert.equal(support.isDownloadCandidateURL("/a.zip", "https://example.com/", rules), false);
});

test("preview opt-in accepts inline files but never HTML, absent types or failed responses", () => {
  const { support } = harness();
  const rules = support.normalizeDownloadRules({ previewExtensions: ["mp4"] });
  const url = "https://example.com/movie.mp4";
  const response = (type, ok = true) => ({ ok, headers: new Headers({ "Content-Disposition": "inline", ...(type ? { "Content-Type": type } : {}) }) });
  assert.equal(support.isDownloadResponse(response("video/mp4"), url), false);
  assert.equal(support.isDownloadResponse(response("video/mp4"), url, rules), true);
  for (const type of ["text/html; charset=utf-8", "application/xhtml+xml", undefined]) {
    assert.equal(support.isDownloadResponse(response(type), url, rules), false);
  }
  assert.equal(support.isDownloadResponse(response("video/mp4", false), url, rules), false);
  assert.equal(support.isDownloadResponse(response("video/mp4"), "https://example.com/movie.zip", rules), false);
});

test("settings load persisted opt-outs and updates, surviving a new background store", async () => {
  const { support, settings } = harness();
  const storage = createStorage({ candidateExtensions: [], previewExtensions: ["mp4"] });
  const store = settings.createStore({ storage });
  assert.equal(support.candidateExtensions(store.rules).length, 0, "Startup must not temporarily restore defaults");
  await store.ready;
  assert.deepEqual([...support.candidateExtensions(store.rules)], ["mp4"]);
  await storage.local.set({ downloadRules: { candidateExtensions: ["dmg"], previewExtensions: [] } });
  assert.deepEqual([...support.candidateExtensions(store.rules)], ["dmg"]);
  const restarted = settings.createStore({ storage });
  await restarted.ready;
  assert.deepEqual([...support.candidateExtensions(restarted.rules)], ["dmg"]);
  storage.emit({ downloadRules: { newValue: { candidateExtensions: ["zip"], previewExtensions: [] } } }, "sync");
  assert.deepEqual([...support.candidateExtensions(store.rules)], ["dmg"], "Other storage areas do not change rules");
  storage.emit({ downloadRules: {} });
  assert.deepEqual([...store.rules.candidateExtensions], [...support.defaultDownloadRules.candidateExtensions].sort());
  assert.equal(store.rules.previewExtensions.length, 0);
});

test("a settings change wins over a stale initial read", async () => {
  const { settings } = harness();
  const storage = createStorage();
  let resolveRead;
  storage.local.get = () => new Promise((resolve) => { resolveRead = resolve; });
  const store = settings.createStore({ storage });
  await storage.local.set({ downloadRules: { candidateExtensions: [], previewExtensions: ["mp4"] } });
  resolveRead({});
  await store.ready;
  assert.deepEqual([...store.rules.previewExtensions], ["mp4"]);
  assert.equal(store.rules.candidateExtensions.length, 0);
});

test("unreadable or malformed settings fail open and a valid change recovers", async () => {
  const { settings, support } = harness();
  for (const malformed of [false, true]) {
    const storage = createStorage({ candidateExtensions: ["*"] });
    if (!malformed) storage.local.get = async () => { throw new Error("Unavailable"); };
    const store = settings.createStore({ storage });
    await store.ready;
    assert.equal(support.candidateExtensions(store.rules).length, 0);
    await storage.local.set({ downloadRules: { previewExtensions: ["mp4"] } });
    assert.deepEqual([...store.rules.previewExtensions], ["mp4"]);
    storage.emit({ downloadRules: { newValue: { candidateExtensions: ["*"] } } });
    assert.equal(support.candidateExtensions(store.rules).length, 0);
  }
});

function optionsHarness(storage) {
  const ids = ["settings-form", "settings-fields", "candidate-extensions", "preview-extensions", "status", "error", "restore"];
  const elements = new Map(ids.map((id) => [id, {
    value: "", hidden: id === "error", disabled: id === "settings-fields", listeners: {},
    addEventListener(type, listener) { this.listeners[type] = listener; },
  }]));
  const context = vm.createContext({ URL, chrome: { storage }, document: { getElementById: (id) => elements.get(id) } });
  for (const file of ["download-support.js", "download-settings.js", "options.js"]) vm.runInContext(source(file), context);
  return { elements, submit: () => elements.get("settings-form").listeners.submit({ preventDefault() {} }) };
}

test("options save normalized rules, reject bad input, restore defaults and report write errors", async () => {
  const storage = createStorage();
  const { elements, submit } = optionsHarness(storage);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(elements.get("settings-fields").disabled, false);
  assert.equal(elements.get("preview-extensions").value, "");
  elements.get("preview-extensions").value = ".MP4 mp4";
  await submit();
  assert.deepEqual(storage.writes.at(-1).downloadRules.previewExtensions, ["mp4"]);
  assert.equal(elements.get("preview-extensions").value, "mp4");
  elements.get("preview-extensions").value = "*.mp4";
  await submit();
  assert.equal(storage.writes.length, 1);
  assert.equal(elements.get("error").hidden, false);
  await elements.get("restore").listeners.click();
  assert.deepEqual(storage.writes.at(-1).downloadRules.previewExtensions, []);
  assert.ok(storage.writes.at(-1).downloadRules.candidateExtensions.includes("zip"));
  assert.equal(elements.get("error").hidden, true);
  storage.local.set = async () => { throw new Error("Disk unavailable"); };
  elements.get("preview-extensions").value = "mp4";
  await submit();
  assert.equal(elements.get("error").hidden, false);
  assert.equal(elements.get("settings-fields").disabled, false);
  assert.equal(elements.get("status").textContent, "");
});
