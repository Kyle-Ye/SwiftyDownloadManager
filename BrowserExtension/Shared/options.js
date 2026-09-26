(() => {
  const api = globalThis.browser ?? globalThis.chrome;
  const support = globalThis.SDMDownloadSupport;
  const settings = globalThis.SDMDownloadSettings;
  const form = document.getElementById("settings-form");
  const fields = document.getElementById("settings-fields");
  const candidates = document.getElementById("candidate-extensions");
  const previews = document.getElementById("preview-extensions");
  const status = document.getElementById("status");
  const error = document.getElementById("error");
  let busy = true;

  function showRules(rules) {
    candidates.value = rules.candidateExtensions.join(", ");
    previews.value = rules.previewExtensions.join(", ");
  }

  async function save(rules) {
    busy = true;
    fields.disabled = true;
    error.hidden = true;
    status.textContent = "Saving…";
    try {
      await api.storage.local.set({ [settings.storageKey]: rules });
      showRules(rules);
      status.textContent = "Saved. Changes apply to open pages and new tabs.";
    } catch {
      status.textContent = "";
      error.textContent = "Could not save settings. Please try again.";
      error.hidden = false;
    } finally {
      busy = false;
      fields.disabled = false;
    }
  }

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    if (busy) return;
    try {
      return save(support.normalizeDownloadRules({
        candidateExtensions: candidates.value,
        previewExtensions: previews.value,
      }));
    } catch (failure) {
      status.textContent = "";
      error.textContent = failure.message;
      error.hidden = false;
    }
  });
  document.getElementById("restore").addEventListener("click", () => {
    if (!busy) return save(support.normalizeDownloadRules(support.defaultDownloadRules));
  });

  void api.storage.local.get(settings.storageKey).then((values) => {
    showRules(support.normalizeDownloadRules(values[settings.storageKey]));
    status.textContent = "";
    busy = false;
    fields.disabled = false;
  }).catch(() => {
    status.textContent = "";
    error.textContent = "Could not load settings. Reload this page to try again.";
    error.hidden = false;
  });
})();
