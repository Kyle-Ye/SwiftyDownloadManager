(() => {
  const callbackScheme = "swifty-download-manager";
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
    return link.hasAttribute("download") || downloadableExtensions.has(inferredExtension(url));
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
