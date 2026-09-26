(() => {
  // A filename is only a reason to check the response, never proof of a download.
  // Leave formats browsers can display (text, PDF, images and media) alone.
  const downloadCandidateExtensions = new Set([
    "7z", "apk", "app", "arc", "arj", "bin", "bz2", "cab", "dmg", "doc",
    "docx", "epub", "exe", "gz", "img", "iso", "jar", "key", "msi",
    "numbers", "odf", "ods", "odt", "pages", "pkg", "ppt", "pptx", "rar",
    "tar", "tgz", "xls", "xlsx", "xip", "xz", "zip", "zipx"
  ]);
  const downloadContentTypes = new Set([
    "application/octet-stream", "application/zip", "application/gzip",
    "application/x-7z-compressed", "application/x-apple-diskimage",
    "application/x-bzip2", "application/x-gzip", "application/x-rar-compressed",
    "application/vnd.rar", "application/x-tar", "application/x-xz",
    "application/x-zip-compressed", "application/vnd.apple.installer+xml",
    "application/x-iso9660-image", "application/vnd.microsoft.portable-executable",
    "application/x-msdownload", "application/vnd.android.package-archive"
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

  function isDownloadCandidateURL(value, baseURL) {
    const url = parsedHTTPURL(value, baseURL);
    return url !== null && downloadCandidateExtensions.has(inferredExtension(url));
  }

  function isDownloadResponse(response) {
    if (!response.ok) return false;
    const disposition = response.headers.get("Content-Disposition")?.split(";")[0].trim().toLowerCase();
    if (disposition === "attachment") return true;
    if (disposition) return false;
    const contentType = response.headers.get("Content-Type")?.split(";")[0].trim().toLowerCase();
    return downloadContentTypes.has(contentType);
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
    downloadCandidateExtensions: Object.freeze([...downloadCandidateExtensions]),
    isDownloadCandidateURL,
    isDownloadResponse,
    isHTTPURL,
    parsedHTTPURL,
  });
})();
