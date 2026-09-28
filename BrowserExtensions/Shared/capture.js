(() => {
  const parameters = new URLSearchParams(window.location.search);
  const downloadURLText = parameters.get("url");
  const openAppButton = document.getElementById("open-app");
  const continueBrowserButton = document.getElementById("continue-browser");
  const confirmation = document.getElementById("confirmation");
  const downloadURLLabel = document.getElementById("download-url");
  const errorLabel = document.getElementById("error");
  const statusLabel = document.getElementById("status");
  const api = globalThis.browser ?? globalThis.chrome;
  let busy = false;

  function setBusy(value) {
    busy = value;
    openAppButton.disabled = value;
    continueBrowserButton.disabled = value;
  }

  function showStatus(message) {
    errorLabel.hidden = true;
    statusLabel.textContent = message;
    statusLabel.hidden = false;
  }

  function showError(message) {
    errorLabel.textContent = message;
    errorLabel.hidden = false;
    statusLabel.hidden = true;
  }

  async function continueInBrowser() {
    if (busy) return;
    setBusy(true);
    showStatus("Continuing in your browser…");
    try {
      const response = await api.runtime.sendMessage({ type: "continueInBrowser", url: downloadURL.href });
      if (!response?.accepted) throw new Error("Browser continuation failed.");
      // Replace the interstitial so Back cannot return to it and recapture the URL.
      window.location.replace(downloadURL.href);
      showStatus("Download requested in your browser. You can retry if it does not start.");
    } catch {
      continueBrowserButton.hidden = false;
      showError("Could not continue. Please try again or use your browser's Back button.");
    } finally {
      // Attachment navigation can start a download without unloading this page.
      setBusy(false);
    }
  }

  let downloadURL;
  try {
    downloadURL = new URL(downloadURLText);
    if (downloadURL.protocol !== "http:" && downloadURL.protocol !== "https:") {
      throw new Error("Unsupported download URL scheme");
    }
  } catch {
    openAppButton.hidden = true;
    continueBrowserButton.hidden = true;
    errorLabel.hidden = false;
    return;
  }

  downloadURLLabel.textContent = downloadURL.href;
  continueBrowserButton.addEventListener("click", (event) => {
    event.preventDefault();
    return continueInBrowser();
  });
  openAppButton.addEventListener("click", async (event) => {
    event.preventDefault();
    if (confirmation.hidden || busy) return;
    setBusy(true);
    showStatus("Opening SDM…");
    try {
      const result = await api.runtime.sendMessage({ type: "captureDownload", url: downloadURL.href });
      if (result?.accepted) {
        showStatus("Sent to SDM. You can close this tab.");
      } else {
        showError(result?.error ?? "Open SDM and try again, or continue in your browser.");
      }
    } catch {
      showError("Open SDM and try again, or continue in your browser.");
    } finally {
      // External app activation also normally leaves the confirmation open.
      setBusy(false);
    }
  });

  // A URL suffix can point at an HTML preview or an inline document. Keep the
  // download prompt hidden until headers confirm it, otherwise resume browsing.
  void api.runtime.sendMessage({ type: "checkDownload", url: downloadURL.href }).then(async (result) => {
    if (result?.download) {
      confirmation.hidden = false;
      continueBrowserButton.hidden = false;
    } else {
      await continueInBrowser();
    }
  }).catch(() => { void continueInBrowser(); });
})();
