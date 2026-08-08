export function ThemeToggle() {
  return (
    <button
      className="theme-toggle"
      type="button"
      data-theme-toggle
      aria-label="Use dark mode · 切换深色模式"
      aria-pressed="false"
    >
      <span className="theme-sun" aria-hidden="true"><i /></span>
      <span className="theme-moon" aria-hidden="true" />
    </button>
  );
}
