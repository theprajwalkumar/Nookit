import type { Metadata } from "next";
import { LegalSection, LegalShell } from "@/components/legal";
import { counts } from "@/lib/catalog";

export const metadata: Metadata = {
  title: "Terms of sale and licence",
  description:
    "The licence terms for Nookit: what you can install, how activation works, the roadmap commitment, refunds and the limits of our liability.",
  alternates: { canonical: "/terms" },
};

export default function TermsPage() {
  return (
    <LegalShell
      eyebrow="Terms"
      title="A licence you can read in one sitting."
      updated="2 November 2026"
      intro={`These terms cover your purchase and use of Nookit, a macOS application with ${counts.tools} tool entries and ${counts.notch} notch modules. By buying or using the app you agree to them. If you do not agree, do not install or use the app and ask for a refund within the refund window.`}
    >
      <LegalSection title="1. What you are buying">
        <p>
          You are buying a perpetual, non-exclusive, non-transferable licence to use
          Nookit on the number of Macs shown on your receipt (one, three or five).
          You are not buying the copyright in the software, the brand, the catalogue
          copy or the design. We keep those rights.
        </p>
        <p>
          A licence is for the people who use the Macs in question. It is not a
          site-wide or company-wide licence. Teams of 10 Macs or more need a separate
          agreement; email support@nookit.app.
        </p>
      </LegalSection>

      <LegalSection title="2. Activation and moving machines">
        <p>
          Your key arrives by email with the receipt. Activate it in the app, or use
          the one-click link on the page after checkout. Activation needs a
          connection the first time; after that the app works offline, with a quiet
          weekly check.
        </p>
        <p>
          You can deactivate a Mac and activate another within your licence count,
          for example when you replace a laptop. If a repair changes the machine
          identity, contact support and we will reset the activation.
        </p>
      </LegalSection>

      <LegalSection title="3. The roadmap, stated plainly">
        <p>
          The catalogue lists {counts.tools} tools, and every one is ready in the
          current build. The notch is the one deliberately partial surface: 10 of its
          24 modules are ready, and the other 14 are marked “On the roadmap”. Roadmap
          modules are included in your purchase and are intended to arrive as free
          updates, but we do not promise a specific date and we do not warrant that
          every roadmap item will ship. The app shows the same status as this website.
        </p>
        <p>
          If a roadmap notch module is essential to your decision, do not buy on the
          strength of it alone. Buy for what is ready today. If the gap is material to
          you, the refund window is the honest escape hatch.
        </p>
      </LegalSection>

      <LegalSection title="4. Updates">
        <p>
          Updates within the product&apos;s life are free for licence holders. We may
          stop supporting an operating system version when Apple stops supporting it.
          We may also release a separately priced future product, but we will not move
          existing included tools behind a new paywall.
        </p>
      </LegalSection>

      <LegalSection id="refunds" title="5. Refunds">
        <p>
          Ask within 14 days of purchase and we will refund the amount you paid,
          through the same payment method. You do not need to justify it. We may ask
          for your order reference so we can find the payment.
        </p>
        <p>
          After 14 days, refunds are at our discretion, except where the law requires
          one. If a paid tool is broken and we cannot fix it in a reasonable time, tell
          us — we would rather refund than argue.
        </p>
        <p>
          Chargebacks without contacting us first make support slower for everyone.
          Please email support@nookit.app.
        </p>
      </LegalSection>

      <LegalSection title="6. Acceptable use">
        <p>You may use Nookit for personal and commercial work. You may not:</p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li>Redistribute, resell, sublicense or rent the app or a licence key.</li>
          <li>
            Reverse engineer, decompile or disassemble the app except where the law
            expressly permits it.
          </li>
          <li>
            Remove or bypass licence checks, or use the app to infringe someone
            else&apos;s rights.
          </li>
          <li>
            Use the downloader or web tools in violation of a site&apos;s terms or
            applicable law. You are responsible for the material you process.
          </li>
        </ul>
        <p>
          Tools that operate on files assume you have the right to those files. Nookit
          does not grant you rights you do not already have.
        </p>
      </LegalSection>

      <LegalSection title="7. Beta and early builds">
        <p>
          Early builds are labelled as such. They may contain defects and may change
          without notice. Every catalogued tool is present, but roadmap notch modules
          may still be missing. Back up important files before processing them, as you
          would with any new software. The refund and support commitments above still
          apply.
        </p>
      </LegalSection>

      <LegalSection title="8. Third-party components">
        <p>
          Nookit uses Apple frameworks and may use open-source components such as
          FFmpeg for some video work. Those components remain under their own
          licences; nothing in these terms changes your rights under them. FFmpeg is a
          trademark of Fabrice Bellard. Apple, Mac, macOS, Apple Intelligence and
          related marks are trademarks of Apple Inc. Nookit is independent and not
          affiliated with or endorsed by Apple.
        </p>
      </LegalSection>

      <LegalSection title="9. Privacy">
        <p>
          Our privacy policy explains what little data we handle and the four
          situations where the app uses the network. It forms part of these terms.
        </p>
      </LegalSection>

      <LegalSection title="10. Warranty and liability">
        <p>
          To the maximum extent permitted by law, Nookit is provided “as is” without
          warranties of merchantability, fitness for a particular purpose or
          non-infringement. We do not warrant that it will be uninterrupted or
          error-free, or that it will preserve every format or metadata field.
        </p>
        <p>
          To the maximum extent permitted by law, our total liability arising out of
          or relating to the app or these terms is limited to the amount you paid for
          the licence in the twelve months before the claim. We are not liable for
          indirect, incidental, special or consequential damages, or for lost data,
          profits or business. Nothing here excludes liability that cannot lawfully be
          excluded.
        </p>
      </LegalSection>

      <LegalSection title="11. Termination">
        <p>
          We may end this licence if you materially breach these terms, for example by
          redistributing keys. If we do, you must stop using the app and remove it. The
          refund policy and any rights you have under consumer law are unaffected.
        </p>
      </LegalSection>

      <LegalSection title="12. Governing law">
        <p>
          These terms are governed by the laws of India, without regard to conflict of
          law rules. Courts in India have exclusive jurisdiction, except where
          mandatory consumer law in your country gives you the right to bring a claim
          locally. If any provision is unenforceable, the rest stays in force.
        </p>
      </LegalSection>

      <LegalSection title="13. Changes to these terms">
        <p>
          We may update these terms for future versions of the app. The version you
          accepted at purchase continues to govern that purchase unless you install a
          later version, in which case the terms shipped with it apply. Material
          changes will be noted in the changelog.
        </p>
      </LegalSection>

      <LegalSection title="14. Contact">
        <p>
          Questions about these terms, licences or invoices:{" "}
          <strong className="text-ink">support@nookit.app</strong>.
        </p>
      </LegalSection>
    </LegalShell>
  );
}
