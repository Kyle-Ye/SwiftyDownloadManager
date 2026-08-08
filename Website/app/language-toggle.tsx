export function LanguageToggle() {
  return (
    <div className="language-toggle" role="group" aria-label="Language · 语言">
      <button type="button" data-language-option="en" aria-pressed="true">
        EN
      </button>
      <button type="button" data-language-option="zh" aria-pressed="false">
        中
      </button>
    </div>
  );
}
