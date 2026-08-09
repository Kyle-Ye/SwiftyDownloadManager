import type { Metadata } from "next";
import { LanguageToggle } from "../language-toggle";
import { ThemeToggle } from "../theme-toggle";

export const metadata: Metadata = {
  title: "Privacy",
  description:
    "How Swifty Download Manager handles download and browsing data locally without analytics, advertising, or developer-operated servers.",
};

const privacyFacts = [
  {
    mark: "01",
    en: "No developer data collection",
    zh: "开发者不收集数据",
    detailEn: "SDM does not send personal information, browsing activity, download URLs, analytics, or telemetry to the developer.",
    detailZh: "SDM 不会把个人信息、浏览活动、下载链接、分析数据或遥测信息发送给开发者。",
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
    en: "Local URL processing",
    zh: "链接仅在本地处理",
    detailEn: "The browser extensions process eligible links, page URLs, and suggested filenames on your device only to hand a download to SDM.",
    detailZh: "浏览器扩展只在设备本地处理符合条件的链接、页面地址与建议文件名，以便将下载交给 SDM。",
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
        <p className="privacy-hero-en lang-en" lang="en">Your download and browsing data stays on your device.</p>
        <p className="privacy-hero-zh lang-zh" lang="zh-Hans">你的下载与浏览数据只在设备本地处理。</p>
        <div className="effective-date">Effective <strong>August 9, 2026</strong></div>
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
            Swifty Download Manager (SDM) does not send personal information,
            browsing activity, download URLs, filenames, usage data, analytics,
            or telemetry to the developer or sell or share that information
            with third parties. The app requires no account and contains no
            advertising, tracking, or developer-operated crash-reporting service.
          </p>
          <h3>Information stored on your device</h3>
          <p>
            Download URLs, filenames, destinations, progress, history,
            diagnostics, engine preferences, and security-scoped bookmarks are
            stored locally in the app’s sandbox. You control this information
            through the app and the operating system.
          </p>
          <h3>Browser extension data handling</h3>
          <p>
            On HTTP and HTTPS pages, the Chrome and Safari extensions locally
            inspect user-initiated link targets, the current page URL, an optional
            suggested filename, and eligible direct-download navigations or
            click-triggered window openings. When you choose or initiate a
            supported download, this information is passed to the locally
            installed SDM app through its custom URL scheme. The extensions do
            not read cookies, form input, request bodies, or custom headers. A
            recent-click timestamp may be held in memory for up to 30 seconds
            to avoid intercepting unrelated window openings; it is not retained
            as activity history. The extensions do not persist browsing history
            or send this information to a developer-operated server.
          </p>
          <h3>Network activity</h3>
          <p>
            When you start a download, SDM connects directly to the source you
            selected so it can retrieve the file. The source website and your
            network provider may process that request under their own terms.
          </p>
          <h3>Chrome Web Store Limited Use</h3>
          <p>
            The Chrome extension’s use of information received from Chrome APIs
            adheres to the Chrome Web Store User Data Policy, including the
            Limited Use requirements.
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
            Swifty Download Manager（SDM）不会把个人信息、浏览活动、下载链接、文件名、
            使用数据、分析数据或遥测信息发送给开发者，也不会向第三方出售或共享这些信息。
            应用无需注册账户，也不包含广告、行为跟踪或由开发者运营的崩溃上报服务。
          </p>
          <h3>保存在设备上的信息</h3>
          <p>
            下载链接、文件名、保存位置、进度、历史记录、诊断信息、引擎偏好和安全作用域书签，
            均保存在应用沙盒内。你可以通过应用与操作系统管理这些信息。
          </p>
          <h3>浏览器扩展的数据处理</h3>
          <p>
            在 HTTP 与 HTTPS 页面中，Chrome 和 Safari 扩展会在设备本地检查由用户触发的链接目标、
            当前页面地址、可选的建议文件名，以及符合条件的直接下载导航或点击后触发的窗口打开。
            当你选择或发起受支持的下载时，这些信息会通过自定义 URL Scheme 交给本机安装的 SDM。
            扩展不会读取 Cookie、表单输入、请求正文或自定义请求头。为了避免拦截无关的窗口打开，
            扩展可能在内存中保存最近一次点击的时间戳，最长 30 秒；该信息不会作为活动历史保留。
            扩展不会保存浏览历史，也不会把这些信息发送到由开发者运营的服务器。
          </p>
          <h3>网络活动</h3>
          <p>
            当你开始下载时，SDM 会直接连接到你选择的文件来源以获取文件。文件来源网站和你的
            网络服务提供商可能依据各自条款处理该请求。
          </p>
          <h3>Chrome 应用商店有限使用要求</h3>
          <p>
            Chrome 扩展对通过 Chrome API 获得的信息的使用，遵循 Chrome 应用商店用户数据政策，
            包括其中的有限使用要求。
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
        <p>Local-only data handling</p>
      </footer>
    </main>
  );
}
