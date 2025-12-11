import React from "react";
import { useLanguage } from "../i18n/LanguageContext";

export default function FAQSection() {
  const { t } = useLanguage();

  const highlightTerms = (text: string): string => {
    return text
      .replace(/Claude/g, '<span class="text-[#da7756]">Claude</span>')
      .replace(/Codex/g, '<span class="text-[#10a37f]">Codex</span>')
      .replace(/Gemini/g, '<span class="text-[#4285f4]">Gemini</span>')
      .replace(/Kimi/g, '<span class="text-[#ff6b6b]">Kimi</span>')
      .replace(/VS Code/g, '<span class="text-[#007acc]">VS Code</span>')
      .replace(/Agent Client Protocol \(ACP\)/g, '<span class="text-[#89dceb]">Agent Client Protocol</span> (<code class="text-[#89dceb] font-mono text-[15px]">ACP</code>)')
      .replace(/ACP/g, '<code class="text-[#89dceb] font-mono text-[15px]">ACP</code>')
      .replace(/NPM/g, '<code class="text-[#89dceb] font-mono text-[15px]">NPM</code>')
      .replace(/GitHub/g, '<span class="text-zinc-300">GitHub</span>')
      .replace(/Apache 2\.0/g, '<span class="text-zinc-300">Apache 2.0</span>')
      .replace(/macOS 13\.5 Ventura/g, '<span class="text-blue-500">macOS 13.5 Ventura</span>')
      .replace(/Apple Silicon/g, '<span class="text-zinc-400">Apple Silicon</span>')
      .replace(/Intel Macs/g, '<span class="text-zinc-400">Intel Macs</span>');
  };

  return (
    <section className="py-20 px-6">
      <div className="max-w-[720px] mx-auto">
        <h2 className="text-[56px] font-semibold text-center mb-16 tracking-tight">{t("faq.title")}</h2>
        <div className="flex flex-col gap-8">
          {["q1", "q2", "q3", "q4", "q5", "q6"].map((qKey) => {
            const answer = t(`faq.${qKey}.answer`);

            return (
              <div key={qKey}>
                <h3 className="text-[21px] font-semibold mb-3 tracking-tight">{t(`faq.${qKey}.question`)}</h3>
                <p className="text-[#86868b] text-[17px] leading-[1.47059]">
                  <span dangerouslySetInnerHTML={{ __html: highlightTerms(answer) }} />
                </p>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
