(() => {
  const storageKey = "sdm-theme";
  const root = document.documentElement;
  const colorScheme = window.matchMedia("(prefers-color-scheme: dark)");

  function storedTheme() {
    try {
      const value = localStorage.getItem(storageKey);
      return value === "light" || value === "dark" ? value : null;
    } catch {
      return null;
    }
  }

  function resolvedTheme(preference = storedTheme()) {
    return preference ?? (colorScheme.matches ? "dark" : "light");
  }

  function updateButtons(theme) {
    const dark = theme === "dark";
    const label = dark
      ? "Use light mode · 切换浅色模式"
      : "Use dark mode · 切换深色模式";

    for (const button of document.querySelectorAll("[data-theme-toggle]")) {
      button.setAttribute("aria-pressed", String(dark));
      button.setAttribute("aria-label", label);
      button.setAttribute("title", label);
    }
  }

  function applyTheme(theme, persist = false) {
    root.dataset.theme = theme;
    root.style.colorScheme = theme;
    updateButtons(theme);

    if (persist) {
      try {
        localStorage.setItem(storageKey, theme);
      } catch {
        // The switch still works when browser storage is unavailable.
      }
    }
  }

  applyTheme(resolvedTheme());

  function start() {
    updateButtons(root.dataset.theme);

    document.addEventListener("click", (event) => {
      const button = event.target.closest("[data-theme-toggle]");
      if (!button) return;

      applyTheme(root.dataset.theme === "dark" ? "light" : "dark", true);
    });

    colorScheme.addEventListener("change", () => {
      if (!storedTheme()) applyTheme(resolvedTheme());
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
