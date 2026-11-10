# Nookit

**94 Mac tools. One notch away.**

Nookit is an original, all-in-one macOS toolkit: a native SwiftUI app with 94 working tools and a notch overlay, plus the Next.js marketing site that sells it. Files are processed on the Mac, results go to dated folders, and originals are never overwritten without confirmation.

This repository contains the storefront and a working native prototype. It does not contain any code, copy, screenshots or branding from other Mac utility products.

<img width="1470" height="956" alt="Screenshot 2026-11-10 at 1 02 30 PM" src="https://github.com/user-attachments/assets/c935c136-4561-417b-9547-2a4469172260" />


<img width="1470" height="956" alt="Screenshot 2026-11-10 at 1 02 42 PM" src="https://github.com/user-attachments/assets/f86624b5-9406-45c0-badf-77596ccd2d65" />


<img width="1470" height="956" alt="Screenshot 2026-11-10 at 1 02 48 PM" src="https://github.com/user-attachments/assets/96510506-c78d-4bb2-9377-75bae8c614a1" />


<img width="1470" height="956" alt="Screenshot 2026-11-10 at 1 02 56 PM" src="https://github.com/user-attachments/assets/760fa5bf-97bf-4ebf-9185-d26dcb10992a" />


<img width="1470" height="956" alt="Screenshot 2026-11-10 at 1 03 40 PM" src="https://github.com/user-attachments/assets/5e91a785-396c-4541-bd6e-8e948962448a" />


<img width="1470" height="956" alt="Screenshot 2026-11-10 at 1 03 57 PM" src="https://github.com/user-attachments/assets/0f7e01e8-802a-4716-936c-791f2b92a737" />


<img width="1470" height="956" alt="Screenshot 2026-11-10 at 1 04 20 PM" src="https://github.com/user-attachments/assets/540ac6ed-0876-4279-afd6-491644d3bff5" />



<img width="1470" height="956" alt="Screenshot 2026-11-10 at 1 05 00 PM" src="https://github.com/user-attachments/assets/4270ac77-7a50-4444-a9ae-adcd25e0d700" />












## Status at a glance

