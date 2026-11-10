import type { Metadata } from "next";
import { Icon } from "@/components/icons";
import { ButtonLink } from "@/components/ui";

export const metadata: Metadata = {
  title: "You're in",
  description: "Your Nookit licence is on its way.",
  robots: { index: false, follow: false },
};

export default function SuccessPage() {
  return (
    <section className="wrap flex min-h-[70vh] max-w-2xl flex-col items-center justify-center py-20 text-center">
      <span className="grid h-16 w-16 place-items-center rounded-full bg-mint/20 text-mint-deep">
        <Icon name="check" className="h-7 w-7" strokeWidth={2.6} />
      </span>
      <h1 className="mt-6 text-[clamp(2rem,5vw,3rem)] font-semibold leading-tight">
        You&apos;re in.
      </h1>
      <p className="mt-3 max-w-md text-[0.95rem] leading-relaxed text-slate">
        Check your inbox for the receipt and licence key. If you ordered by email,
        the reply includes the key and the download link. If nothing arrives, look
        in spam, then email support@nookit.app and we will resend it.
      </p>
      <div className="mt-8 w-full max-w-md space-y-2 text-left">
        {[
          "Open the email and copy your licence key.",
          "Download the build from the same email and drag it to Applications.",
          "Paste the key on first launch. Activation takes a second.",
          "Open the dashboard and press ⌘K to find your first tool.",
        ].map((step, i) => (
          <div
            key={step}
            className="flex items-start gap-3 rounded-xl border border-line bg-white/70 p-3.5"
          >
            <span className="grid h-6 w-6 shrink-0 place-items-center rounded-full bg-ink font-mono text-[0.62rem] text-paper">
              {i + 1}
            </span>
            <p className="text-[0.84rem] leading-relaxed text-slate">{step}</p>
          </div>
        ))}
      </div>
      <div className="mt-7 flex flex-wrap justify-center gap-3">
        <ButtonLink href="/download" size="md">
          Setup guide
          <Icon name="arrowRight" className="h-4 w-4" />
        </ButtonLink>
        <ButtonLink
          href="mailto:support@nookit.app?subject=My%20Nookit%20order"
          variant="ghost"
          size="md"
        >
          Contact support
        </ButtonLink>
      </div>
    </section>
  );
}
