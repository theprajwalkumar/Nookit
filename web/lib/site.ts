import { product } from "./catalog";

export const SITE = {
  name: product.name,
  url: process.env.NEXT_PUBLIC_SITE_URL || "https://nookit.app",
  title: "Nookit — 94 Mac tools. One notch away.",
  description:
    "A private, one-time-purchase toolkit for the Mac: video, audio, images, PDFs, text, files, developer utilities and a notch that shows your day. On-device by default.",
  support: product.support,
};

export const NAV = [
  { label: "What's inside", href: "/#inside" },
  { label: "Tools", href: "/tools" },
  { label: "Notch", href: "/notch" },
  { label: "Pricing", href: "/pricing" },
  { label: "FAQ", href: "/#faq" },
];

export const LAUNCH_ENDS = Date.parse("2026-11-30T23:59:59Z");

export interface Tier {
  id: "one" | "three" | "five";
  macs: number;
  price: number;
  compareAt: number;
  label: string;
  note: string;
  best?: boolean;
}

export const TIERS: Tier[] = [
  {
    id: "one",
    macs: 1,
    price: 19,
    compareAt: 49.99,
    label: "1 Mac",
    note: "The everyday licence.",
  },
  {
    id: "three",
    macs: 3,
    price: 29,
    compareAt: 79.99,
    label: "3 Macs",
    note: "Laptop, desktop and the spare.",
    best: true,
  },
  {
    id: "five",
    macs: 5,
    price: 39,
    compareAt: 119.99,
    label: "5 Macs",
    note: "The whole household.",
  },
];

const CHECKOUT_LINKS = {
  one: process.env.NEXT_PUBLIC_CHECKOUT_1,
  three: process.env.NEXT_PUBLIC_CHECKOUT_3,
  five: process.env.NEXT_PUBLIC_CHECKOUT_5,
} as const;

/** True when at least one hosted checkout link is configured at build time. */
export function checkoutIsConfigured(): boolean {
  return Boolean(
    CHECKOUT_LINKS.one || CHECKOUT_LINKS.three || CHECKOUT_LINKS.five,
  );
}

export function checkoutUrl(tier: Tier["id"]): string {
  const tierData = TIERS.find((t) => t.id === tier)!;
  return (
    CHECKOUT_LINKS[tier] ??
    `mailto:${SITE.support}?subject=${encodeURIComponent(
      `Buy Nookit — ${tierData.label}`,
    )}&body=${encodeURIComponent(
      "I would like to buy Nookit. Please send a checkout link.\n\nLicence: " +
        tierData.label,
    )}`
  );
}

export const FAQ = [
  {
    q: "Does anything leave my Mac?",
    a: "No file you open with a tool is uploaded. Compression, transcription, image work, PDFs and every Mac utility run locally. Network access happens only when you use a network feature: the video downloader (the site you paste, plus the official yt-dlp engine on first use), the speed test (Cloudflare's endpoints), Web Page to PDF (the page you paste), the Coordinate Picker (Apple map tiles and place search), a local AI model server you configure (such as Ollama), and licence activation plus a quiet weekly check that sends only your licence key and an anonymous activation ID. AI prompts stay on your Mac or local network. There is no analytics SDK, no account and no telemetry.",
  },
  {
    q: "What is ready today, and what is still coming?",
    a: "All 94 tools in the catalogue are ready in this build, each with its own screen. The notch is the one place where the catalogue is deliberately partial: 10 of its 24 modules are ready, and the other 14 are visible as roadmap entries included in your purchase. There is no upgrade tier, no credit pack and no second payment. We would rather show you the honest status than pretend a module shipped.",
  },
  {
    q: "Which Macs does it run on?",
    a: "macOS 14 Sonoma or later, on Apple silicon and Intel. AI Chat uses Apple Intelligence on macOS 26 when it is enabled, or any open-source model through Ollama or an OpenAI-compatible local server on older systems; the rest of the app works without either. The notch overlay draws its own notch on Macs that do not have one.",
  },
  {
    q: "Is it a subscription?",
    a: "No. One payment for the licence you choose. Updates are free for the life of the product. You are not renting a tool that runs on your own computer.",
  },
  {
    q: "How many Macs can I use it on?",
    a: "One, three or five depending on the licence you buy. The release build will let you move a licence to a new Mac by deactivating the old one, and we do not plan to count a machine twice after a repair.",
  },
  {
    q: "Do the video tools need FFmpeg?",
    a: "Some do. Convert, trim, mute and extract audio use Apple's AVFoundation encoders and need nothing extra. Download, screen recording, subtitles, GIF, speed change, frame extraction and most of the edit tools can use a system FFmpeg; the app checks the usual Homebrew paths and shows you the exact `brew install ffmpeg` command if it is missing. On the first streaming download, Download Video fetches the official standalone `yt-dlp` binary into Application Support so YouTube links work without Homebrew; a copy you already installed is used first. Direct media links work with the system HTTP client.",
  },
  {
    q: "Where do my results go?",
    a: "Every run gets its own dated folder inside a Nookit folder in Downloads. You can point Nookit at a different folder in Settings. Originals are never overwritten or moved unless you explicitly choose a destructive action and confirm it.",
  },
  {
    q: "How do I activate a licence?",
    a: "At launch, your key arrives by email with the receipt. Paste it into Nookit, or use the one-click activation link on the page after checkout. Activation will work offline after the first check.",
  },
  {
    q: "What if it is not right for me?",
    a: "Ask for a refund within 14 days of purchase and we will process it, no interrogation. If a tool is broken, tell us and we will try to fix it first.",
  },
  {
    q: "Can I buy for a team?",
    a: "Yes. Licences of 10 Macs or more, purchase orders and invoices are available. Email support@nookit.app with the number of machines and we will send a quote.",
  },
  {
    q: "What permissions does it ask for?",
    a: "Only the ones a tool you opened needs, and it explains why before macOS shows its own prompt: Microphone for recording, Speech Recognition for transcription, Calendar for the notch countdown, Automation for the notch music player, and Screen Recording for Record Screen and Capture Text. Everything is optional and revocable in System Settings.",
  },
  {
    q: "Is the price the same everywhere?",
    a: "The price is set in US dollars. Checkout shows the final amount in your local currency including any tax that applies. Regional purchasing-power pricing is applied at checkout where we can.",
  },
];

