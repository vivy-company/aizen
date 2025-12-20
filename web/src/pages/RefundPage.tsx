import React from "react";
import logo from "../logo.png";

export function RefundPage() {
  return (
    <div className="min-h-screen px-6 py-20">
      <div className="max-w-[800px] mx-auto">
        <a href="/" className="inline-block mb-8">
          <img src={logo} alt="Aizen" className="w-12 h-12" />
        </a>
        <h1 className="text-4xl font-semibold tracking-tight mb-2">Refund Policy</h1>
        <p className="text-[#86868b] mb-8">Last updated: {new Date().toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" })}</p>

        <div className="prose prose-invert max-w-none space-y-6 text-[#86868b]">
          <section>
            <h2 className="text-xl font-semibold text-white mb-3">30-Day Money-Back Guarantee</h2>
            <p>
              We want you to be completely satisfied with Aizen Pro. If you're not happy with your purchase
              for any reason, you can request a full refund within 30 days of your purchase date.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-3">How to Request a Refund</h2>
            <p>To request a refund:</p>
            <ol className="list-decimal list-inside space-y-2 mt-2">
              <li>Email us at <a href="mailto:dev@aizen.win" className="text-blue-500 hover:underline">dev@aizen.win</a></li>
              <li>Include your order number or the email used for purchase</li>
              <li>Let us know why you're requesting a refund (optional, but helps us improve)</li>
            </ol>
            <p className="mt-4">
              We'll process your refund within 5-7 business days. The refund will be credited to your original payment method.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-3">After the 30-Day Period</h2>
            <p>
              Refunds are not available after the 30-day period. However, if you experience technical issues
              that prevent you from using the software, please contact our support team and we'll do our best
              to resolve the issue.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-3">Subscription Cancellation</h2>
            <p>
              If Aizen Pro is offered as a subscription, you can cancel at any time. Upon cancellation:
            </p>
            <ul className="list-disc list-inside space-y-1 mt-2">
              <li>You'll retain access until the end of your current billing period</li>
              <li>No further charges will be made</li>
              <li>Pro features will be disabled after the period ends</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-white mb-3">Contact Us</h2>
            <p>
              Questions about our refund policy? Contact us at:{" "}
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
