import { LanguageToggle } from "./language-toggle";
import { siteConfig } from "./site-config";
import { ThemeToggle } from "./theme-toggle";

type Feature = {
  index: string;
  title: string;
  copy: string;
  zh: string;
  visual: "range" | "speed" | "resume" | "source";
};

const features: Feature[] = [
  {
    index: "01",
    title: "Dynamic Range segmentation",
    copy: "Reassigns byte ranges dynamically to keep every connection working.",
    zh: "动态重新分配字节区间，让每条连接持续工作。",
    visual: "range",
  },
  {
    index: "02",
    title: "Use every connection",
    copy: "Fetches independent ranges in parallel to use more available bandwidth.",
    zh: "并行获取独立区间，尽可能利用可用带宽。",
    visual: "speed",
  },
  {
    index: "03",
    title: "Resume with confidence",
    copy: "Keeps progress on disk so interrupted downloads can continue.",
    zh: "将进度持久保存到磁盘，中断后可以继续下载。",
    visual: "resume",
  },
  {
    index: "04",
    title: "Source available",
    copy: "Available under FSL-1.1-MIT, transitioning to MIT after two years.",
    zh: "采用 FSL-1.1-MIT 许可，两年后转为 MIT。",
    visual: "source",
  },
];

function FeatureVisual({ type }: { type: Feature["visual"] }) {
  if (type === "range") {
    return (
      <div className="feature-visual range-visual" role="img" aria-label="A file dynamically divided into eight HTTP Range segments">
        <div className="range-segments" aria-hidden="true">
          {Array.from({ length: 8 }, (_, index) => <i key={index} />)}
        </div>
        <div className="range-nodes" aria-hidden="true">
          {Array.from({ length: 8 }, (_, index) => <i key={index} />)}
        </div>
        <div className="visual-caption">
          <span>8 Range segments</span>
          <strong>Rebalanced live</strong>
        </div>
      </div>
    );
  }

  if (type === "resume") {
    return (
      <div className="feature-visual resume-visual" role="img" aria-label="A download checkpoint saved at 68 percent and ready to resume">
        <div className="resume-status">
          <span>Checkpoint saved</span>
          <strong>68%</strong>
        </div>
        <div className="resume-track" aria-hidden="true"><i><b /></i></div>
        <div className="resume-flow">
          <span className="resume-pause" aria-hidden="true">Ⅱ</span>
          <i aria-hidden="true">→</i>
          <span className="resume-play" aria-hidden="true">▶</span>
          <strong>Resume from 68%</strong>
        </div>
      </div>
    );
  }

  if (type === "source") {
    return (
      <div className="feature-visual source-visual" role="img" aria-label="Public source repository licensed under FSL-1.1-MIT">
        <div className="source-window" aria-hidden="true">
          <div className="source-window-bar"><i /><i /><i /><span>Public repository</span></div>
          <div className="source-code-lines"><i /><i /><i /><i /></div>
        </div>
        <div className="license-chip">
          <span>FSL-1.1-MIT</span>
          <strong>MIT in 2 years</strong>
        </div>
      </div>
    );
  }

  return (
    <div className="speed-comparison feature-visual" aria-label="Illustrative single and multi-connection speed comparison">
      <div className="speed-row single-speed">
        <div className="speed-label">
          <span>Single connection</span>
          <strong>1× baseline</strong>
        </div>
        <div className="speed-track" aria-hidden="true"><i /></div>
      </div>
      <div className="speed-row multi-speed">
        <div className="speed-label">
          <span>SDM · Up to 8 connections</span>
          <strong>Toward available bandwidth</strong>
        </div>
        <div className="speed-track" aria-hidden="true"><i /></div>
      </div>
      <p className="speed-note lang-en" lang="en">
        Illustrative comparison — actual speed depends on the server, network,
        file, and HTTP Range support.
      </p>
      <p className="speed-note lang-zh" lang="zh-Hans">
        示意对比——实际速度取决于服务器、网络、文件与 HTTP Range 支持。
      </p>
    </div>
  );
}

