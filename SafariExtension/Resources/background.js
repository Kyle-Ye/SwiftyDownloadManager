const extensionAPI = globalThis.browser ?? globalThis.chrome;
const nativeApplicationIdentifier = "top.kyleye.swifty-download-manager-app";
const contextMenuIdentifier = "download-with-sdm";

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

extensionAPI.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId !== contextMenuIdentifier || !isHTTPURL(info.linkUrl)) {
    return;
  }

  void sendToApp({
    type: "download",
    url: info.linkUrl,
    sourcePage: info.pageUrl ?? tab?.url,
  });
});

extensionAPI.browserAction.onClicked.addListener(() => {
  void sendToApp({ type: "openApp" });
});

void registerContextMenu();
