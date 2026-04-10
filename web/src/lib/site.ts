import en from "../i18n/translations/en.json";

export const SITE = {
  name: "Aizen",
  shortName: "Aizen",
  siteUrl: "https://aizen.win",
  title: "Aizen",
  description:
    "A macOS workspace for parallel development.",
  downloadUrl: "https://github.com/vivy-company/aizen/releases/latest",
  githubUrl: "https://github.com/vivy-company/aizen",
  discordUrl: "https://discord.gg/zemMZtrkSb",
  twitterUrl: "https://x.com/aizenwin",
  themeStorageKey: "aizen-theme",
  languageStorageKey: "aizen-language",
  stripeMonthly: "https://buy.stripe.com/dRmdR1dOI9eHfyW0LA3Ru00",
  stripeYearly: "https://buy.stripe.com/eVqfZ9bGAduXaeC9i63Ru02",
  stripeLifetime: "https://buy.stripe.com/8x23cn7qk2QjgD0gKy3Ru01",
};

export const translations = { en } as const;

export const softwareSchema = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Aizen",
  applicationCategory: "DeveloperApplication",
  operatingSystem: "macOS 13.5+",
  description:
    "An agentic-first macOS workspace for parallel development, with project environments, terminal, files, browser, workflows, and CLI.",
  url: "https://aizen.win/",
  image: "https://aizen.win/og.png",
  author: {
    "@type": "Organization",
    name: "Vivy Technologies",
  },
  softwareVersion: "1.0",
  offers: {
    "@type": "Offer",
    price: "0",
    priceCurrency: "USD",
    description: "Free download with optional Pro support",
  },
  features: [
    "Git worktree management",
    "Project environments",
    "Workspace organization",
    "Integrated terminal (libghostty)",
    "tmux-backed terminal persistence",
    "ACP agents",
    "MCP server marketplace",
    "Agent Client Protocol (ACP)",
    "Agentic-first workflow",
    "Voice input",
    "Git operations and review UI",
    "GitHub Actions and GitLab CI views",
    "CLI companion",
  ],
};

export const websiteSchema = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "WebSite",
      name: "Aizen",
      url: "https://aizen.win/",
    },
    {
      "@type": "Organization",
      name: "Vivy Technologies",
      url: "https://aizen.win/",
      logo: "https://aizen.win/logo.png",
    },
  ],
};
