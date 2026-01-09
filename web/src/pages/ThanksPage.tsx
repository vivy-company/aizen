import React, { useState, useEffect } from "react";
import { CheckCircle, Mail, Settings, Key, MessageCircle, Download } from "lucide-react";
import { fetchLatestVersion } from "../utils/sparkle";

export function ThanksPage() {
  const [downloadUrl, setDownloadUrl] = useState("https://github.com/vivy-company/aizen/releases/latest");

  useEffect(() => {
    fetchLatestVersion().then((info) => {
      if (info) setDownloadUrl(info.downloadUrl);
    });
  }, []);

  return (
    <div className="min-h-screen flex flex-col items-center justify-center px-6 py-20 bg-[radial-gradient(ellipse_80%_50%_at_50%_-20%,rgba(52,199,89,0.1),transparent)]">
      <div className="max-w-[700px] mx-auto">
        {/* Header */}
        <div className="text-center mb-12">
          <div className="relative inline-block mb-6">
            <img src="/logo.png" alt="Aizen" className="w-24 h-24" />
            <div className="absolute -bottom-1 -right-1 w-8 h-8 rounded-full bg-green-500 flex items-center justify-center">
              <CheckCircle size={18} className="text-white" />
            </div>
          </div>
          <h1 className="text-5xl font-semibold tracking-tight mb-4">Thank You!</h1>
          <p className="text-xl text-[#86868b]">
            Welcome to Aizen Pro. Your license is on its way.
          </p>
        </div>

        {/* Steps */}
        <div className="bg-white/[0.03] border border-white/8 rounded-3xl p-8 mb-8">
          <h2 className="text-xl font-semibold mb-6">Get started in 3 steps</h2>
          <div className="space-y-6">
            <div className="flex gap-4">
              <div className="w-10 h-10 rounded-xl bg-blue-500/20 flex items-center justify-center flex-shrink-0">
                <Mail size={20} className="text-blue-500" />
              </div>
              <div>
                <h3 className="font-medium mb-1">Check your email</h3>
                <p className="text-[#86868b] text-sm">We've sent your license key to your email. Check spam if you don't see it.</p>
              </div>
            </div>
            <div className="flex gap-4">
              <div className="w-10 h-10 rounded-xl bg-purple-500/20 flex items-center justify-center flex-shrink-0">
                <Settings size={20} className="text-purple-500" />
              </div>
              <div>
                <h3 className="font-medium mb-1">Open Aizen Settings</h3>
                <p className="text-[#86868b] text-sm">Go to <span className="text-white font-mono text-xs bg-white/10 px-1.5 py-0.5 rounded">Settings → Aizen Pro</span> in the app.</p>
              </div>
            </div>
            <div className="flex gap-4">
              <div className="w-10 h-10 rounded-xl bg-green-500/20 flex items-center justify-center flex-shrink-0">
                <Key size={20} className="text-green-500" />
              </div>
              <div>
                <h3 className="font-medium mb-1">Activate your license</h3>
                <p className="text-[#86868b] text-sm">Paste your license key and click Activate. You're all set!</p>
              </div>
            </div>
          </div>
        </div>

        {/* Actions */}
        <div className="flex gap-4 mb-8">
          <a
            href={downloadUrl}
            className="flex-1 inline-flex items-center justify-center gap-2 px-6 py-3 text-[17px] font-normal bg-blue-500 text-white rounded-full hover:bg-blue-600 transition-all duration-200"
          >
            <Download size={18} />
            Download Aizen
          </a>
          <a
            href="https://discord.gg/zemMZtrkSb"
            target="_blank"
            rel="noopener noreferrer"
            className="flex-1 inline-flex items-center justify-center gap-2 px-6 py-3 text-[17px] font-normal border border-white/20 text-white rounded-full hover:bg-white/5 transition-all duration-200"
          >
            <MessageCircle size={18} />
            Join Discord
          </a>
        </div>

        {/* Support */}
        <p className="text-center text-sm text-[#86868b]">
          Need help? Contact us at <a href="mailto:dev@aizen.win" className="text-blue-500 hover:underline">dev@aizen.win</a>
        </p>
      </div>
    </div>
  );
}
