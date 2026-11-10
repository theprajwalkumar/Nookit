import type { Metadata, Viewport } from "next";
import "./globals.css";
import { CommandPaletteProvider } from "@/components/command-palette";
import { SiteHeader } from "@/components/site-header";
import { SiteFooter } from "@/components/footer";
import { SITE } from "@/lib/site";
import { counts, product } from "@/lib/catalog";

export const metadata: Metadata = {
  metadataBase: new URL(SITE.url),
  title: {
    default: SITE.title,
    template: "%s — Nookit",
  },
  description: SITE.description,
  applicationName: "Nookit",
  keywords: [
    "Mac tools",
    "macOS utility",
    "PDF tools for Mac",
    "video converter Mac",
    "Mac notch app",
    "offline file converter",
    "one-time purchase Mac app",
  ],
  authors: [{ name: "Nookit" }],
  creator: "Nookit",
  openGraph: {
    type: "website",
    locale: "en_US",
    url: SITE.url,
    siteName: "Nookit",
    title: SITE.title,
    description: SITE.description,
    images: [{ url: "/og.png", width: 1200, height: 630, alt: "Nookit — 94 Mac tools. One notch away." }],
  },
  twitter: {
    card: "summary_large_image",
    title: SITE.title,
    description: SITE.description,
    images: ["/og.png"],
  },
  robots: { index: true, follow: true },
  alternates: { canonical: "/" },
  category: "technology",
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f7f4ed" },
    { media: "(prefers-color-scheme: dark)", color: "#0a0b0e" },
  ],
  width: "device-width",
  initialScale: 1,
};

const jsonLd = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "Organization",
      "@id": `${SITE.url}#org`,
      name: "Nookit",
      url: SITE.url,
      email: SITE.support,
    },
    {
      "@type": "SoftwareApplication",
      "@id": `${SITE.url}#app`,
      name: "Nookit",
      applicationCategory: "UtilitiesApplication",
      operatingSystem: "macOS 14 Sonoma or later",
      description: SITE.description,
      url: SITE.url,
      downloadUrl: `${SITE.url}/download`,
      softwareVersion: "0.1.0",
      offers: {
        "@type": "Offer",
        price: product.price,
        priceCurrency: "USD",
        availability: "https://schema.org/InStock",
        url: `${SITE.url}/pricing`,
      },
      featureList: [
        `${counts.tools} Mac tools across video, audio, images, documents, text, files, Mac utilities and developer utilities`,
        `${counts.notch} notch modules including clipboard, notes, tasks, timers, calendar and private AI`,
        "On-device processing with no account and no uploads",
        "One-time purchase with free updates",
      ],
      publisher: { "@id": `${SITE.url}#org` },
    },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className="min-h-screen antialiased">
        <CommandPaletteProvider>
          <a href="#main" className="skip-link">
            Skip to content
          </a>
          <SiteHeader />
          <main id="main">{children}</main>
          <SiteFooter />
        </CommandPaletteProvider>
        <script
          type="application/ld+json"
          // Structured data is static and controlled by us.
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
      </body>
    </html>
  );
}
