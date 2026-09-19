(() => {
  const parameters = new URLSearchParams(window.location.search);
  const downloadURLText = parameters.get("url");
  const openAppLink = document.getElementById("open-app");
  const downloadURLLabel = document.getElementById("download-url");
  const errorLabel = document.getElementById("error");

  let downloadURL;
  try {
    downloadURL = new URL(downloadURLText);
    if (downloadURL.protocol !== "http:" && downloadURL.protocol !== "https:") {
      throw new Error("Unsupported download URL scheme");
    }
  } catch {
    openAppLink.hidden = true;
    errorLabel.hidden = false;
    return;
  }

  downloadURLLabel.textContent = downloadURL.href;
  openAppLink.href = "#";
  openAppLink.addEventListener("click", async (event) => {
    event.preventDefault();
    const api = globalThis.browser ?? globalThis.chrome;
    try {
      const result = await api.runtime.sendMessage({ type: "captureDownload", url: downloadURL.href });
      if (result?.accepted) return;
      errorLabel.textContent = result?.error ?? "Open SDM and try again, or continue in your browser.";
      // The background collector grants a one-use bypass before rejecting.
      // Return to the authenticated browser download without recapturing it.
      window.location.assign(downloadURL.href);
    } catch {
      errorLabel.textContent = "Open SDM and try again, or continue in your browser.";
    }
    errorLabel.hidden = false;
  });
})();
