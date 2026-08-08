import type { Metadata } from "next";
import { LanguageToggle } from "../language-toggle";
import { ThemeToggle } from "../theme-toggle";

export const metadata: Metadata = {
  title: "Privacy",
  description:
    "Swifty Download Manager does not collect personal data, analytics, download history, or telemetry.",
};

const privacyFacts = [
  {
    mark: "01",
    en: "No personal information",
    zh: "不收集个人信息",
    detailEn: "No name, email address, account, device identifier, or contact information is requested or collected.",
    detailZh: "我们不会要求或收集姓名、邮箱、账户、设备标识符或联系方式。",
  },
  {
    mark: "02",
    en: "No analytics or telemetry",
    zh: "无分析与遥测",
    detailEn: "SDM contains no analytics SDK, advertising SDK, crash-reporting service, or behavioral tracking.",
    detailZh: "SDM 不包含分析 SDK、广告 SDK、崩溃上报服务或行为跟踪。",
  },
  {
    mark: "03",
    en: "No download data collection",
    zh: "不收集下载数据",
    detailEn: "Download URLs, filenames, progress, history, diagnostics, and settings remain on your device.",
    detailZh: "下载链接、文件名、进度、历史、诊断信息与设置只保存在你的设备上。",
  },
  {
    mark: "04",
    en: "No developer-operated server",
    zh: "无开发者服务器",
    detailEn: "The app does not send your activity to a server operated by the SDM developer.",
    detailZh: "应用不会把你的使用活动发送到由 SDM 开发者运营的服务器。",
  },
];

export default function PrivacyPage() {
  return (
    <main className="privacy-page">
      <header className="nav-wrap privacy-nav">
        <a className="brand" href="/" aria-label="Back to Swifty Download Manager home">
          <img src="/sdm-icon.png" alt="" width="42" height="42" />
          <strong>Swifty Download Manager</strong>
        </a>
        <nav aria-label="Privacy navigation">
          <a href="/">Back home</a>
          <a href="https://github.com/Kyle-Ye/SwiftyDownloadManager" target="_blank" rel="noreferrer">GitHub ↗</a>
        </nav>
        <div className="nav-actions">
          <a className="nav-cta" href="/">← Back home</a>
          <ThemeToggle />
          <LanguageToggle />
        </div>
      </header>

      <section className="privacy-hero">
        <div className="privacy-shield" aria-hidden="true">
          <span>✓</span>
        </div>
        <p className="eyebrow">Privacy statement</p>
        <h1>Nothing leaves<br />without <em>you.</em></h1>
        <p className="privacy-hero-en lang-en" lang="en">Swifty Download Manager does not collect any data.</p>
        <p className="privacy-hero-zh lang-zh" lang="zh-Hans">Swifty Download Manager 不收集任何数据。</p>
        <div className="effective-date">Effective <strong>August 8, 2026</strong></div>
      </section>

      <section className="privacy-facts" aria-label="Privacy commitments">
        {privacyFacts.map((fact) => (
          <article className="privacy-fact" key={fact.mark}>
            <span>{fact.mark}</span>
            <h2 className="lang-en" lang="en">{fact.en}</h2>
            <h3 className="lang-zh" lang="zh-Hans">{fact.zh}</h3>
            <p className="lang-en" lang="en">{fact.detailEn}</p>
            <p className="lang-zh" lang="zh-Hans">{fact.detailZh}</p>
          </article>
        ))}
      </section>

      <section className="bilingual-statement">
        <article id="english" className="privacy-language-panel lang-en" lang="en">
          <p className="language-label">English</p>
          <h2>Privacy Statement</h2>
          <h3>Data collection</h3>
          <p>
            Swifty Download Manager (SDM) does not collect, transmit, sell, or
            share personal information or usage data. The app requires no
            account and contains no analytics, advertising, tracking, or
            developer-operated crash-reporting service.
          </p>
          <h3>Information stored on your device</h3>
          <p>
            Download URLs, filenames, destinations, progress, history,
            diagnostics, engine preferences, and security-scoped bookmarks are
            stored locally in the app’s sandbox. You control this information
            through the app and the operating system.
          </p>
          <h3>Network activity</h3>
          <p>
            When you start a download, SDM connects directly to the source you
            selected so it can retrieve the file. The Safari extension processes
            eligible download links on your device and hands them to the app.
            This necessary network activity is not data collection by SDM.
          </p>
          <h3>Website privacy</h3>
          <p>
            This website does not use analytics, advertising, tracking pixels,
            cookies, or externally hosted fonts. Your language preference may
            be stored locally in your browser and is never transmitted by SDM.
            If the site is hosted by a third-party platform, that platform may
            process standard request logs under its own terms.
          </p>
          <h3>Changes</h3>
          <p>
            If SDM’s privacy practices change, this statement will be updated
            before a release containing that change is made available.
          </p>
        </article>

        <article id="chinese" className="privacy-language-panel lang-zh" lang="zh-Hans">
          <p className="language-label">简体中文</p>
          <h2>隐私说明</h2>
          <h3>数据收集</h3>
          <p>
            Swifty Download Manager（SDM）不收集、传输、出售或共享个人信息与使用数据。
            应用无需注册账户，也不包含分析、广告、行为跟踪或由开发者运营的崩溃上报服务。
          </p>
          <h3>保存在设备上的信息</h3>
          <p>
            下载链接、文件名、保存位置、进度、历史记录、诊断信息、引擎偏好和安全作用域书签，
            均保存在应用沙盒内。你可以通过应用与操作系统管理这些信息。
          </p>
          <h3>网络活动</h3>
          <p>
            当你开始下载时，SDM 会直接连接到你选择的文件来源以获取文件。Safari 扩展只在设备
            本地处理符合条件的下载链接，并将其交给应用。此类必要的网络请求不属于 SDM 的数据收集。
          </p>
          <h3>网站隐私</h3>
          <p>
            本网站不使用分析工具、广告、跟踪像素、Cookie 或外部托管字体。语言偏好可能保存在
            你的浏览器本地，SDM 不会传输该偏好。若网站托管在第三方平台，该平台可能依据其自身
            条款处理标准访问日志。
          </p>
          <h3>说明变更</h3>
          <p>
            如果 SDM 的隐私实践发生变化，我们会在包含该变化的新版本发布之前更新本说明。
          </p>
        </article>
      </section>

      <section className="privacy-contact">
        <p className="eyebrow">Questions</p>
        <h2>Privacy should be easy to verify.</h2>
        <p>SDM’s source and issue tracker are public on GitHub.</p>
        <a className="button button-primary" href="https://github.com/Kyle-Ye/SwiftyDownloadManager" target="_blank" rel="noreferrer">
          Review the project on GitHub ↗
        </a>
      </section>

      <footer className="privacy-footer">
        <a href="/">← Swifty Download Manager</a>
        <p>Zero data collection</p>
      </footer>
    </main>
  );
}
