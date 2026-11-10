import type { Metadata } from "next";
import { LegalSection, LegalShell } from "@/components/legal";

export const metadata: Metadata = {
  title: "Privacy policy",
  description:
    "How Nookit handles your files, your licence and the little data it needs. Your files stay on your Mac; there is no analytics SDK and no account.",
  alternates: { canonical: "/privacy" },
};

export default function PrivacyPage() {
  return (
    <LegalShell
      eyebrow="Privacy"
      title="Your files stay on your Mac. That is the product."
      updated="2 November 2026"
      intro="Nookit is a local-first Mac application. Files you open with a tool are processed on your machine and are not uploaded to us. This page explains the small amount of data we handle and the specific times the app uses the network."
    >
      <LegalSection title="The short version">
        <p>
          We do not want your documents, your photos, your recordings or your
          clipboard. Nookit has no analytics SDK, no advertising tracker and no
          account system. The data we hold is limited to what is needed to sell you
          a licence, deliver it, and support you.
        </p>
      </LegalSection>

      <LegalSection title="What stays on your Mac">
        <p>
          Video, audio, images, documents, text, archives and Mac system values are
          read and written locally. The app writes new result files to a dated folder
          inside a Nookit folder in Downloads, or to a folder you choose in Settings.
          Originals are not moved or overwritten unless you explicitly choose a
          destructive action and confirm it.
        </p>
        <p>
          Notes, tasks and habits are stored as files in a folder inside Application
          Support on your Mac. Clipboard history and the water counter live in the
          app&apos;s own preferences. None of it is synced to us or to any third
          party. You can back it up, read it with any text editor, or delete it at any
          time.
        </p>
      </LegalSection>

      <LegalSection title="When the app uses the network">
        <p>Nookit is designed to use the network only when you use a network feature:</p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li>
            <strong className="text-ink">Download Video</strong> contacts the site
            whose link you paste, in order to fetch the video you asked for. On the
            first streaming download it also fetches the official standalone
            yt-dlp engine from GitHub. Browser cookies are read only if you choose
            that option.
          </li>
          <li>
            <strong className="text-ink">Network Speed Test</strong> measures
            latency and transfers small timed payloads to and from Cloudflare, which
            measures your connection against Cloudflare&apos;s servers.
          </li>
          <li>
            <strong className="text-ink">Nookit AI</strong>{" "}
            sends your prompt to Apple Intelligence (on-device) or to NVIDIA&apos;s API when
            you provide an API key. Nookit does not proxy prompts through its own
            cloud service. Your NVIDIA API key stays in your Mac&apos;s preferences.
          </li>
          <li>
            <strong className="text-ink">Web Page to PDF</strong> requests the page
            you provide, if you use that tool.
          </li>
          <li>
            <strong className="text-ink">Coordinate Picker</strong> asks Apple for
            map tiles and search results when you open the map or search for a
            place. Your search text goes to Apple&apos;s map service; the points you
            drop and any report you save stay on the Mac.
          </li>
          <li>
            <strong className="text-ink">Licence activation</strong> in the release
            build will send your licence key and an anonymous activation identifier
            to our licensing service. A quiet weekly check will do the same. It
            contains no file names, no usage history and no document contents. The
            current prototype has no activation or licence check.
          </li>
        </ul>
        <p>
          AI Chat, transcription, PDF work, image work, hashing and every Mac
          utility run on your Mac or your local network. They do not require an
          internet connection.
        </p>
      </LegalSection>

      <LegalSection title="Permissions">
        <p>
          Nookit asks only for what a tool you opened needs, and explains why before
          macOS shows its own prompt. Microphone is used for recording; Speech
          Recognition for on-device transcription; Calendar for the notch countdown;
          Automation for the notch music player. Screen Recording is used only when
          you run Record Screen or Capture Text. You can revoke any of them in System
          Settings, and the rest of the app keeps working.
        </p>
      </LegalSection>

      <LegalSection title="What we collect when you buy">
        <ul className="list-disc space-y-1.5 pl-5">
          <li>Your email address, so we can send the licence and receipt.</li>
          <li>
            Licence key, purchase date, licence size and an anonymous activation
            identifier, so activation and support work.
          </li>
          <li>
            Payment and tax details, handled by our merchant of record. We do not see
            or store your full card number.
          </li>
          <li>
            Support emails you send us, kept only as long as needed to resolve the
            issue.
          </li>
        </ul>
        <p>
          We do not collect your files, your clipboard contents, your notes, your
          calendar events, your browsing history or a persistent advertising
          identifier. We do not sell personal data.
        </p>
      </LegalSection>

      <LegalSection title="This website">
        <p>
          The marketing site does not set advertising cookies and does not include a
          third-party analytics script. Our hosting provider may keep standard
          server logs (IP address, user agent, requested URL, timestamp) for
          security and reliability. If we add privacy-friendly analytics later, this
          page will say so before it is enabled.
        </p>
      </LegalSection>

      <LegalSection title="Who processes data for us">
        <p>
          We use a payment merchant of record to take payments and calculate tax, an
          email provider to send receipts and licence keys, a licensing service to
          validate activation, and a hosting provider for this website. Each receives
          only the data needed for its job. We do not share data for advertising.
        </p>
      </LegalSection>

      <LegalSection title="Retention">
        <p>
          Purchase records and licence data are kept while your licence is active and
          for as long afterwards as tax and accounting rules require. Support emails
          are deleted when the issue is closed, unless they are needed for a warranty
          or dispute. You can ask us to delete support correspondence sooner.
        </p>
      </LegalSection>

      <LegalSection title="Your rights">
        <p>
          Depending on where you live, you may have the right to access, correct,
          export, restrict or delete the personal data we hold, and to object to some
          processing. Email support@nookit.app and we will respond within 30 days. We
          may need to keep purchase records where the law requires it. If you are in
          the EEA or UK, you can also complain to your local data protection
          authority.
        </p>
      </LegalSection>

      <LegalSection title="Security">
        <p>
          Licence traffic uses HTTPS. Activation identifiers are random and are not
          derived from your hardware serial number. No system is perfect; if we
          become aware of a breach affecting your data, we will tell you and the
          relevant authority as required.
        </p>
      </LegalSection>

      <LegalSection title="Children">
        <p>
          Nookit is a general-purpose utility and is not directed at children under
          13. We do not knowingly collect personal data from children.
        </p>
      </LegalSection>

      <LegalSection title="Changes">
        <p>
          If this policy changes in a way that affects what we collect, we will
          update this page and note the change in the changelog. Material changes
          will be announced by email to licence holders.
        </p>
      </LegalSection>

      <LegalSection title="Contact">
        <p>
          Privacy questions: <strong className="text-ink">support@nookit.app</strong>.
          We are the controller of the licence and support data described here.
        </p>
      </LegalSection>
    </LegalShell>
  );
}
