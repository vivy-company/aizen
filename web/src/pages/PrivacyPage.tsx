import React from "react";
import logo from "../logo.png";

export function PrivacyPage() {
  return (
    <div className="min-h-screen px-6 py-20">
      <div className="max-w-[800px] mx-auto">
        <a href="/" className="inline-block mb-8">
          <img src={logo} alt="Aizen" className="w-12 h-12" />
        </a>
        <h1 className="text-4xl font-semibold tracking-tight mb-2">Privacy Policy</h1>
        <p className="text-[#86868b] mb-8">Last updated: {new Date().toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" })}</p>

        <div className="prose prose-invert max-w-none space-y-6 text-[#86868b]">
          <section>
            <h2 className="text-xl font-semibold text-white mb-3">1. Introduction</h2>
            <p>
              Vivy Technologies Co., Limited ("we", "our", or "us") operates Aizen, a macOS application for Git worktree management.
              This Privacy Policy explains how we collect, use, and protect your information.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-3">2. Information We Collect</h2>
            <h3 className="text-lg font-medium text-white mb-2">Analytics Data</h3>
            <p>
              We use Umami Analytics, a privacy-focused analytics service, to collect anonymous usage statistics on our website.
              This includes page views and general interaction data. No personal information is collected or stored.
            </p>
            <h3 className="text-lg font-medium text-white mb-2 mt-4">License Information</h3>
            <p>
              If you purchase Aizen Pro, we collect your email address and payment information through our payment processor.
              License keys are stored securely to validate your subscription.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-3">3. How We Use Your Information</h2>
            <ul className="list-disc list-inside space-y-1">
              <li>To provide and maintain our service</li>
              <li>To process transactions and send related information</li>
              <li>To send technical notices and support messages</li>
              <li>To improve our website and application</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-3">4. Data Storage and Security</h2>
            <p>
              Your data is stored securely and we implement appropriate technical measures to protect against unauthorized access.
              We do not sell or share your personal information with third parties except as necessary to provide our services.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-3">5. Your Rights</h2>
            <p>You have the right to:</p>
            <ul className="list-disc list-inside space-y-1 mt-2">
              <li>Access your personal data</li>
              <li>Correct inaccurate data</li>
              <li>Request deletion of your data</li>
              <li>Object to processing of your data</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-3">6. Contact Us</h2>
            <p>
              If you have questions about this Privacy Policy, please contact us at:{" "}
              <a href="mailto:dev@aizen.win" className="text-blue-500 hover:underline">dev@aizen.win</a>
            </p>
          </section>
        </div>

        <div className="mt-12 pt-8 border-t border-white/8">
          <a href="/" className="text-blue-500 hover:underline">← Back to Home</a>
        </div>
      </div>
    </div>
  );
}
