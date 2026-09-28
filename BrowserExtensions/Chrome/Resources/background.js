importScripts(
  "Shared/download-support.js",
  "Shared/download-settings.js",
  "Shared/background-controller.js",
  "handoff.js"
);

globalThis.SDMBackgroundController.start({
  action: chrome.action,
  addMessageListener(listener) {
    chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
      const response = listener(message, sender);
      if (!response) {
        return false;
      }

      void response.then(sendResponse);
      return true;
    });
  },
  api: chrome,
  browser: "chrome",
  registerContextMenuOnInstall: true,
  sendToApp: globalThis.SDMChromeHandoff.send,
});
