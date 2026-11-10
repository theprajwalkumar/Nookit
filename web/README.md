# Nookit website

Next.js 16.4.4 storefront for Nookit. Static-rendered, no CMS, no analytics, no client-side data fetching. Product facts come from `../shared/catalog.mjs` via a generated JSON copy.

## Run

```bash
pnpm install
pnpm dev          # http://localhost:3000
pnpm typecheck
pnpm build        # 108 prerendered routes
pnpm start
```

Node 20.9+ is required by Next 16. The project uses the App Router, React 19, Tailwind 4, and TypeScript in strict mode.

## Routes

| Route | Purpose |
| --- | --- |
| `/` | Hero, app mockup, notch demo, catalogue preview, privacy, pricing, FAQ |
| `/tools` | Filterable/searchable catalogue of all 94 tools |
| `/tools/[slug]` | 94 generated detail pages with status, use cases, steps and related tools |
| `/notch` | 24 notch modules, grouped, with live Ready/Roadmap badges |
| `/pricing` | Licence switcher, included list, comparisons, buying FAQ |
| `/download` | Setup steps, requirements, permissions, troubleshooting |
| `/changelog` | Shipped and planned entries |
| `/privacy`, `/terms` | Plain-language policy templates — legal review required |
| `/success` | Post-checkout instructions; excluded from indexing |
| `/sitemap.xml`, `/robots.txt` | Generated from `NEXT_PUBLIC_SITE_URL` |
| `/_not-found` | Branded 404 with search trigger |

## Configuration

Copy `.env.example` to `.env.local`:

```bash
NEXT_PUBLIC_CHECKOUT_1=
NEXT_PUBLIC_CHECKOUT_3=
NEXT_PUBLIC_CHECKOUT_5=
NEXT_PUBLIC_SITE_URL=https://nookit.app
```

- Checkout values are inlined at build time. Missing links fall back to a `mailto:` order email; the pricing card switches its checkout note accordingly.
- `NEXT_PUBLIC_SITE_URL` is used by `metadataBase`, canonical URLs, JSON-LD, the sitemap and robots.
- There are no server secrets. The site has no API routes, database, newsletter form, or account system.

## Catalogue and counts

Never hardcode a count in a component. Import from `lib/catalog.ts`:

```ts
import { counts, tools, readyTools } from "@/lib/catalog";
counts.tools;              // 94
counts.implementedTools;   // 94
counts.notch;              // 24
counts.byCategory;         // { video: 15, ... }
```

To change the catalogue, edit `../shared/catalog.mjs`, then run:

```bash
pnpm catalog      # or: node ../shared/build-catalog.mjs
```

That regenerates `lib/catalog.json` and the app's copy. Tool detail pages are generated from `generateStaticParams`, so new slugs appear at build time without touching the route file.

A few branded strings (page titles, social copy) intentionally say “94” as part of the product promise. If the catalogue size changes, update those strings too.

## Design system

Tokens live in `app/globals.css` under `@theme`:

- paper `#F7F4ED`, ink `#0A0B0E`, ember `#FF5A1F`, mint `#6FE3B6`
- system sans for UI, New York serif for accents, SF Mono for data
- shared radii, shadows, dot grids, grain, and `.wrap` / `.eyebrow` utilities

Primary components:

- `site-header.tsx` — sticky nav, countdown, mobile menu with Escape-to-close
- `command-palette.tsx` — one global palette provider; header, homepage and 404 all open the same dialog. ⌘K listener, focus on mount, Tab trap, focus return, reference-counted scroll lock. Do not mount a second provider.
- `tool-catalog.tsx` — catalogue search, category filters and status chips
- `pricing-cards.tsx` — 1/3/5-Mac switcher, launch-price logic that hides the discount after `LAUNCH_ENDS`
- `notch-demo.tsx`, `app-mockup.tsx` — DOM-only product mockups (no screenshots)
- `reveal.tsx` — IntersectionObserver entrance animation, disabled for reduced motion

`lib/site.ts` holds editorial copy: tiers, FAQ, notch FAQ, permissions, comparison rows, changelog, and checkout helpers. Keep claims there aligned with what the native build actually does.

## Social card

`public/og.png` is a checked-in 2400×1260 PNG (1200×630 at 2×), referenced by the Open Graph and Twitter metadata in `app/layout.tsx`. Replace it with a new 1200×630 image if branding changes; keep the path and dimensions in sync.

## Deploy

The build is prerendered but uses the Next.js server output (`next start`). Deploy to Vercel or any Node host that can run `pnpm build && pnpm start`.

If you need a pure static host, add this to `next.config.ts`:

```ts
const config: NextConfig = { output: "export" };
```

Then deploy `out/`. The current project keeps the server output because it is the least surprising default for Next 16.

Set `NEXT_PUBLIC_SITE_URL` to the production origin before building, or canonical URLs, Open Graph URLs and the sitemap will keep pointing at the placeholder domain.

## QA

The last automated pass covered 11 routes at 390×844, 768×1024 and 1440×900, plus interaction checks:

- zero console/page errors
- no horizontal overflow and no empty links
- one command-palette dialog, input focused, Escape closes, focus returns to the trigger
- pricing tabs update $19 / $29 / $39
- FAQ `aria-expanded` changes after a frame
- catalogue filter 94 → 12
- mobile menu opens and closes with Escape
- `/og.png` returns 200

Before shipping, also verify with a real screen reader that the palette’s focus trap, skip link, and disclosure buttons behave as expected.
