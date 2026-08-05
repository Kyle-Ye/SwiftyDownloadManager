const extensionAPI = globalThis.browser ?? globalThis.chrome;
const nativeApplicationIdentifier = "top.kyleye.swifty-download-manager-app";
const contextMenuIdentifier = "download-with-sdm";
const callbackScheme = "swifty-download-manager";
const downloadableExtensions = new Set([
  "7z", "aac", "apk", "app", "arc", "arj", "avi", "bin", "bz2", "cab",
  "csv", "dmg", "doc", "docx", "epub", "exe", "flac", "gz", "img", "iso",
  "jar", "key", "m4a", "m4v", "mkv", "mov", "mp3", "mp4", "mpeg", "mpg",
  "msi", "numbers", "odf", "ods", "odt", "pages", "pdf", "pkg", "ppt",
  "pptx", "rar", "rtf", "tar", "tgz", "tif", "tiff", "ts", "txt", "wav",
  "webm", "wma", "wmv", "xls", "xlsx", "xip", "xz", "zip", "zipx"
]);

function isHTTPURL(value) {
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

async function sendToApp(message) {
  try {
    const response = await extensionAPI.runtime.sendNativeMessage(
      nativeApplicationIdentifier,
      message
    );
    return response ?? { accepted: false, error: "SDM did not respond." };
  } catch (error) {
    return {
      accepted: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

function callbackURL(host, queryItems = {}) {
  const url = new URL(`${callbackScheme}://${host}`);
  for (const [name, value] of Object.entries(queryItems)) {
    if (typeof value === "string" && value.length > 0) {
      url.searchParams.set(name, value);
    }
  }
  return url.href;
}

function isDirectDownloadURL(value) {
  try {
    const url = new URL(value);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return false;
    }

    const filename = url.pathname.split("/").pop() ?? "";
    const separator = filename.lastIndexOf(".");
    const extension = separator >= 0
      ? filename.slice(separator + 1).toLowerCase()
      : "";
    return downloadableExtensions.has(extension);
  } catch {
    return false;
  }
}

function capturePageURL(downloadURL) {
  const url = new URL(extensionAPI.runtime.getURL("capture.html"));
  url.searchParams.set("url", downloadURL);
  return url.href;
}

async function openCallbackFromTab(tab, host, queryItems, nativeMessage) {
  if (tab?.id !== undefined && extensionAPI.tabs?.update) {
    try {
      await extensionAPI.tabs.update(tab.id, {
        url: callbackURL(host, queryItems),
      });
      return { accepted: true };
    } catch (error) {
      console.error("Unable to open the SDM callback from the Safari tab", error);
    }
  }

  return sendToApp(nativeMessage);
}

async function registerContextMenu() {
  try {
    await extensionAPI.contextMenus.removeAll();
    extensionAPI.contextMenus.create({
      id: contextMenuIdentifier,
      title: "Download with SDM",
      contexts: ["link"],
      targetUrlPatterns: ["http://*/*", "https://*/*"],
    });
  } catch (error) {
    console.error("Unable to register the SDM context menu", error);
  }
}

extensionAPI.runtime.onMessage.addListener((message, sender) => {
  if (message?.type !== "captureDownload" || !isHTTPURL(message.url)) {
    return undefined;
  }

  return sendToApp({
    type: "download",
    url: message.url,
    filename: message.filename,
    sourcePage: message.sourcePage ?? sender?.tab?.url,
  });
});

if (extensionAPI.contextMenus?.onClicked) {
  extensionAPI.contextMenus.onClicked.addListener((info, tab) => {
    if (info.menuItemId !== contextMenuIdentifier || !isHTTPURL(info.linkUrl)) {
      return;
    }

    const sourcePage = info.pageUrl ?? tab?.url;
    void openCallbackFromTab(
      tab,
      "download",
      {
        url: info.linkUrl,
        source: sourcePage,
      },
      {
        type: "download",
        url: info.linkUrl,
        sourcePage,
      }
    );
  });

  void registerContextMenu();
}

extensionAPI.browserAction.onClicked.addListener((tab) => {
  void openCallbackFromTab(tab, "open", {}, { type: "openApp" });
});

if (extensionAPI.webNavigation?.onBeforeNavigate) {
  extensionAPI.webNavigation.onBeforeNavigate.addListener((details) => {
    if (details.frameId !== 0 || !isDirectDownloadURL(details.url)) {
      return;
    }

    void extensionAPI.tabs.update(details.tabId, {
      url: capturePageURL(details.url),
    }).catch((error) => {
      console.error("Unable to capture the direct download navigation", error);
    });
  });
}
