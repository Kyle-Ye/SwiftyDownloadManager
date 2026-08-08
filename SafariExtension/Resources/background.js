const extensionAPI = globalThis.browser ?? globalThis.chrome;
const nativeApplicationIdentifier = "top.kyleye.swifty-download-manager-app";

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

globalThis.SDMBackgroundController.start({
  action: extensionAPI.browserAction,
  addMessageListener(listener) {
    extensionAPI.runtime.onMessage.addListener(listener);
  },
  api: extensionAPI,
  browser: "safari",
  registerContextMenuOnInstall: false,
  sendMessagesDirectlyToApp: true,
  sendToApp,
});
