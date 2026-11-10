import Link from "next/link";
import { PERMISSIONS } from "@/lib/site";
import { Icon, iconForSymbol } from "./icons";

const ONLINE = [
  "Video downloader — the link you paste",
  "Speed test — Cloudflare's endpoints",
  "Local AI model — the server you configure",
  "Web page to PDF — the page you ask for",
  "Licence activation and a weekly key check",
];

export function PrivacyGrid() {
  return (
    <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
      {PERMISSIONS.map((p) => (
        <div
          key={p.name}
          className="rounded-2xl border border-line bg-white/70 p-4 transition-colors hover:bg-white"
        >
          <div className="flex items-center gap-2.5">
            <span className="grid h-8 w-8 place-items-center rounded-[9px] bg-ink text-paper">
              <Icon name={iconForSymbol(p.icon)} className="h-4 w-4" />
            </span>
            <h3 className="text-[0.86rem] font-semibold">{p.name}</h3>
          </div>
          <p className="mt-2 text-[0.78rem] leading-relaxed text-slate">{p.why}</p>
        </div>
      ))}

      <div className="rounded-2xl border border-ink bg-ink p-4 text-paper md:col-span-2 lg:col-span-3">
        <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
          <div className="max-w-xl">
            <div className="flex items-center gap-2">
              <Icon name="wifi" className="h-4 w-4 text-ember-soft" />
              <h3 className="text-[0.9rem] font-semibold">Where the release build will connect</h3>
            </div>
            <p className="mt-2 text-[0.8rem] leading-relaxed text-paper/55">
              Everything else is local. There is no analytics SDK, no crash reporter
              that ships your files, and no account to log in to. A request leaves
              the Mac only when you run one of these features.
            </p>
          </div>
          <ul className="grid gap-1.5 sm:grid-cols-2 md:max-w-md">
            {ONLINE.map((item) => (
              <li
                key={item}
                className="flex items-start gap-2 rounded-lg bg-white/[0.05] px-2.5 py-2 text-[0.7rem] leading-snug text-paper/65"
              >
                <Icon name="check" className="mt-0.5 h-3 w-3 shrink-0 text-mint" />
                {item}
              </li>
            ))}
          </ul>
        </div>
        <div className="mt-4 border-t border-white/10 pt-3">
          <Link
            href="/privacy"
            className="inline-flex items-center gap-1.5 text-[0.72rem] font-semibold text-ember-soft hover:text-paper"
          >
            Read the privacy policy
            <Icon name="arrowRight" className="h-3 w-3" />
          </Link>
        </div>
      </div>
    </div>
  );
}
