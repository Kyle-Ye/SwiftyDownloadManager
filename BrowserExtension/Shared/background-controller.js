(() => {
  const contextMenuIdentifier = "download-with-sdm";

  function start(configuration) {
    const { action, addMessageListener, api, browser, registerContextMenuOnInstall, sendToApp } = configuration;
    const support = globalThis.SDMDownloadSupport;
    const bypasses = new Map();

    function allowBrowserDownload(tabID, url) {
      bypasses.set(`${tabID}:${url}`, Date.now() + 15_000);
    }

    async function cookiesFor(url, sender) {
      if (!api.cookies?.getAll) throw new Error("Enable SDM's cookie permission and try again.");
      const filter = { url };
      if (sender.tab?.id !== undefined && api.cookies.getAllCookieStores) {
        const stores = await api.cookies.getAllCookieStores();
        const store = stores.find((value) => value.tabIds.includes(sender.tab.id));
        if (!store) throw new Error("The browser cookie store is unavailable.");
        filter.storeId = store.id;
      }
      let cookies = await api.cookies.getAll(filter);
      if (api.cookies.getPartitionKey && sender.tab?.id !== undefined) {
        const { partitionKey } = await api.cookies.getPartitionKey({ tabId: sender.tab.id, frameId: sender.frameId ?? 0 });
        if (partitionKey?.topLevelSite) {
          cookies = cookies.concat(await api.cookies.getAll({ ...filter, partitionKey }));
        }
      }
      return cookies.filter((cookie) => !cookie.expirationDate || cookie.expirationDate > Date.now() / 1000)
        .map(({ name, value, domain, path, secure, hostOnly, expirationDate }) =>
          ({ name, value, domain, path, secure, hostOnly, expirationDate }));
    }

    async function capture(message, sender) {
      try {
        const target = new URL(message.url);
        if (target.username || target.password) throw new Error("URLs containing passwords are unsupported.");
        const source = support.parsedHTTPURL(sender.url) ?? support.parsedHTTPURL(message.sourcePage) ??
          support.parsedHTTPURL(sender.tab?.url);
        // Send only the origin, following the downgrade restriction of strict-origin.
        const referrer = source && !(source.protocol === "https:" && target.protocol !== "https:")
          ? `${source.origin}/` : undefined;
        const payload = {
          type: "download", url: target.href, filename: message.filename,
          requestContext: {
            cookies: await cookiesFor(target.href, sender),
            userAgent: globalThis.navigator?.userAgent,
            referrer,
          },
        };
        const response = await sendToApp(payload, sender.tab);
        if (!response?.accepted) allowBrowserDownload(sender.tab?.id, target.href);
        return response ?? { accepted: false };
      } catch {
        allowBrowserDownload(sender.tab?.id, message.url);
        // Never put browser context or native payloads in logs or page responses.
        return { accepted: false, error: "SDM could not receive the browser session. The download can continue in your browser." };
      }
    }

    function handleMessage(message, sender) {
      if (sender.id && sender.id !== api.runtime.id) return undefined;
      if (message?.type !== "captureDownload" || !support.isHTTPURL(message.url)) return undefined;
      return capture(message, sender);
    }
    addMessageListener(handleMessage);

    async function registerContextMenu() {
      await api.contextMenus.removeAll();
      api.contextMenus.create({ id: contextMenuIdentifier, title: "Download with SDM", contexts: ["link"],
        targetUrlPatterns: ["http://*/*", "https://*/*"] });
    }
    api.contextMenus.onClicked.addListener((info, tab) => {
      if (info.menuItemId !== contextMenuIdentifier || !support.isHTTPURL(info.linkUrl)) return;
      void capture({ url: info.linkUrl, sourcePage: info.pageUrl }, { tab, url: info.pageUrl, frameId: info.frameId })
        .then((response) => {
          if (!response.accepted && tab?.id !== undefined) void api.tabs.update(tab.id, { url: info.linkUrl });
        });
    });
    action.onClicked.addListener((tab) => {
      if (browser === "safari") void sendToApp({ type: "openApp" }, tab);
      else if (tab?.id !== undefined) void api.tabs.update(tab.id, { url: support.callbackURL("open", {}, browser) });
    });
    api.webNavigation.onBeforeNavigate.addListener((details) => {
      if (details.frameId !== 0 || !support.isDirectDownloadURL(details.url)) return;
      const key = `${details.tabId}:${details.url}`;
      for (const [entry, expiry] of bypasses) if (expiry < Date.now()) bypasses.delete(entry);
      if (bypasses.has(key)) { bypasses.delete(key); return; }
      const url = new URL(api.runtime.getURL("Shared/capture.html"));
      url.searchParams.set("url", details.url);
      void api.tabs.update(details.tabId, { url: url.href });
    });
    if (registerContextMenuOnInstall) api.runtime.onInstalled.addListener(() => { void registerContextMenu(); });
    else void registerContextMenu();
  }
  globalThis.SDMBackgroundController = Object.freeze({ start });
})();
