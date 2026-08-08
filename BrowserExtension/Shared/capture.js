(() => {
  const parameters = new URLSearchParams(window.location.search);
  const browser = parameters.get("browser");
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

  const callbackURL = globalThis.SDMDownloadSupport.callbackURL(
    "download",
    { url: downloadURL.href },
    browser
  );
  downloadURLLabel.textContent = downloadURL.href;
  openAppLink.href = callbackURL;
})();