| Area | State |
| --- | --- |
| Web storefront | Complete static build, 108 routes (94 tool pages) |
| Native app | Compiles and launches; all 94 catalogue tools have real screens |
| Notch overlay | 10 of 24 modules implemented; the other 14 are labelled Roadmap in-app and on the site |
| Checkout | Env-driven links; falls back to a pre-filled email when unset |
| Notarization / DMG hosting | Not done yet — see [Distribution](#distribution-status) |
| Licensing backend | Not implemented in the native app |

Tool status by category (ready / total):

| Category | Ready |
| --- | --- |
| Video | 15 / 15 |
| Audio | 5 / 5 |
| Images | 11 / 11 |
| Docs | 22 / 22 |
| Text & Speech | 9 / 9 |
| Files | 4 / 4 |
| Mac | 16 / 16 |
| Developer | 12 / 12 |
| **All tools** | **94 / 94** |

The website reads these numbers from the shared catalogue, so adding a tool updates the storefront automatically. The notch is the one place where the catalogue is deliberately partial: 10 modules are ready and 14 remain roadmap entries.

## New in this build

- **Nookit AI** — persistent chat with image/document analysis, powered by NVIDIA models. Providers: Automatic, Apple Intelligence, Nookit AI.
- **Hype** — Food, Events and Travel with live data: Swiggy/Zomato menus, District movies and showtimes, Google Flights/Hotels and eRail trains with fares. One-way and round-trip for flights and trains; hotels support "search near my location".
- **Apps** — real Google Workspace actions after OAuth: Docs, Sheets, Slides, Gmail, Calendar, Meet and Drive.
- **Travel** — native scraped data (no embedded-browser-only results), train fares, dynamic date fields, train-specific iconography, MakeMyTrip branding removed.
- **Premium UI** — tab bar aligned with content, sliding active indicator, glassmorphism, staggered entry, hover/press states.

## Repository layout

```
.
├── shared/
│   ├── catalog.mjs          # single source of truth: product, 8 categories, 94 tools, 24 notch modules
│   ├── catalog.json         # generated copy
│   └── build-catalog.mjs    # validates + writes JSON into shared/, web/lib/, and the app bundle source
├── web/                     # Next.js 16 + React 19 + Tailwind 4 storefront
│   ├── app/                 # routes, metadata, sitemap, robots, legal pages
│   ├── components/          # header, palette, catalogue, notch demo, pricing, mockups
│   ├── lib/                 # generated catalogue, editorial content, scroll lock
│   └── public/og.png        # 1200×630 social card
└── apps/nookit/
    ├── Sources/Nookit/      # SwiftUI app, tools, notch, services
    ├── Resources/           # generated catalogue copy
    ├── build-app.sh         # direct swiftc build → build/Nookit.app
    ├── Package.swift        # retained for Xcode/SwiftPM use elsewhere
    └── BUILD_NOTES.md       # native build details and distribution checklist
```

## Requirements

- macOS 14 or later (the app targets macOS 14; some features need macOS 26)
- Node.js 20.9+ and pnpm 10+ for the website
- Command Line Tools for the native app (`xcode-select --install`); full Xcode is optional
- Swift 6.0.3 is what this build was verified with

## Run the website

```bash
cd web
pnpm install
pnpm dev
```

Open <http://localhost:3000>.

Production build:

```bash
cd web
pnpm typecheck
pnpm build
pnpm start
```

The build is fully prerendered. Deploy it as a Next.js Node app (Vercel, a container, or any Node host). If you prefer a purely static host, add `output: "export"` to `web/next.config.ts` and serve `out/`; the current project uses `next start`.

### Configuration

Copy `web/.env.example` to `web/.env.local` and fill in what you have:

```bash
NEXT_PUBLIC_CHECKOUT_1=       # hosted checkout for the 1-Mac licence
NEXT_PUBLIC_CHECKOUT_3=       # 3-Mac licence
NEXT_PUBLIC_CHECKOUT_5=       # 5-Mac licence
NEXT_PUBLIC_SITE_URL=https://nookit.app
```

`NEXT_PUBLIC_*` values are inlined at build time, so rebuild after changing them.

- With checkout links set, Buy buttons point at the hosted checkout and the pricing note says “Secure checkout”.
- Without them, Buy buttons become a pre-filled `mailto:` to `support@nookit.app`, and the note changes to “Order by email”.
- `NEXT_PUBLIC_SITE_URL` drives metadata, the sitemap and robots. The default is `https://nookit.app`.

## Edit the catalogue

Every product count on the site and in the app comes from `shared/catalog.mjs`.

```bash
# edit shared/catalog.mjs, then:
node shared/build-catalog.mjs
```

The script:

1. validates 94 tools and 24 notch modules,
2. rejects duplicate slugs and unknown categories,
3. writes `shared/catalog.json`, `web/lib/catalog.json`, and `apps/nookit/Sources/Nookit/Resources/catalog.json`.

Changing a tool's `implemented` flag changes its “Ready” badge on the site. The native app derives readiness from `ToolRegistry`, so a tool is only Ready there when a screen is registered for its slug.

## Build and run the macOS app

```bash
cd apps/nookit
./build-app.sh
open build/Nookit.app
```

No Xcode project or SwiftPM resolution is required. The script compiles every Swift source with `swiftc -parse-as-library`, assembles a normal `.app` bundle, copies the catalogue resource, rasterizes the icon, and ad-hoc signs the result.

Render every registered tool without opening a window:

```bash
NOOKIT_SMOKE=1 ./build/Nookit.app/Contents/MacOS/Nookit
# NOOKIT_SMOKE rendered=94 missing=
```

See [apps/nookit/BUILD_NOTES.md](apps/nookit/BUILD_NOTES.md) for the SwiftPM workaround, architectural notes, permissions, and the distribution checklist.

## What works today

All 94 registered tools are real screens backed by system frameworks, local processes and, for some media formats, a system FFmpeg:

- **Developer:** JSON, Base64, hashes, UUIDs, JWT, timestamps, diffs, regex, link cleaning, Unicode inspection, lorem ipsum, map coordinate picking.
- **Text & Speech:** word count, case conversion, text extraction, `say`-based speech, on-device transcription (no server fallback), summarising and document Q&A through Apple Intelligence, on-device translation, screen-region OCR.
- **Files:** QR codes, batch rename, duplicate finding, zip/unzip through `ditto`.
- **Images:** convert, resize, compress, rotate, metadata stripping, screenshot beautification, background removal, face blur, redaction, annotation and a colour picker through ImageIO and Core Graphics.
- **PDFs and documents:** merge, split, organise, extract, delete, images→PDF, PDF→images, compress, password add/remove, redaction, forms, signing, OCR, PDF→Word, Office/Web/Markdown→PDF through PDFKit, plus native XML rendering when LibreOffice is unavailable.
- **Video & audio:** download, screen record, trim, merge, mute, replace audio, change speed, resize, crop/rotate, extract frames, compress, convert, subtitles, GIF, media info, audio cleanup and conversion through AVFoundation, `screencapture`, a self-provisioned `yt-dlp`, and FFmpeg.
- **Mac:** keep awake, eject disks, battery health, storage explorer, latency/download/upload speed test, saved Wi-Fi password, uninstall, presentation mode, keyboard shield, dead-pixel test, login items, damaged-app repair, permission reset, hidden defaults, built-in and DDC display control, and scroll fixing.
- **Notch:** 10 working modules across AI, calls, work, focus and daily life; the other 14 are visible as roadmap entries.

## Honest limitations

These are deliberate boundaries, not hidden gaps:

- **The native app is a prototype, not a licensed release.** There is no licence key entry, activation server, auto-update feed, crash reporting, or telemetry.
- **Notarization and hosting are not done.** `build-app.sh` ad-hoc signs for local use. A public download requires a Developer ID certificate, `notarytool`, stapling, and a DMG/update host. The site says “notarized before release” rather than claiming a notarized build exists.
- **Checkout is not configured.** Without the env vars, orders go through email.
- **Some tools need external pieces.** Many video and audio tools call FFmpeg, and Download Video provisions the official standalone `yt-dlp` binary on the first streaming download (a Homebrew/system copy is used first). Node or Deno lets YouTube use its full-quality JavaScript extraction; without one the tool falls back to YouTube's compatible client, which may cap resolution. The app checks `/opt/homebrew/bin`, `/usr/local/bin` and `PATH` and tells you what is missing. Apple-only paths (convert, trim, mute, extract audio, recording) work without either. The network speed test measures latency plus chunked download and upload against Cloudflare, with a fallback payload. Web Page to PDF and the video downloader need a network connection.
- **External display control is hardware-dependent.** Built-in brightness uses DisplayServices. External brightness, contrast and volume use DDC/CI over the display cable, and some hubs and adapters block that channel; the tool reports this instead of pretending it worked. DDC has only been exercised against the embedded display on this build machine, so treat external-monitor control as untested until you can try it with a real monitor.
- **AI is on-device or local-network only.** AI Chat uses Apple Intelligence on macOS 26 when it is available, or any open-source model served by Ollama or an OpenAI-compatible runtime configured under Settings → AI. It never proxies prompts through a cloud service; on systems with neither, the module explains how to set one up.
- **Legal pages are templates.** They cover refunds, licensing, acceptable use, and privacy in plain language, but they are not legal advice. Have a lawyer review `web/app/privacy/page.tsx`, `web/app/terms/page.tsx`, and the pricing/refund copy before selling.

## Verification

Useful checks before shipping a change:

```bash
node shared/build-catalog.mjs
cd web && pnpm typecheck && pnpm build
cd ../apps/nookit && ./build-app.sh
NOOKIT_SMOKE=1 ./build/Nookit.app/Contents/MacOS/Nookit
```

The web QA suite used during development runs Puppeteer against a production build at 11 routes × 3 viewports and checks console errors, horizontal overflow, empty links, unlabelled buttons, the ⌘K palette, pricing tabs, FAQ disclosure, tool filters, and the mobile menu. It lives outside the repo in `/tmp/nookit-qa`; recreate it or add a checked-in Playwright suite before making QA part of CI.

## Brand and legal

Nookit is an independent product. Apple, Mac, macOS, Apple Intelligence and SF Symbols are trademarks of Apple Inc. Nookit is not affiliated with or endorsed by Apple. FFmpeg is a trademark of Fabrice Bellard. Prices are shown in USD; taxes are calculated at checkout.