export default function Home() {
  return (
    <main>
      <header className="nav-wrap">
        <a className="brand" href="#top" aria-label="Swifty Download Manager home">
          <img src="/sdm-icon.png" alt="" width="42" height="42" />
          <strong>Swifty Download Manager</strong>
        </a>
        <nav aria-label="Main navigation">
          <a href="#features">Features</a>
          <a href="#lock-screen">Lock Screen</a>
          <a href="#engines">Engines</a>
          <a href="/privacy/">Privacy</a>
        </nav>
        <div className="nav-actions">
          <ThemeToggle />
          <LanguageToggle />
          <a className="nav-cta" href={siteConfig.repositoryURL} target="_blank" rel="noreferrer">
            View on GitHub <span aria-hidden="true">↗</span>
          </a>
        </div>
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <h1>
            Download faster.
            <br />
            <em>Resume anytime.</em>
          </h1>
          <p className="hero-lede lang-en" lang="en">
            An Apple-native download manager with optimized HTTP Range
            segmentation, parallel connections, and persistent resume.
          </p>
          <p className="hero-zh lang-zh" lang="zh-Hans">原生 Apple 平台下载工具，支持动态 HTTP Range 分段、多连接并行与可靠断点续传。</p>
          <div className="hero-actions">
            <a className="button button-primary" href={siteConfig.downloads.github.href} target="_blank" rel="noreferrer">
              <span className="button-icon" aria-hidden="true" />
              {siteConfig.downloads.github.label}
            </a>
            {siteConfig.downloads.appStore.enabled && siteConfig.downloads.appStore.href ? (
              <a className="button button-store" href={siteConfig.downloads.appStore.href} target="_blank" rel="noreferrer">
                {siteConfig.downloads.appStore.label}
              </a>
            ) : null}
          </div>
          <div className="privacy-note">
            <span className="privacy-mark" aria-hidden="true">✓</span>
            No accounts. No analytics. No developer data collection.
          </div>
        </div>

        <div className="hero-stage" aria-label="Illustration of the SDM download interface">
          <div className="app-window">
            <div className="window-bar">
              <span className="window-dots"><i /><i /><i /></span>
              <span className="window-title">Swifty Download Manager</span>
              <span className="window-add">＋</span>
            </div>
            <div className="window-body">
              <div className="mini-sidebar">
                <img src="/sdm-icon.png" alt="" width="52" height="52" />
                <span className="side-line active" />
                <span className="side-line" />
                <span className="side-line short" />
              </div>
              <div className="download-list">
                <div className="list-heading">
                  <span>Downloads</span>
                  <small>3 active</small>
                </div>
                <div className="download-row featured-row">
                  <div className="file-glyph coral">ZIP</div>
                  <div className="file-meta">
                    <strong>Design-assets.zip</strong>
                    <div className="progress-track"><span style={{ width: "82%" }} /></div>
                    <small>82% · 48.2 MB/s</small>
                  </div>
                  <div className="pause-icon">Ⅱ</div>
                </div>
                <div className="connection-stack" aria-hidden="true">
                  <span style={{ width: "100%" }} />
                  <span style={{ width: "93%" }} />
                  <span style={{ width: "75%" }} />
                  <span style={{ width: "64%" }} />
                </div>
                <div className="download-row">
                  <div className="file-glyph blue">DMG</div>
                  <div className="file-meta">
                    <strong>Studio-build.dmg</strong>
                    <div className="progress-track"><span style={{ width: "56%" }} /></div>
                    <small>56% · 12.7 MB/s</small>
                  </div>
                </div>
                <div className="download-row complete-row">
                  <div className="file-glyph mint">✓</div>
                  <div className="file-meta">
                    <strong>Field-notes.pdf</strong>
                    <small>Complete · 126 MB</small>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section className="section features-section" id="features">
        <div className="section-heading">
          <p className="eyebrow">Built for the whole transfer</p>
          <h2>Fast by design.<br />Ready to resume.</h2>
          <p>
            Split the file intelligently, keep every connection working, and
            resume interrupted transfers without throwing progress away.
          </p>
        </div>
        <div className="feature-grid">
          {features.map((feature) => (
            <article className="feature-card has-feature-visual" key={feature.index}>
              <div className="feature-copy">
                <span className="feature-index">{feature.index}</span>
                <h3>{feature.title}</h3>
                <p className="lang-en" lang="en">{feature.copy}</p>
                <small className="lang-zh" lang="zh-Hans">{feature.zh}</small>
              </div>
              <FeatureVisual type={feature.visual} />
            </article>
          ))}
        </div>
      </section>

      <section className="lock-screen-section" id="lock-screen">
        <div className="lock-screen-intro">
          <div>
            <p className="eyebrow">macOS Lock Screen</p>
            <h2 className="lang-en" lang="en">
              Keep an eye on every download.
              <br />
              <em>Even while your Mac is locked.</em>
            </h2>
            <h2 className="lang-zh" lang="zh-Hans">
              下载状态，<br className="lock-screen-mobile-break" />抬眼可见。
              <br />
              <em>锁屏时也一样。</em>
            </h2>
          </div>
          <div className="lock-screen-copy">
            <p className="lang-en" lang="en">
              See recent downloads, live progress, transfer speed, time
              remaining, and task status without unlocking your Mac.
            </p>
            <p className="lang-zh" lang="zh-Hans">
              无需解锁 Mac，即可查看最近下载、实时进度、传输速度、剩余时间与任务状态。
            </p>
            <div className="lock-screen-setting">
              <span className="setting-switch" aria-hidden="true"><i /></span>
              <span>
                <strong className="lang-en" lang="en">Enable it in Settings</strong>
                <strong className="lang-zh" lang="zh-Hans">可在设置中开启</strong>
                <small className="lang-en" lang="en">Off by default</small>
                <small className="lang-zh" lang="zh-Hans">默认关闭</small>
              </span>
            </div>
          </div>
        </div>
        <figure className="lock-screen-visual">
          <img
            className="lang-en"
            src="/lock-screen-status-en.jpg"
            alt="A Mac Lock Screen showing five recent downloads in Swifty Download Manager"
            width="1555"
            height="1011"
            loading="lazy"
            decoding="async"
          />
          <img
            className="lang-zh"
            src="/lock-screen-status-zh.jpg"
            alt="Mac 锁屏界面上显示 Swifty Download Manager 最近五条下载任务"
            width="1555"
            height="1011"
            loading="lazy"
            decoding="async"
          />
          <figcaption>
            <span className="lang-en" lang="en">Product visualization based on SDM&apos;s actual Lock Screen interface.</span>
            <span className="lang-zh" lang="zh-Hans">产品示意图，界面基于 SDM 实际锁屏状态视图。</span>
          </figcaption>
        </figure>
      </section>

      <section className="engine-section" id="engines">
        <div className="engine-intro">
          <p className="eyebrow light">Choose your route</p>
          <h2>Two engines.<br /><em>One clear choice.</em></h2>
          <p>
            Choose multi-connection libcurl for HTTP Range acceleration and
            granular resume control, or URLSession for system-native background
            transfers.
          </p>
        </div>
        <div className="engine-cards">
          <article className="engine-card curl-card">
            <div className="engine-card-top">
              <span className="engine-badge">Power</span>
              <span className="engine-symbol">×8</span>
            </div>
            <h3>libcurl</h3>
            <p>Optimized segmentation keeps Range connections working toward your available bandwidth.</p>
            <ul>
              <li>Dynamic HTTP Range segmentation</li>
              <li>Multiple parallel connections</li>
              <li>SQLite-backed resumable state</li>
              <li>Per-connection progress and bandwidth control</li>
            </ul>
          </article>
          <article className="engine-card session-card">
            <div className="engine-card-top">
              <span className="engine-badge">Native</span>
              <span className="engine-symbol cloud-symbol">☁</span>
            </div>
            <h3>URLSession</h3>
            <p>For system-native background transfers.</p>
            <ul>
              <li>Native background downloads</li>
              <li>System-managed resume</li>
              <li>Apple system trust</li>
              <li>Energy-aware networking</li>
            </ul>
          </article>
        </div>
      </section>

      <section className="source-banner" id="source">
        <div className="source-mark" aria-hidden="true"><span>{"{ }"}</span></div>
        <div>
          <p className="eyebrow">Source available</p>
          <h2>Built in the open.<br />Licensed FSL-1.1-MIT.</h2>
        </div>
        <div className="source-banner-copy">
          <p className="lang-en" lang="en">
            The code is available to read, study, modify, and redistribute for
            permitted purposes. Each released version automatically becomes
            available under MIT after two years.
          </p>
          <p className="lang-zh" lang="zh-Hans">
            源代码公开可获取，可在许可范围内阅读、研究、修改与分发；每个发布版本两年后自动以 MIT 许可证提供。
          </p>
          <div className="source-links">
            <a href={siteConfig.repositoryURL} target="_blank" rel="noreferrer">Browse the source on GitHub <span>↗</span></a>
            <a href={siteConfig.licenseURL} target="_blank" rel="noreferrer">Read FSL-1.1-MIT <span>↗</span></a>
          </div>
        </div>
      </section>

      <section className="safari-section">
        <div className="safari-visual" aria-hidden="true">
          <div className="browser-frame">
            <div className="browser-top"><i /><i /><i /><span>Safari · Chrome</span></div>
            <div className="browser-content">
              <span className="fake-heading" />
              <span className="fake-copy" />
              <span className="fake-copy short" />
              <div className="fake-download">Download project.zip <b>↓</b></div>
            </div>
          </div>
          <div className="handoff-arrow">→</div>
          <img src="/sdm-icon.png" alt="" width="104" height="104" />
        </div>
        <div className="safari-copy">
          <p className="eyebrow">Safari + Chrome</p>
          <h2>One click.<br />SDM takes it from here.</h2>
          <p>
            On macOS, extensions for Safari and Chrome recognize download links,
            eligible click-triggered downloads, and the Download with SDM
            context-menu action.
          </p>
        </div>
      </section>

      <section className="privacy-banner">
        <div className="privacy-banner-mark" aria-hidden="true"><span>✓</span></div>
        <div>
          <p className="eyebrow">Private means private</p>
          <h2>Nothing leaves.<br />Nothing to sell.</h2>
        </div>
        <div className="privacy-banner-copy">
          <p className="lang-en" lang="en">
            SDM has no account system, analytics SDK, advertising, or telemetry.
            Your download history and settings stay on your device.
          </p>
          <p className="privacy-banner-zh lang-zh" lang="zh-Hans">SDM 不会把浏览或下载数据发送给开发者；下载记录与设置只保存在你的设备上。</p>
          <a href="/privacy/">Read the privacy statement <span>→</span></a>
        </div>
      </section>

      <section className="final-cta">
        <img src="/sdm-icon.png" alt="Swifty Download Manager icon" width="112" height="112" />
        <p className="eyebrow">Ready when you are</p>
        <h2>Give every download<br />a better landing.</h2>
        <p>Free to download · Source available · FSL-1.1-MIT · macOS 14+</p>
        <div className="download-actions">
          <a className="button button-primary" href={siteConfig.downloads.github.href} target="_blank" rel="noreferrer">
            {siteConfig.downloads.github.label} <span aria-hidden="true">↓</span>
          </a>
          {siteConfig.downloads.appStore.enabled && siteConfig.downloads.appStore.href ? (
            <a className="button button-store" href={siteConfig.downloads.appStore.href} target="_blank" rel="noreferrer">
              {siteConfig.downloads.appStore.label}
            </a>
          ) : null}
        </div>
      </section>

      <footer>
        <div className="footer-brand">
          <img src="/sdm-icon.png" alt="" width="38" height="38" />
          <span><strong>Swifty Download Manager</strong><small>Download faster. Resume anytime.</small></span>
        </div>
        <div className="footer-links">
          <a href={siteConfig.repositoryURL} target="_blank" rel="noreferrer">GitHub ↗</a>
          <a href={siteConfig.licenseURL} target="_blank" rel="noreferrer">FSL-1.1-MIT ↗</a>
          <a href={siteConfig.downloads.github.href} target="_blank" rel="noreferrer">Latest Release ↗</a>
          <a href="/privacy/">Privacy</a>
        </div>
        <p className="copyright">@ 2026 Kyle-Ye</p>
      </footer>
    </main>
  );
}
