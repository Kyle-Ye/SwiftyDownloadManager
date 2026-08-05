(() => {
  const callbackScheme = "swifty-download-manager";
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

  const callbackURL = new URL(`${callbackScheme}://download`);
  callbackURL.searchParams.set("url", downloadURL.href);
  downloadURLLabel.textContent = downloadURL.href;
  openAppLink.href = callbackURL.href;
})();
