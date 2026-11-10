import type { Metadata } from "next";
import { Icon } from "@/components/icons";
import { Badge, ButtonLink, SectionHeader } from "@/components/ui";
import { counts } from "@/lib/catalog";
import { checkoutIsConfigured } from "@/lib/site";

export const metadata: Metadata = {
  title: "Download and install",
  description:
    "How to install Nookit on macOS 14 or later, activate your licence, and grant the permissions a tool needs.",
  alternates: { canonical: "/download" },
};

const STEPS = [
  {
    n: "01",
    title: "Buy the licence",
    body: "Choose 1, 3 or 5 Macs. The key arrives by email with the receipt. No account is created.",
  },
  {
    n: "02",
    title: "Download the build",
    body: "Your receipt contains the download link and the activation link. Already bought? Search your email for “Nookit”.",
  },
  {
    n: "03",
    title: "Drag it to Applications",
    body: "Open the disk image and drag Nookit into Applications. It lives in the menu bar and the Dock, not in a browser tab.",
  },
  {
    n: "04",
    title: "Activate once",
    body: "Paste the key, or use the one-click page after checkout. After activation the app works offline, with a quiet weekly check.",
  },
];

export default function DownloadPage() {
  return (
    <>
      <section className="relative overflow-hidden border-b border-line">
        <div className="pointer-events-none absolute inset-0 dot-grid opacity-40 [mask-image:radial-gradient(ellipse_60%_60%_at_50%_0%,black,transparent)]" />
        <div className="wrap relative py-14 md:py-18">
          <div className="mx-auto max-w-2xl text-center">
            <p className="eyebrow">Download</p>
            <h1 className="mt-3 text-[clamp(2.4rem,5.4vw,3.9rem)] font-semibold leading-[0.98]">
              Up and running
              <br />
              in a minute.
            </h1>
            <p className="mx-auto mt-4 max-w-xl text-[0.95rem] leading-relaxed text-slate">
              Nookit is delivered after purchase so the licence and build stay in
              sync. Already bought it? The download is in your receipt email.
            </p>
            {!checkoutIsConfigured() ? (
              <p className="mx-auto mt-4 max-w-xl rounded-xl border border-line bg-white/70 px-4 py-3 text-left text-[0.78rem] leading-relaxed text-slate">
                <strong className="text-ink">Pre-release.</strong> Orders are handled
                by email while checkout and notarization are being finished. The
                signed build and licence key follow at launch; nothing is charged
                until the invoice is confirmed.
              </p>
            ) : null}
            <div className="mt-6 flex flex-wrap justify-center gap-3">
              <ButtonLink href="/pricing" size="lg">
                Buy Nookit — $19
                <Icon name="arrowRight" className="h-4 w-4" />
              </ButtonLink>
              <ButtonLink
                href="mailto:support@nookit.app?subject=Nookit%20download%20link"
                variant="ghost"
                size="lg"
              >
                Already bought? Email us
              </ButtonLink>
            </div>
            <div className="mt-4 flex flex-wrap justify-center gap-2">
              <Badge tone="neutral">macOS 14 Sonoma+</Badge>
              <Badge tone="neutral">Apple silicon & Intel</Badge>
              <Badge tone="neutral">Notarized before release</Badge>
            </div>
          </div>
        </div>
      </section>

      <section id="setup" className="wrap scroll-mt-24 py-14">
        <SectionHeader
          eyebrow="Setup"
          title="Four steps, and one of them is buying."
          body="No installer wizard, no background daemon, no login. Drag it in, paste the key, start working."
        />
        <div className="mt-8 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {STEPS.map((step) => (
            <div key={step.n} className="rounded-2xl border border-line bg-white/70 p-5">
              <span className="font-mono text-[0.7rem] text-slate-2">{step.n}</span>
              <h2 className="mt-3 text-[1rem] font-semibold">{step.title}</h2>
              <p className="mt-1.5 text-[0.82rem] leading-relaxed text-slate">{step.body}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="border-y border-line bg-paper-2/30 py-14">
        <div className="wrap grid gap-8 md:grid-cols-2">
          <div>
            <p className="eyebrow">Requirements</p>
            <h2 className="mt-2 text-[1.6rem] font-semibold leading-tight">
              What you need.
            </h2>
            <ul className="mt-4 space-y-2.5">
              {[
                "macOS 14 Sonoma or later, on Apple silicon or Intel.",
                "A few megabytes for the app, plus room for results.",
                "Nookit AI uses Apple Intelligence on macOS 26, or NVIDIA models (Nemotron, etc.) with your API key.",
                "Some video and audio tools use a system FFmpeg; the app names the missing piece and the Homebrew command instead of installing it.",
                "A licence key for 1, 3 or 5 Macs.",
              ].map((item) => (
                <li key={item} className="flex items-start gap-2.5 text-[0.85rem] leading-relaxed text-slate">
                  <Icon name="check" className="mt-0.5 h-3.5 w-3.5 shrink-0 text-mint-deep" strokeWidth={2.6} />
                  {item}
                </li>
              ))}
            </ul>
          </div>

          <div>
            <p className="eyebrow">First run</p>
            <h2 className="mt-2 text-[1.6rem] font-semibold leading-tight">
              Permissions, explained first.
            </h2>
            <p className="mt-3 text-[0.85rem] leading-relaxed text-slate">
              Nookit asks only when a tool you opened needs something, and tells you
              why before macOS shows its own prompt. The rest of the app keeps working
              if you decline.
            </p>
            <div className="mt-4 space-y-2">
              {[
                ["Microphone", "Record Audio"],
                ["Speech Recognition", "Transcribe"],
                ["Calendar", "The notch countdown"],
                ["Screen Recording", "Record Screen, Capture Text"],
                ["Automation", "Music and Spotify controls"],
              ].map(([perm, use]) => (
                <div
                  key={perm}
                  className="flex items-center justify-between gap-3 rounded-lg border border-line bg-white/70 px-3 py-2 text-[0.78rem]"
                >
                  <span className="font-semibold">{perm}</span>
                  <span className="text-right text-slate-2">{use}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      <section className="wrap py-14">
        <SectionHeader
          eyebrow="Troubleshooting"
          title="If something will not open."
          body={`Release builds are signed and notarized before they are published. If macOS still complains, or a tool is missing, these are the usual answers. Still stuck? Email support@nookit.app with your macOS version and the tool name.`}
        />
        <div className="mt-6 grid gap-3 md:grid-cols-3">
          {[
            {
              title: "“App is damaged”",
              body: "Usually a partial download. Delete the copy, download again from your receipt link, and drag it to Applications. Do not use a download manager.",
            },
            {
              title: "A video tool asks for FFmpeg",
              body: "Convert, trim, mute and extract audio use Apple's encoders and need nothing extra. Download, screen recording, subtitles, GIF and the edit tools can use FFmpeg; install it with Homebrew (`brew install ffmpeg`) and Nookit will find it. The app shows the command rather than installing it for you.",
            },
            {
              title: "The notch is not visible",
              body: "Open Settings → Notch and make sure it is enabled. On a Mac without a notch, Nookit draws a pill at the top centre — check that the screen is not in a full-screen space.",
            },
          ].map((item) => (
            <div key={item.title} className="rounded-2xl border border-line bg-paper-2/40 p-5">
              <Icon name="info" className="h-4 w-4 text-ember" />
              <h3 className="mt-2.5 text-[0.92rem] font-semibold">{item.title}</h3>
              <p className="mt-1.5 text-[0.8rem] leading-relaxed text-slate">{item.body}</p>
            </div>
          ))}
        </div>

        <div className="mt-8 flex flex-wrap items-center justify-between gap-4 rounded-2xl bg-ink px-5 py-5 text-paper">
          <div>
            <p className="text-[0.9rem] font-semibold">
              {counts.implementedTools} tools ready today, {counts.tools} in the catalogue.
            </p>
            <p className="mt-1 text-[0.78rem] text-paper/50">
              Roadmap tools are free updates, not a second purchase.
            </p>
          </div>
          <ButtonLink href="/pricing" size="md">
            Buy Nookit
            <Icon name="arrowRight" className="h-4 w-4" />
          </ButtonLink>
        </div>
      </section>
    </>
  );
}
