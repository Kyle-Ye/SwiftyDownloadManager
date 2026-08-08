import type { Metadata } from "next";
import "./globals.css";
import { LanguageRuntime } from "./language-runtime";

export const metadata: Metadata = {
  metadataBase: new URL("https://kyle-ye.github.io/SwiftyDownloadManager/"),
  title: {
    default: "Swifty Download Manager — Download faster. Resume anytime.",
    template: "%s · Swifty Download Manager",
  },
  description:
    "A private, Apple-native download manager with dynamic HTTP Range segmentation, multi-connection transfers, and persistent resume.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
  openGraph: {
    type: "website",
    title: "Swifty Download Manager — Download faster. Resume anytime.",
    description:
      "Dynamic HTTP Range segmentation, parallel connections, and persistent resume for Apple platforms.",
    images: [
      {
        url: "/og.png",
        width: 1736,
        height: 909,
        alt: "Swifty Download Manager — Download faster. Resume anytime.",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Swifty Download Manager — Download faster. Resume anytime.",
    description:
      "Dynamic HTTP Range segmentation, parallel connections, and persistent resume for Apple platforms.",
    images: ["/og.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" data-language="en">
      <head>
        <script src="/theme.js" data-sdm-static="true" />
      </head>
      <body>
        {children}
        <LanguageRuntime />
        <script src="/language.js" defer data-sdm-static="true" />
      </body>
    </html>
  );
}
