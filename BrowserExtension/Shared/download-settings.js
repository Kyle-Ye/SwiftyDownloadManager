(() => {
  const storageKey = "downloadRules";
  const support = globalThis.SDMDownloadSupport;

  function createStore(api, didChange = () => {}) {
    // Do not intercept using defaults before a saved opt-out has been loaded.
    let rules = support.normalizeDownloadRules({ candidateExtensions: [], previewExtensions: [] });
    let revision = 0;
    function apply(value) {
      rules = support.normalizeDownloadRules(value);
      didChange(rules);
    }
    api.storage.onChanged.addListener((changes, area) => {
      if (area !== "local" || !Object.hasOwn(changes, storageKey)) return;
      revision++;
      try {
        apply(changes[storageKey].newValue);
      } catch {
        apply({ candidateExtensions: [], previewExtensions: [] });
      }
    });
    const ready = api.storage.local.get(storageKey).then((values) => {
      // A slow initial read must not overwrite a newer settings-change event.
      if (revision === 0) apply(values[storageKey]);
    }).catch(() => {
      // A failed read keeps automatic handling off. A later valid storage
      // change can still enable it without restarting the extension.
    });
    return { get rules() { return rules; }, ready };
  }

  globalThis.SDMDownloadSettings = Object.freeze({ createStore, storageKey });
})();
