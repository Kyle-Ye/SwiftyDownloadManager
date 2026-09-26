(() => {
  // A filename is only a reason to check the response, never proof of a download.
  // Leave formats browsers can display (text, PDF, images and media) alone.
  const downloadCandidateExtensions = Object.freeze([
    "7z", "apk", "app", "arc", "arj", "bin", "bz2", "cab", "dmg", "doc",
    "docx", "epub", "exe", "gz", "img", "iso", "jar", "key", "msi",
    "numbers", "odf", "ods", "odt", "pages", "pkg", "ppt", "pptx", "rar",
    "tar", "tgz", "xls", "xlsx", "xip", "xz", "zip", "zipx"
  ]);
  const defaultDownloadRules = Object.freeze({
    candidateExtensions: downloadCandidateExtensions,
    previewExtensions: Object.freeze([]),
  });

  function parseExtensionList(value) {
    const items = typeof value === "string" ? value.split(/[\s,;]+/).filter(Boolean) : value;
    if (!Array.isArray(items) || items.length > 200) {
      throw new Error("Enter up to 200 file extensions, separated by commas or spaces.");
    }
    const extensions = items.map((item) => {
      if (typeof item !== "string") throw new Error("File extensions must be text.");
      const extension = item.trim().replace(/^\./, "").toLowerCase();
      if (!/^[a-z0-9]{1,16}$/.test(extension)) {
        throw new Error("Use extensions such as zip or mp4, without URLs, wildcards, or compound suffixes.");
      }
      return extension;
    });
    return Object.freeze([...new Set(extensions)].sort());
  }

  function normalizeDownloadRules(value) {
    return Object.freeze({
      candidateExtensions: parseExtensionList(value?.candidateExtensions ?? downloadCandidateExtensions),
      previewExtensions: parseExtensionList(value?.previewExtensions ?? []),
    });
  }

  function candidateExtensions(rules = defaultDownloadRules) {
    return [...new Set([...rules.candidateExtensions, ...rules.previewExtensions])];
  }
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

  function isDownloadCandidateURL(value, baseURL, rules = defaultDownloadRules) {
    const url = parsedHTTPURL(value, baseURL);
    return url !== null && candidateExtensions(rules).includes(inferredExtension(url));
  }

  function isDownloadResponse(response, url, rules = defaultDownloadRules) {
    if (!response.ok) return false;
    const contentType = response.headers.get("Content-Type")?.split(";")[0].trim().toLowerCase();
    const target = parsedHTTPURL(url);
    if (target && rules.previewExtensions.includes(inferredExtension(target))) {
      // Opting into a previewable type must not turn an HTML preview or login
      // page into a download. An absent MIME type is not evidence of a file.
      return Boolean(contentType) && contentType !== "text/html" && contentType !== "application/xhtml+xml";
    }
    const disposition = response.headers.get("Content-Disposition")?.split(";")[0].trim().toLowerCase();
    if (disposition === "attachment") return true;
    if (disposition) return false;
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
    candidateExtensions,
    defaultDownloadRules,
    downloadCandidateExtensions,
    isDownloadCandidateURL,
    isDownloadResponse,
    isHTTPURL,
    normalizeDownloadRules,
    parseExtensionList,
    parsedHTTPURL,
  });
})();
