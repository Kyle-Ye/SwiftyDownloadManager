(() => {
  const pageBridgeSource = "swifty-download-manager-page-bridge";
  const userGestureLifetimeMilliseconds = 30_000;
  const responseTimeoutMilliseconds = 40_000;

  if (window.__sdmPageBridgeInstalled === true) {
    return;
  }
  window.__sdmPageBridgeInstalled = true;

  const originalWindowOpen = window.open.bind(window);
  const pendingDownloads = new Map();
  let bridgeToken;
  let downloadCandidateExtensions = new Set();
  let lastEligibleClickMilliseconds = 0;
  let requestOrdinal = 0;

  function parsedDownloadURL(value) {
    try {
      const url = new URL(String(value), document.baseURI);
      if (url.protocol !== "http:" && url.protocol !== "https:") return null;
      const filename = url.pathname.split("/").pop() ?? "";
      const separator = filename.lastIndexOf(".");
      const extension = separator >= 0 ? filename.slice(separator + 1).toLowerCase() : "";
      return downloadCandidateExtensions.has(extension) ? url : null;
    } catch {
      return null;
    }
  }

  function hasRecentEligibleClick() {
    return Date.now() - lastEligibleClickMilliseconds <= userGestureLifetimeMilliseconds;
  }

  function resumeDownload(request) {
    originalWindowOpen(...request.arguments);
  }

  function finishRequest(id, accepted) {
    const request = pendingDownloads.get(id);
    if (!request) {
      return;
    }
    pendingDownloads.delete(id);
    window.clearTimeout(request.timeout);
    if (!accepted) {
      resumeDownload(request);
    }
  }

  document.addEventListener("click", (event) => {
    if (
      event.isTrusted &&
      event.button === 0 &&
      !event.altKey &&
      !event.ctrlKey &&
      !event.metaKey &&
      !event.shiftKey
    ) {
      lastEligibleClickMilliseconds = Date.now();
    }
  }, true);

  window.addEventListener("message", (event) => {
    const message = event.data;
    if (
      event.source !== window ||
      event.origin !== window.location.origin ||
      message?.source !== pageBridgeSource
    ) {
      return;
    }

    if (message.type === "bridgeInitialize" && typeof message.token === "string" &&
        Array.isArray(message.downloadCandidateExtensions) &&
        message.downloadCandidateExtensions.every((value) => typeof value === "string")) {
      // MAIN is self-contained. Receive plain matching data from the isolated
      // script instead of assuming its helper global is available in this world.
      downloadCandidateExtensions = new Set(message.downloadCandidateExtensions);
      bridgeToken = message.token;
      return;
    }

    if (
      !bridgeToken ||
      message.token !== bridgeToken ||
      message.type !== "downloadResponse" ||
      typeof message.id !== "string"
    ) {
      return;
    }
    finishRequest(message.id, message.accepted === true);
  });

  window.open = function (...args) {
    if (!bridgeToken || !hasRecentEligibleClick()) {
      return originalWindowOpen(...args);
    }
    const url = parsedDownloadURL(args[0]);
    if (!url) {
      return originalWindowOpen(...args);
    }

    const id = `${Date.now()}-${requestOrdinal++}`;
    const request = {
      arguments: [url.href, ...args.slice(1)],
      timeout: window.setTimeout(() => finishRequest(id, false), responseTimeoutMilliseconds),
    };
    pendingDownloads.set(id, request);
    window.postMessage({
      source: pageBridgeSource,
      token: bridgeToken,
      type: "downloadRequest",
      id,
      url: url.href,
    }, window.location.origin);
    return null;
  };

  window.postMessage({
    source: pageBridgeSource,
    type: "bridgeReady",
  }, window.location.origin);
})();
