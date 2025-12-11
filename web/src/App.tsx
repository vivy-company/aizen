import React, { useState, useEffect, lazy, Suspense } from "react";
import {
  Folder,
  GitBranch,
  Bot,
  Terminal,
  GitCommit,
  Mic,
  Github,
  FolderOpen,
  Globe,
} from "lucide-react";
import logo from "./logo.png";
import demoScreenshot from "./demo.png";
import terminalScreenshot from "./terminal.png";
import filesScreenshot from "./files.png";
import browserScreenshot from "./browser.png";
import { useLanguage, LanguageProvider } from "./i18n/LanguageContext";

declare global {
  interface Window {
    umami?: {
      track: (eventName: string) => void;
    };
  }
}

interface VersionInfo {
  version: string;
  downloadUrl: string;
}

interface SparkleReleaseCandidate {
  versionKey: string | null;
  displayVersion: string;
  downloadUrl: string;
  pubDate: number | null;
}

const tokenizeVersion = (version: string) =>
  version
    .split(/[\.-]/)
    .map((segment) => segment.trim())
    .filter((segment) => segment.length > 0)
    .map((segment) =>
      /^\d+$/.test(segment)
        ? { type: "number" as const, value: parseInt(segment, 10) }
        : { type: "string" as const, value: segment.toLowerCase() }
    );

const compareVersionStrings = (a: string, b: string): number => {
  const tokensA = tokenizeVersion(a);
  const tokensB = tokenizeVersion(b);
  const maxLength = Math.max(tokensA.length, tokensB.length);

  for (let index = 0; index < maxLength; index += 1) {
    const segA = tokensA[index] ?? { type: "number" as const, value: 0 };
    const segB = tokensB[index] ?? { type: "number" as const, value: 0 };

    if (segA.type === segB.type) {
      if (segA.value === segB.value) continue;
      return segA.value > segB.value ? 1 : -1;
    }

    if (segA.type === "number" && segB.type === "string") return 1;
    if (segA.type === "string" && segB.type === "number") return -1;
  }

  return 0;
};

const findLatestSparkleRelease = (xml: Document): VersionInfo | null => {
  const items = Array.from(xml.querySelectorAll("channel > item"));
  let latest: SparkleReleaseCandidate | null = null;

  for (const item of items) {
    const enclosure = item.querySelector("enclosure");
    if (!enclosure) continue;

    const downloadUrl = enclosure.getAttribute("url")?.trim();
    if (!downloadUrl) continue;

    const versionAttr = enclosure.getAttribute("sparkle:version")?.trim() ?? "";
    const shortVersion = enclosure.getAttribute("sparkle:shortVersionString")?.trim() ?? "";
    const versionKey = versionAttr || shortVersion || null;
    const displayVersion = shortVersion || versionAttr || "";
    const pubDateText = item.querySelector("pubDate")?.textContent?.trim() ?? "";
    const parsedPubDate = pubDateText ? Date.parse(pubDateText) : NaN;

    const candidate: SparkleReleaseCandidate = {
      versionKey,
      displayVersion,
      downloadUrl,
      pubDate: Number.isNaN(parsedPubDate) ? null : parsedPubDate,
    };

    if (!latest) {
      latest = candidate;
      continue;
    }

    if (candidate.versionKey && latest.versionKey) {
      const versionComparison = compareVersionStrings(candidate.versionKey, latest.versionKey);
      if (versionComparison > 0) {
        latest = candidate;
        continue;
      }
      if (versionComparison < 0) continue;
    } else if (candidate.versionKey && !latest.versionKey) {
      latest = candidate;
      continue;
    } else if (!candidate.versionKey && latest.versionKey) {
      continue;
    }

    const latestPubDate = latest.pubDate ?? -Infinity;
    const candidatePubDate = candidate.pubDate ?? -Infinity;

    if (candidatePubDate > latestPubDate) {
      latest = candidate;
    }
  }

  if (!latest) return null;

  return {
    version: latest.displayVersion,
    downloadUrl: latest.downloadUrl,
  };
};

const FAQSection = lazy(() => import("./components/FAQSection"));

type ShowcaseTab = "agents" | "terminal" | "files" | "browser";

