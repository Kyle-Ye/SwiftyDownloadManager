(() => {
  const extensionAPI = globalThis.browser ?? globalThis.chrome;
  const callbackScheme = "swifty-download-manager";
  const pageBridgeSource = "swifty-download-manager-page-bridge";
  const pageBridgeToken = globalThis.crypto.randomUUID();
  const downloadableExtensions = new Set([
    "7z", "aac", "apk", "app", "arc", "arj", "avi", "bin", "bz2", "cab",
    "csv", "dmg", "doc", "docx", "epub", "exe", "flac", "gz", "img", "iso",
    "jar", "key", "m4a", "m4v", "mkv", "mov", "mp3", "mp4", "mpeg", "mpg",
    "msi", "numbers", "odf", "ods", "odt", "pages", "pdf", "pkg", "ppt",
    "pptx", "rar", "rtf", "tar", "tgz", "tif", "tiff", "ts", "txt", "wav",
    "webm", "wma", "wmv", "xls", "xlsx", "xip", "xz", "zip", "zipx"
  ]);

  function linkFromEvent(event) {
    for (const node of event.composedPath()) {
      if (node instanceof HTMLAnchorElement || node instanceof HTMLAreaElement) {
        return node;
      }
    }
    return null;
  }

  function parsedHTTPURL(value) {
    try {
      const url = new URL(value, document.baseURI);
      return url.protocol === "http:" || url.protocol === "https:" ? url : null;
    } catch {
      return null;
    }
  }

  function inferredExtension(url) {
    const name = url.pathname.split("/").pop() ?? "";
    const separator = name.lastIndexOf(".");
    return separator >= 0 ? name.slice(separator + 1).toLowerCase() : "";
  }

  function isDownloadLink(link, url) {
    return link.hasAttribute("download") || isDownloadURL(url);
  }

  function isDownloadURL(url) {
    return downloadableExtensions.has(inferredExtension(url));
  }

  function suggestedFilename(link) {
    if (!(link instanceof HTMLAnchorElement) || !link.hasAttribute("download")) {
      return undefined;
    }
    const value = link.getAttribute("download")?.trim();
    return value || undefined;
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
    link.href = callbackURL("download", {
      url: url.href,
      filename,
      source: window.location.href,
    });
    link.target = "_self";
    if (link instanceof HTMLAnchorElement) {
      link.removeAttribute("download");
    }

    event.stopImmediatePropagation();
  }, true);
})();
