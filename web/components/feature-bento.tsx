import { Icon } from "./icons";
import { Badge } from "./ui";

export function FeatureBento() {
  return (
    <div className="grid grid-cols-1 gap-3 md:grid-cols-12">
      {/* Big: one window per job */}
      <div className="relative overflow-hidden rounded-[22px] border border-line bg-white p-5 md:col-span-7 md:p-7">
        <div className="max-w-md">
          <Badge tone="ember">The shape of it</Badge>
          <h3 className="mt-3 text-[1.5rem] font-semibold leading-tight tracking-[-0.03em]">
            One window per job. Only the settings that job needs.
          </h3>
          <p className="mt-2 text-[0.86rem] leading-relaxed text-slate">
            No ribbon of a hundred buttons. Open Convert Video and you get a drop
            zone, a quality preset and a result. Open JSON Formatter and you get a
            text editor and an error line.
          </p>
        </div>

        <div className="mt-5 rounded-xl border border-line bg-paper p-3">
          <div className="flex items-center gap-2 border-b border-line pb-2">
            <span className="h-2 w-2 rounded-full bg-[#ff5f57]" />
            <span className="h-2 w-2 rounded-full bg-[#febc2e]" />
            <span className="h-2 w-2 rounded-full bg-[#28c840]" />
            <span className="ml-2 text-[0.66rem] font-medium text-slate-2">
              Convert Video
            </span>
            <span className="ml-auto rounded-full bg-mint/15 px-2 py-0.5 text-[0.58rem] font-semibold text-mint-deep">
              Ready
            </span>
          </div>
          <div className="mt-2.5 grid gap-2 sm:grid-cols-[1.2fr_1fr]">
            <div className="flex flex-col items-center justify-center rounded-lg border border-dashed border-line-strong bg-white/60 py-6">
              <Icon name="arrowDownCircle" className="h-5 w-5 text-ember" />
              <p className="mt-1.5 text-[0.66rem] font-semibold">Drop a video</p>
              <p className="text-[0.58rem] text-slate-2">MP4, MOV, M4V</p>
            </div>
            <div className="space-y-1.5">
              {[
                { label: "Quality", value: "Balanced" },
                { label: "Format", value: "MP4" },
                { label: "Encoder", value: "System" },
              ].map((row) => (
                <div
                  key={row.label}
                  className="flex items-center justify-between rounded-md border border-line bg-white px-2 py-1.5"
                >
                  <span className="text-[0.6rem] text-slate-2">{row.label}</span>
                  <span className="text-[0.6rem] font-semibold">{row.value}</span>
                </div>
              ))}
              <div className="rounded-md bg-ink px-2 py-1.5 text-center text-[0.6rem] font-semibold text-paper">
                Export
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Results */}
      <div className="rounded-[22px] border border-line bg-paper-2/70 p-5 md:col-span-5 md:p-7">
        <span className="grid h-9 w-9 place-items-center rounded-[10px] bg-white text-ink">
          <Icon name="folder" className="h-4 w-4" />
        </span>
        <h3 className="mt-3 text-[1.15rem] font-semibold tracking-[-0.02em]">
          Results land somewhere sensible.
        </h3>
        <p className="mt-1.5 text-[0.82rem] leading-relaxed text-slate">
          Every run gets a dated folder. Originals are never moved or overwritten.
        </p>
        <div className="mt-4 rounded-lg border border-line bg-white p-3 font-mono text-[0.62rem] leading-[1.9] text-slate">
          <p className="text-slate-2">Downloads / Nookit /</p>
          <p>
            <span className="text-ember-deep">▾</span> 2026-11-02 Convert Video
          </p>
          <p className="pl-4">launch-cut.mp4 <span className="text-slate-2">186 MB</span></p>
          <p>
            <span className="text-slate-2">▸</span> 2026-11-02 Merge PDFs
          </p>
          <p>
            <span className="text-slate-2">▸</span> 2026-11-01 Batch Rename
          </p>
        </div>
      </div>

      {/* Stat */}
      <div className="relative overflow-hidden rounded-[22px] bg-ember p-5 text-white md:col-span-4 md:p-7">
        <div className="absolute -right-8 -top-10 h-32 w-32 rounded-full bg-white/15 blur-2xl" />
        <p className="text-[0.62rem] font-semibold uppercase tracking-[0.14em] text-white/60">
          Trim Video
        </p>
        <p className="mt-2 text-[2.6rem] font-semibold leading-none tracking-[-0.05em]">
          00:42
        </p>
        <p className="mt-1 text-[0.82rem] text-white/75">kept from a 12:18 clip</p>
        <div className="mt-4 h-1.5 overflow-hidden rounded-full bg-white/20">
          <div className="h-full w-[13%] rounded-full bg-white" />
        </div>
        <p className="mt-3 text-[0.72rem] leading-relaxed text-white/70">
          Set in and out points and export just that range. The original file stays
          where it is.
        </p>
      </div>

      {/* Launcher */}
      <div className="rounded-[22px] border border-line bg-white p-5 md:col-span-4 md:p-7">
        <div className="flex items-center justify-between">
          <span className="grid h-9 w-9 place-items-center rounded-[10px] bg-paper-2 text-ink">
            <Icon name="command" className="h-4 w-4" />
          </span>
          <span className="text-[0.58rem] font-semibold uppercase tracking-[0.1em] text-slate-2">
            0.2 · in progress
          </span>
        </div>
        <h3 className="mt-3 text-[1.15rem] font-semibold tracking-[-0.02em]">
          Any tool from any app.
        </h3>
        <p className="mt-1.5 text-[0.82rem] leading-relaxed text-slate">
          A global launcher for the tool you need, without finding the window.
        </p>
        <div className="mt-4 rounded-lg border border-line bg-paper p-2">
          <div className="flex items-center gap-2 rounded-md bg-white px-2 py-1.5 shadow-sm">
            <Icon name="search" className="h-3 w-3 text-slate-2" />
            <span className="text-[0.66rem] text-slate">pdf m…</span>
            <span className="ml-auto flex gap-0.5">
              <span className="rounded border border-line px-1 font-mono text-[0.5rem]">⌃</span>
              <span className="rounded border border-line px-1 font-mono text-[0.5rem]">⌥</span>
              <span className="rounded border border-line px-1 font-mono text-[0.5rem]">space</span>
            </span>
          </div>
          <p className="mt-1.5 px-1 text-[0.6rem] text-slate-2">Merge PDFs · Split PDF · Extract Pages</p>
        </div>
      </div>

      {/* Privacy */}
      <div className="rounded-[22px] border border-white/10 bg-ink p-5 text-paper md:col-span-4 md:p-7">
        <span className="grid h-9 w-9 place-items-center rounded-[10px] bg-white/[0.08] text-mint">
          <Icon name="shield" className="h-4 w-4" />
        </span>
        <h3 className="mt-3 text-[1.15rem] font-semibold tracking-[-0.02em]">
          The file stays here.
        </h3>
        <p className="mt-1.5 text-[0.82rem] leading-relaxed text-paper/55">
          Compression, transcription, PDF work and every Mac chore run on your own
          chip. No upload queue, no account, no analytics SDK.
        </p>
        <div className="mt-4 flex flex-wrap gap-1.5">
          {["No account", "No telemetry", "Works offline"].map((t) => (
            <span
              key={t}
              className="rounded-full bg-white/[0.07] px-2 py-1 text-[0.6rem] text-paper/60"
            >
              {t}
            </span>
          ))}
        </div>
      </div>

      {/* Storage */}
      <div className="rounded-[22px] border border-line bg-paper-2/70 p-5 md:col-span-4 md:p-7">
        <span className="grid h-9 w-9 place-items-center rounded-[10px] bg-white text-ink">
          <Icon name="internaldrive" className="h-4 w-4" />
        </span>
        <h3 className="mt-3 text-[1.15rem] font-semibold tracking-[-0.02em]">
          Big folders, in plain sight.
        </h3>
        <p className="mt-1.5 text-[0.82rem] leading-relaxed text-slate">
          Scan your home folder and see the top-level folders ranked by allocated
          size. Nookit reveals them in Finder; it does not delete anything.
        </p>
        <div className="mt-4 space-y-2">
          {[
            { name: "Library", size: "38.2 GB", w: "88%" },
            { name: "Movies", size: "12.4 GB", w: "41%" },
            { name: "Pictures", size: "9.1 GB", w: "30%" },
          ].map((row) => (
            <div key={row.name}>
              <div className="flex justify-between text-[0.62rem]">
                <span className="font-medium">{row.name}</span>
                <span className="text-slate-2">{row.size}</span>
              </div>
              <div className="mt-1 h-1 rounded-full bg-line">
                <div className="h-full rounded-full bg-ink/70" style={{ width: row.w }} />
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
