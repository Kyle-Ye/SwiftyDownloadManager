(() => {
  const storageKey = "sdm-language";
  const translations = {
    "Features": "功能",
    "Lock Screen": "锁屏状态",
    "Engines": "下载引擎",
    "Privacy": "隐私",
    "View on GitHub ↗": "在 GitHub 查看 ↗",
    "Download faster.": "更快下载。",
    "Resume anytime.": "随时续传。",
    "Download Latest Version": "下载最新版本",
    "Download on the App Store": "前往 App Store 下载",
    "No accounts. No analytics. No developer data collection.": "无账户、无分析，开发者不收集数据。",
    "Downloads": "下载任务",
    "3 active": "3 个进行中",
    "Complete · 126 MB": "已完成 · 126 MB",
    "Dynamic Range segmentation": "动态 Range 分段",
    "Built for the whole transfer": "为完整下载流程而生",
    "Fast by design.": "为速度而生。",
    "Ready to resume.": "随时断点续传。",
    "Split the file intelligently, keep every connection working, and resume interrupted transfers without throwing progress away.": "智能拆分文件，让每条连接持续工作，并在中断后保留进度继续下载。",
    "Use every connection": "利用每一条连接",
    "Single connection": "单连接",
    "1× baseline": "1× 基线",
    "SDM · Up to 8 connections": "SDM · 最多 8 个连接",
    "Toward available bandwidth": "尽量利用可用带宽",
    "8 Range segments": "8 个 Range 分段",
    "Rebalanced live": "动态重新分配",
    "Resume with confidence": "可靠断点续传",
    "Checkpoint saved": "检查点已保存",
    "Resume from 68%": "从 68% 继续",
    "macOS Lock Screen": "macOS 锁屏状态",
    "Source available": "源代码可获取",
    "Public repository": "公开代码仓库",
    "MIT in 2 years": "两年后转 MIT",
    "Choose your route": "选择你的下载方式",
    "Two engines.": "两种引擎。",
    "One clear choice.": "选择清晰明确。",
    "Choose multi-connection libcurl for HTTP Range acceleration and granular resume control, or URLSession for system-native background transfers.": "选择 libcurl 获得多连接 HTTP Range 加速与精细断点续传控制，或使用 URLSession 完成系统原生后台传输。",
    "Power": "高性能",
    "Native": "系统原生",
    "Optimized segmentation keeps Range connections working toward your available bandwidth.": "优化分段让多个 Range 连接持续工作，尽可能利用可用带宽。",
    "For system-native background transfers.": "使用系统原生后台传输能力。",
    "Dynamic HTTP Range segmentation": "动态 HTTP Range 分段",
    "Multiple parallel connections": "多个并行连接",
    "SQLite-backed resumable state": "基于 SQLite 的可续传状态",
    "Per-connection progress and bandwidth control": "逐连接进度与带宽控制",
    "Native background downloads": "系统原生后台下载",
    "System-managed resume": "系统管理的断点续传",
    "Apple system trust": "Apple 系统信任链",
    "Energy-aware networking": "能耗感知网络调度",
    "Built in the open.": "开放构建。",
    "Licensed FSL-1.1-MIT.": "采用 FSL-1.1-MIT 许可。",
    "Browse the source on GitHub ↗": "在 GitHub 浏览源代码 ↗",
    "Read FSL-1.1-MIT ↗": "阅读 FSL-1.1-MIT ↗",
    "Safari + Chrome": "Safari + Chrome",
    "One click.": "一次点击。",
    "SDM takes it from here.": "接下来交给 SDM。",
    "On macOS, extensions for Safari and Chrome recognize download links, eligible click-triggered downloads, and the Download with SDM context-menu action.": "在 macOS 上，Safari 与 Chrome 扩展可识别下载链接、点击触发的下载，并支持通过“使用 SDM 下载”右键菜单交给 SDM。",
    "Private means private": "隐私就该名副其实",
    "Nothing leaves.": "数据不会离开设备。",
    "Nothing to sell.": "自然也无从出售。",
    "Read the privacy statement": "阅读隐私说明",
    "Ready when you are": "随时准备就绪",
    "Give every download": "让每一次下载",
    "a better landing.": "都有更好的落点。",
    "Free to download · Source available · FSL-1.1-MIT · macOS 14+": "免费下载 · 源代码可获取 · FSL-1.1-MIT · macOS 14+",
    "Download faster. Resume anytime.": "更快下载，随时续传。",
    "Releases ↗": "发布版本 ↗",
    "Latest Release ↗": "最新版本 ↗",
    "Back home": "返回首页",
    "← Back home": "← 返回首页",
    "Privacy statement": "隐私说明",
    "Nothing leaves": "未经你的允许，",
    "without": "任何信息都不会",
    "you.": "离开设备。",
    "Effective": "生效日期",
    "August 9, 2026": "2026 年 8 月 9 日",
    "Questions": "问题反馈",
    "Privacy should be easy to verify.": "隐私承诺应该易于验证。",
    "SDM’s source and issue tracker are public on GitHub.": "SDM 的源代码与问题追踪均公开在 GitHub。",
    "Review the project on GitHub ↗": "在 GitHub 查看项目 ↗",
    "← Swifty Download Manager": "← 返回 Swifty Download Manager",
    "Local-only data handling": "仅在本地处理数据",
  };

  const originalText = new WeakMap();
  let currentLanguage = "en";

  function storedLanguage() {
    try {
      return localStorage.getItem(storageKey);
    } catch {
      return null;
    }
  }

  function storeLanguage(language) {
    try {
      localStorage.setItem(storageKey, language);
    } catch {
      // The switch still works when browser storage is unavailable.
    }
  }

  function translatedText(node, language) {
    if (!originalText.has(node)) {
      originalText.set(node, node.nodeValue ?? "");
    }

    const original = originalText.get(node);
    const match = original.match(/^(\s*)(.*?)(\s*)$/s);
    if (!match) return original;

    const [, leading, content, trailing] = match;
    const lookupText = content.replace(/\s+/g, " ").trim();
    const translated = language === "zh" ? translations[lookupText] : undefined;
    return `${leading}${translated ?? content}${trailing}`;
  }

  function translateTree(root, language) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const nodes = [];
    let node;

    while ((node = walker.nextNode())) {
      const parent = node.parentElement;
      if (!parent || parent.closest("script, style")) continue;
      nodes.push(node);
    }

    for (const textNode of nodes) {
      const nextText = translatedText(textNode, language);
      if (textNode.nodeValue !== nextText) textNode.nodeValue = nextText;
    }
  }

  function applyLanguage(language, persist = true) {
    currentLanguage = language === "zh" ? "zh" : "en";
    document.documentElement.dataset.language = currentLanguage;
    document.documentElement.lang = currentLanguage === "zh" ? "zh-Hans" : "en";

    for (const button of document.querySelectorAll("[data-language-option]")) {
      button.setAttribute(
        "aria-pressed",
        String(button.dataset.languageOption === currentLanguage),
      );
    }

    translateTree(document.body, currentLanguage);
    document.title = location.pathname.includes("privacy")
      ? currentLanguage === "zh"
        ? "隐私说明 · Swifty Download Manager"
        : "Privacy · Swifty Download Manager"
      : currentLanguage === "zh"
        ? "Swifty Download Manager — 更快下载，随时续传。"
        : "Swifty Download Manager — Download faster. Resume anytime.";

    if (persist) storeLanguage(currentLanguage);
  }

  function start() {
    const savedLanguage = storedLanguage();
    const preferredLanguage = navigator.language.toLowerCase().startsWith("zh")
      ? "zh"
      : "en";
    applyLanguage(savedLanguage ?? preferredLanguage, false);

    document.addEventListener("click", (event) => {
      const button = event.target.closest("[data-language-option]");
      if (button) applyLanguage(button.dataset.languageOption);
    });

    new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const addedNode of mutation.addedNodes) {
          if (addedNode.nodeType === Node.ELEMENT_NODE) {
            translateTree(addedNode, currentLanguage);
          }
        }
      }
    }).observe(document.body, { childList: true, subtree: true });
  }

  let started = false;

  function scheduleStart() {
    if (started) return;
    started = true;
    requestAnimationFrame(() => requestAnimationFrame(start));
  }

  function startWhenPageIsReady() {
    const root = document.documentElement;
    if (root.dataset.sdmAppReady === "true" || root.dataset.sdmStaticExport === "true") {
      scheduleStart();
      return;
    }

    const readyObserver = new MutationObserver(() => {
      if (root.dataset.sdmAppReady === "true") {
        readyObserver.disconnect();
        scheduleStart();
      }
    });
    readyObserver.observe(root, { attributes: true, attributeFilter: ["data-sdm-app-ready"] });
  }

  if (document.readyState === "complete") {
    startWhenPageIsReady();
  } else {
    window.addEventListener("load", startWhenPageIsReady, { once: true });
  }
})();