function AppContent() {
  const { t } = useLanguage();
  const [activeTab, setActiveTab] = useState<ShowcaseTab>("agents");
  const [versionInfo, setVersionInfo] = useState<VersionInfo | null>(null);

  const trackEvent = (eventName: string) => {
    if (typeof window !== "undefined" && window.umami) {
      window.umami.track(eventName);
    }
  };

  useEffect(() => {
    fetch("https://r2.aizen.win/appcast.xml")
      .then((res) => res.text())
      .then((xmlText) => {
        const parser = new DOMParser();
        const xml = parser.parseFromString(xmlText, "text/xml");
        const latestRelease = findLatestSparkleRelease(xml);
        if (latestRelease) {
          setVersionInfo(latestRelease);
        }
      })
      .catch((err) => {
        console.error("Failed to fetch version info:", err);
      });
  }, []);

  const screenshots: Record<ShowcaseTab, string> = {
    agents: demoScreenshot,
    terminal: terminalScreenshot,
    files: filesScreenshot,
    browser: browserScreenshot,
  };

  const showcaseTabs: ShowcaseTab[] = ["agents", "terminal", "files", "browser"];

  const features = [
    { icon: Folder, bg: "rgba(0,122,255,0.1)", color: "#007aff", key: "workspaces", span: true },
    { icon: GitBranch, bg: "rgba(255,149,0,0.1)", color: "#ff9500", key: "worktrees", span: true },
    { icon: Bot, bg: "rgba(52,199,89,0.1)", color: "#34c759", key: "agents" },
    { icon: Terminal, bg: "rgba(48,209,88,0.1)", color: "#30d158", key: "terminal" },
    { icon: GitCommit, bg: "rgba(255,149,0,0.1)", color: "#ff9500", key: "git" },
    { icon: Mic, bg: "rgba(255,59,48,0.1)", color: "#ff3b30", key: "voice" },
    { icon: FolderOpen, bg: "rgba(90,200,250,0.1)", color: "#5ac8fa", key: "fileBrowser", span: true },
    { icon: Globe, bg: "rgba(175,82,222,0.1)", color: "#af52de", key: "webBrowser", span: true },
  ];

  return (
    <div className="w-full overflow-x-hidden">
      {/* Hero Section */}
      <main className="relative text-center py-20 px-6 pb-10 bg-[radial-gradient(ellipse_80%_50%_at_50%_-20%,rgba(0,113,227,0.15),transparent)] animate-[gradient-shift_15s_ease-in-out_infinite]">
        <div className="max-w-[980px] mx-auto">
          <div className="inline-flex flex-col items-center mb-8 relative">
            <img src={logo} alt="Aizen" className="w-32 h-32 drop-shadow-[0_0_40px_rgba(0,113,227,0.3)]" />
            <span className="absolute -bottom-2 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-blue-500 bg-blue-500/15 border border-blue-500/35 rounded-full">
              {t("hero.earlyAccess")}
            </span>
          </div>
          <h1 className="text-8xl font-semibold tracking-tight mb-6 leading-none">{t("hero.title")}</h1>
          <p className="text-[28px] text-[#86868b] mb-12">
            {t("hero.subtitle")}
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center items-center mb-6">
            <a
              href={versionInfo?.downloadUrl || "https://github.com/vivy-company/aizen/releases"}
              className="inline-flex items-center justify-center px-6 py-3 text-[17px] font-normal bg-blue-500 text-white rounded-full hover:bg-blue-600 transition-all duration-200"
              target="_blank"
              rel="noopener noreferrer"
              onClick={() => trackEvent("download_click")}
            >
              {t("hero.download")} {versionInfo?.version && `v${versionInfo.version}`}
            </a>
            <a
              href="https://github.com/vivy-company/aizen"
              className="inline-flex items-center gap-2 px-6 py-3 text-[17px] font-normal text-blue-500 hover:underline transition-all duration-200"
              target="_blank"
              rel="noopener noreferrer"
              onClick={() => trackEvent("github_click")}
            >
              <Github size={18} />
              {t("hero.viewOnGithub")}
            </a>
          </div>
          <p className="text-sm text-[#86868b]">
            {t("hero.requirements")}
          </p>
        </div>
      </main>

      {/* Visual Showcase */}
      <section className="py-12 px-6 pb-20">
        <div className="max-w-[1200px] mx-auto">
          <div className="flex gap-2 justify-center mb-2 flex-wrap">
            {showcaseTabs.map((tab) => (
              <button
                key={tab}
                onClick={() => { trackEvent(`showcase_tab_${tab}`); setActiveTab(tab); }}
                className={`px-4 py-2 rounded-full text-[17px] cursor-pointer transition-all duration-200 border-none ${
                  activeTab === tab
                    ? "bg-[#1d1d1f] text-[#f5f5f7]"
                    : "bg-transparent text-[#86868b] hover:text-[#f5f5f7]"
                }`}
              >
                {t(`showcase.${tab}`)}
              </button>
            ))}
          </div>
          <div className="rounded-[18px] overflow-hidden">
            <img
              src={screenshots[activeTab]}
              alt={`${activeTab} example`}
              className="w-full block"
              fetchPriority="high"
              loading="eager"
            />
          </div>
        </div>
      </section>

      {/* Features Bento Grid */}
      <section className="py-20 px-6">
        <div className="max-w-[1200px] mx-auto">
          <h2 className="text-[56px] md:text-[56px] text-[36px] font-semibold text-center mb-16 tracking-tight">{t("features.title")}</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
            {features.map((feature, i) => (
              <div
                key={i}
                className={`bg-white/[0.03] border border-white/8 rounded-3xl p-8 backdrop-blur-xl transition-all duration-300 hover:-translate-y-1.5 hover:shadow-[0_20px_40px_rgba(0,0,0,0.3)] hover:border-white/12 relative overflow-hidden group ${feature.span ? "md:col-span-2 lg:col-span-2" : ""}`}
              >
                <div className="absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(0,113,227,0.1),transparent)] opacity-0 group-hover:opacity-100 transition-opacity duration-300" />
                <div
                  className="w-12 h-12 rounded-xl flex items-center justify-center mb-4 border border-white/8"
                  style={{ background: feature.bg }}
                >
                  <feature.icon size={24} color={feature.color} />
                </div>
                <h3 className="text-2xl font-semibold mb-3 tracking-tight">{t(`features.${feature.key}.title`)}</h3>
                <p className="text-[#86868b] text-[17px] leading-[1.47059]">{t(`features.${feature.key}.desc`)}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-20 px-6">
        <div className="max-w-[720px] mx-auto">
          <h2 className="text-[56px] font-semibold text-center mb-16 tracking-tight">{t("howItWorks.title")}</h2>
          <div className="flex flex-col gap-10">
            {[
              { num: "1", key: "step1" },
              { num: "2", key: "step2" },
              { num: "3", key: "step3" },
            ].map((step) => (
              <div key={step.num} className="flex gap-6 items-start">
                <span className="text-[40px] font-bold text-blue-500 font-mono min-w-[60px]">{step.num}</span>
                <div>
                  <h3 className="text-2xl font-semibold mb-2 tracking-tight">{t(`howItWorks.${step.key}.title`)}</h3>
                  <p className="text-[#86868b] text-[17px] leading-[1.47059]">{t(`howItWorks.${step.key}.desc`)}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* FAQ */}
      <Suspense fallback={<div className="py-20 px-6"><div className="max-w-[720px] mx-auto text-center text-zinc-500">Loading...</div></div>}>
        <FAQSection />
      </Suspense>

      {/* Footer */}
      <footer className="py-12 px-6 border-t border-white/8 mt-20">
        <div className="max-w-[1200px] mx-auto flex flex-col md:flex-row justify-between items-center md:items-center gap-6">
          <p className="text-sm text-[#86868b] text-center md:text-left">{t("footer.copyright")}</p>
          <div className="flex flex-col sm:flex-row gap-4 sm:gap-6 items-center">
            <a href="https://x.com/aizenwin" className="text-sm text-zinc-500 hover:text-blue-500 transition-colors duration-200" target="_blank" rel="noopener noreferrer">
              {t("footer.twitter")}
            </a>
            <a href="https://github.com/vivy-company/aizen" className="text-sm text-zinc-500 hover:text-blue-500 transition-colors duration-200" target="_blank" rel="noopener noreferrer">
              {t("footer.github")}
            </a>
          </div>
        </div>
      </footer>
    </div>
  );
}

export function App() {
  return (
    <LanguageProvider>
      <AppContent />
    </LanguageProvider>
  );
}

export default App;
