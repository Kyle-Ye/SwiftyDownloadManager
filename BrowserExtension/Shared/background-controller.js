(() => {
  const contextMenuIdentifier = "download-with-sdm";

  function start(configuration) {
    const {
      action,
      addMessageListener,
      api,
      browser,
      registerContextMenuOnInstall,
      sendMessagesDirectlyToApp,
      sendToApp,
    } = configuration;
    const downloadSupport = globalThis.SDMDownloadSupport;

    function capturePageURL(downloadURL) {
      const url = new URL(api.runtime.getURL("Shared/capture.html"));
      url.searchParams.set("browser", browser);
      url.searchParams.set("url", downloadURL);
      return url.href;
    }

    async function openCallbackFromTab(tab, host, queryItems, nativeMessage) {
      if (tab?.id !== undefined && api.tabs?.update) {
        try {
          await api.tabs.update(tab.id, {
            url: downloadSupport.callbackURL(host, queryItems, browser),
          });
          return { accepted: true };
        } catch (error) {
          console.error("Unable to open the SDM callback from the browser tab", error);
        }
      }

      if (sendToApp) {
        return sendToApp(nativeMessage);
      }
      return { accepted: false, error: "No browser tab was available." };
    }

    async function registerContextMenu() {
      try {
        await api.contextMenus.removeAll();
        api.contextMenus.create({
          id: contextMenuIdentifier,
          title: "Download with SDM",
          contexts: ["link"],
          targetUrlPatterns: ["http://*/*", "https://*/*"],
        });
      } catch (error) {
        console.error("Unable to register the SDM context menu", error);
      }
    }

    function handleMessage(message, sender) {
      if (message?.type !== "captureDownload" || !downloadSupport.isHTTPURL(message.url)) {
        return undefined;
      }

      const sourcePage = message.sourcePage ?? sender.tab?.url;
      const nativeMessage = {
        type: "download",
        url: message.url,
        filename: message.filename,
        sourcePage,
      };
      if (sendMessagesDirectlyToApp && sendToApp) {
        return sendToApp(nativeMessage);
      }

      return openCallbackFromTab(
        sender.tab,
        "download",
        {
          url: message.url,
          filename: message.filename,
          source: sourcePage,
        },
        nativeMessage
      );
    }

    addMessageListener(handleMessage);

    api.contextMenus.onClicked.addListener((info, tab) => {
      if (
        info.menuItemId !== contextMenuIdentifier ||
        !downloadSupport.isHTTPURL(info.linkUrl)
      ) {
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

    action.onClicked.addListener((tab) => {
      void openCallbackFromTab(tab, "open", {}, { type: "openApp" });
    });

    api.webNavigation.onBeforeNavigate.addListener((details) => {
      if (details.frameId !== 0 || !downloadSupport.isDirectDownloadURL(details.url)) {
        return;
      }

      void api.tabs.update(details.tabId, {
        url: capturePageURL(details.url),
      }).catch((error) => {
        console.error("Unable to capture the direct download navigation", error);
      });
    });

    if (registerContextMenuOnInstall) {
      api.runtime.onInstalled.addListener(() => {
        void registerContextMenu();
      });
    } else {
      void registerContextMenu();
    }
  }

  globalThis.SDMBackgroundController = Object.freeze({ start });
})();