export const NOTCH_FAQ = [
  {
    q: "Does the notch work on a Mac without a notch?",
    a: "Yes. Nookit draws its own small pill at the top centre of the screen. The modules, shortcuts and behaviour are identical.",
  },
  {
    q: "Does it get in the way of the menu bar?",
    a: "It sits at the top centre, in the notch area, and collapses to almost nothing. It only expands when you hover or click, and it never covers the menu bar items on either side.",
  },
  {
    q: "Does it show up in screen recordings?",
    a: "No. The notch is a non-activating panel excluded from screen capture, so notes and clipboard stay out of a share. The teleprompter and revenue modules on the roadmap will use the same behaviour. You can also switch the notch off from the menu bar or Settings.",
  },
  {
    q: "Does it drain the battery?",
    a: "Collapsed, there is no animation loop and no GPU work. Lightweight timers refresh the clipboard, calendar, music and water status, and none of them touch the network. Network access only happens in the tools that need it.",
  },
  {
    q: "Where do notes, clipboard and tasks live?",
    a: "On your Mac, not on a server. Notes are Markdown files and tasks are a JSON file inside Application Support; clipboard history is kept in the app's own preferences and can be cleared from the notch. Nothing is synced to us.",
  },
  {
    q: "Can I choose which modules appear?",
    a: "Yes. Turn any of the 10 working modules on or off in Settings. The other 14 are roadmap entries and will join the same row as they ship. Each visible module has a number key while the panel is open.",
  },
];

export const PERMISSIONS = [
  {
    icon: "mic",
    name: "Microphone",
    why: "Only while recording audio. The recording is written locally and never leaves the machine.",
  },
  {
    icon: "wave",
    name: "Speech Recognition",
    why: "For on-device transcription. Audio is processed by Apple's local speech model, not uploaded; if the model is missing, the tool stops.",
  },
  {
    icon: "calendar",
    name: "Calendar",
    why: "To show the next meeting in the notch. Nookit reads upcoming events; it never creates or edits them.",
  },
  {
    icon: "display",
    name: "Screen Recording",
    why: "Used by Record Screen and Capture Text to read a window, screen or selection. The image is processed locally and discarded; nothing is recorded in the background.",
  },
  {
    icon: "music",
    name: "Automation",
    why: "Only when you use the notch player, so Nookit can read and control Music or Spotify. macOS asks the first time.",
  },
  {
    icon: "folder",
    name: "Downloads",
    why: "To save results into a new dated folder. Nookit does not read or change the other files in your Downloads.",
  },
];

export const COMPARISON = [
  {
    job: "Video conversion and trimming",
    elsewhere: "$10–$30 each",
    nookit: ["Convert Video", "Trim Video", "Mute Video"],
  },
  {
    job: "PDF toolkit",
    elsewhere: "Usually a subscription",
    nookit: ["Merge PDFs", "Split PDF", "PDF to Images"],
  },
  {
    job: "Transcription app",
    elsewhere: "Usually a subscription",
    nookit: ["Transcribe"],
  },
  {
    job: "File renaming and archives",
    elsewhere: "$10–$30 each",
    nookit: ["Batch Rename", "Zip & Unzip"],
  },
  {
    job: "Image batch work",
    elsewhere: "$10–$40 each",
    nookit: ["Convert Images", "Resize Images", "Compress Images"],
  },
  {
    job: "Keep-awake utility",
    elsewhere: "Free to $10",
    nookit: ["Keep Awake"],
  },
  {
    job: "Notch utility",
    elsewhere: "$15–$20, sometimes a subscription",
    nookit: ["Notch overlay (10 modules ready)"],
  },
  {
    job: "Battery and network utilities",
    elsewhere: "Free to $15 each",
    nookit: ["Battery Health", "Network Speed Test"],
  },
];

export const CHANGELOG = [
  {
    version: "0.1.0",
    date: "2 November 2026",
    title: "First pre-release build",
    items: [
      "The dashboard, search and all 94 tool entries, each with a working screen.",
      "The notch overlay with 10 working modules: clipboard, notes, tasks, timer, calendar, music, hydration, breathing, habits and a private AI assistant.",
      "Video, audio, image, document, text, file, Mac and developer tool screens, with FFmpeg and LibreOffice fallbacks where the system frameworks stop.",
      "Result folders, progress reporting and a plain-English error surface.",
    ],
  },
  {
    version: "0.2.0",
    date: "Planned",
    title: "Notch, distribution and polish",
    items: [
      "The remaining 14 notch modules, including dictation, snippets, teleprompter and the analytics modules.",
      "Timestamped and SRT transcript export.",
      "A signed, notarized DMG and a licence activation flow.",
      "Quick launcher polish and broader keyboard coverage.",
    ],
  },
];
