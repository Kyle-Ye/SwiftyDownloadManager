(() => {
  const downloadableExtensions = new Set([
    "7z", "aac", "apk", "app", "arc", "arj", "avi", "bin", "bz2", "cab",
    "csv", "dmg", "doc", "docx", "epub", "exe", "flac", "gz", "img", "iso",
    "jar", "key", "m4a", "m4v", "mkv", "mov", "mp3", "mp4", "mpeg", "mpg",
    "msi", "numbers", "odf", "ods", "odt", "pages", "pdf", "pkg", "ppt",
    "pptx", "rar", "rtf", "tar", "tgz", "tif", "tiff", "ts", "txt", "wav",
    "webm", "wma", "wmv", "xls", "xlsx", "xip", "xz", "zip", "zipx"
  ]);

  function parsedHTTPURL(value, baseURL) {
    try {
      const url = baseURL === undefined
        ? new URL(value)
        : new URL(value, baseURL);
      return url.protocol === "http:" || url.protocol === "https:" ? url : null;
    } catch {
      return null;
    }
  }

  function isHTTPURL(value) {
    return parsedHTTPURL(value) !== null;
  }

  function inferredExtension(url) {
    const filename = url.pathname.split("/").pop() ?? "";
    const separator = filename.lastIndexOf(".");
    return separator >= 0 ? filename.slice(separator + 1).toLowerCase() : "";
  }

  function isDirectDownloadURL(value, baseURL) {
    const url = parsedHTTPURL(value, baseURL);
    return url !== null && downloadableExtensions.has(inferredExtension(url));
  }

  function callbackURL(host, queryItems = {}, browser) {
    const url = new URL(`swifty-download-manager://${host}`);
    if (typeof browser === "string" && browser.length > 0) {
      url.searchParams.set("browser", browser);
    }
    for (const [name, value] of Object.entries(queryItems)) {
      if (typeof value === "string" && value.length > 0) {
        url.searchParams.set(name, value);
      }
    }
    return url.href;
  }

  globalThis.SDMDownloadSupport = Object.freeze({
    callbackURL,
    isDirectDownloadURL,
    isHTTPURL,
    parsedHTTPURL,
  });
})();
