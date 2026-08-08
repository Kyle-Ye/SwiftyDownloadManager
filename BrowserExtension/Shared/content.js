(() => {
  const extensionPlatform = globalThis.SDMExtensionPlatform;
  const extensionAPI = extensionPlatform.api;
  const downloadSupport = globalThis.SDMDownloadSupport;
  const pageBridgeSource = "swifty-download-manager-page-bridge";
  const pageBridgeToken = globalThis.crypto.randomUUID();

  function linkFromEvent(event) {
    for (const node of event.composedPath()) {
      if (node instanceof HTMLAnchorElement || node instanceof HTMLAreaElement) {
        return node;
      }
    }
    return null;
  }

  function parsedHTTPURL(value) {
    return downloadSupport.parsedHTTPURL(value, document.baseURI);
  }

  function isDownloadLink(link, url) {
    return link.hasAttribute("download") || isDownloadURL(url);
  }

  function isDownloadURL(url) {
    return downloadSupport.isDirectDownloadURL(url.href);
  }

  function suggestedFilename(link) {
    if (!(link instanceof HTMLAnchorElement) || !link.hasAttribute("download")) {
      return undefined;
    }
    const value = link.getAttribute("download")?.trim();
    return value || undefined;
  }

  function postPageBridgeResponse(id, accepted) {
    window.postMessage({
      source: pageBridgeSource,
      token: pageBridgeToken,
      type: "downloadResponse",
      id,
      accepted,
    }, window.location.origin);
  }

  function postPageBridgeInitialization() {
    window.postMessage({
      source: pageBridgeSource,
      token: pageBridgeToken,
      type: "bridgeInitialize",
    }, window.location.origin);
  }

  window.addEventListener("message", (event) => {
    const message = event.data;
    if (
      event.source !== window ||
      event.origin !== window.location.origin ||
      message?.source !== pageBridgeSource
    ) {
      return;
    }

    if (message.type === "bridgeReady") {
      postPageBridgeInitialization();
      return;
    }

    if (
      message.token !== pageBridgeToken ||
      message.type !== "downloadRequest" ||
      typeof message.id !== "string"
    ) {
      return;
    }

    const url = parsedHTTPURL(message.url);
    if (!url || !isDownloadURL(url)) {
      postPageBridgeResponse(message.id, false);
      return;
    }

    void extensionAPI.runtime.sendMessage({
      type: "captureDownload",
      url: url.href,
      sourcePage: window.location.href,
    }).then((response) => {
      postPageBridgeResponse(message.id, response?.accepted === true);
    }).catch(() => {
      postPageBridgeResponse(message.id, false);
    });
  });

  postPageBridgeInitialization();

  document.addEventListener("click", (event) => {
    if (
      event.defaultPrevented ||
      event.button !== 0 ||
      event.altKey ||
      event.ctrlKey ||
      event.metaKey ||
      event.shiftKey
    ) {
      return;
    }

    const link = linkFromEvent(event);
    const url = link ? parsedHTTPURL(link.href) : null;
    if (!link || !url || !isDownloadLink(link, url)) {
      return;
    }

    const filename = suggestedFilename(link);
    link.href = downloadSupport.callbackURL(
      "download",
      {
        url: url.href,
        filename,
        source: window.location.href,
      },
      extensionPlatform.browser
    );
    link.target = "_self";
    if (link instanceof HTMLAnchorElement) {
      link.removeAttribute("download");
    }

    event.stopImmediatePropagation();
  }, true);
})();
