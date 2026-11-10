import type { CategoryId } from "./catalog";

interface Detail {
  steps: { title: string; body: string }[];
  notes: string[];
}

const BY_CATEGORY: Record<CategoryId, Detail> = {
  video: {
    steps: [
      {
        title: "Drop the clip",
        body: "Drag a video in, or choose one from the Finder. Nookit reads it where it is; the source stays untouched.",
      },
      {
        title: "Choose the output",
        body: "The video tools offer a quality preset, an MP4 or MOV container, or in and out points for a trim.",
      },
      {
        title: "Take the result",
        body: "The new file lands in a dated folder in Downloads, with a Reveal button. Nothing overwrites the original.",
      },
    ],
    notes: [
      "Progress is shown while an export runs.",
      "The ready tools use Apple's system encoders for MP4 and MOV. Edit, convert-to-GIF and subtitle tools use a system FFmpeg and say so if it is missing.",
      "Nothing is uploaded. Video never leaves the Mac.",
    ],
  },
  audio: {
    steps: [
      {
        title: "Add audio",
        body: "Choose a video to pull its soundtrack from, or record straight into the tool from the default input.",
      },
      {
        title: "Pick the operation",
        body: "Extract the existing audio track as M4A, or record a new 44.1 kHz mono M4A with a running timer.",
      },
      {
        title: "Save and keep the original",
        body: "The result is written to a dated folder as a new file. The source is never modified.",
      },
    ],
    notes: [
      "Microphone access is requested only while you are recording.",
      "Transcription runs on-device and stops if the offline model is missing; no audio is uploaded.",
      "Recordings are saved as M4A. Extract Audio writes M4A and does not re-encode the video.",
    ],
  },
  images: {
    steps: [
      {
        title: "Drop images",
        body: "One image or a batch. The queue shows how many files are waiting before you run anything.",
      },
      {
        title: "Pick the recipe",
        body: "Format, quality, longest edge, rotation or metadata removal — only the options that tool actually uses.",
      },
      {
        title: "Export a copy",
        body: "Processed images go to a new dated folder, named after the originals, with no silent overwrites.",
      },
    ],
    notes: [
      "PNG and HEIC outputs stay in their format where the tool supports it; other resize and rotate outputs become JPEG.",
      "Remove Metadata keeps colour profiles. Rotate and Beautify redraw the pixels, so metadata is not carried over.",
      "Batch results report the total output size, not a before-and-after comparison.",
    ],
  },
  docs: {
    steps: [
      {
        title: "Choose the document",
        body: "Drop a PDF, or images for Images to PDF, and pick the files in the order you want them.",
      },
      {
        title: "Set pages and options",
        body: "Page ranges or one file per page, a compression resolution, or an output scale — whichever that tool offers.",
      },
      {
        title: "Write a new file",
        body: "Nookit never edits the original in place. The result opens or reveals when it is done.",
      },
    ],
    notes: [
      "PDF work uses Apple's PDFKit and Core Graphics, entirely on the Mac. Office, web and Markdown conversions use LibreOffice when it is installed, with a native text-and-table fallback when it is not.",
      "Compress PDF rasterises pages unless you keep the text layer; text-heavy files may not shrink much.",
      "Password-protected files are handled by Remove Password. Other PDF tools expect a file they can open.",
    ],
  },
  text: {
    steps: [
      {
        title: "Add the input",
        body: "Paste text, choose a document, or choose an audio or video file, depending on the tool.",
      },
      {
        title: "Run it on device",
        body: "Transcription uses Apple's Speech framework; document extraction uses PDFKit and AppKit. Nothing is sent to a server.",
      },
      {
        title: "Copy or export",
        body: "Copy the result or save it as a plain-text file in a dated folder.",
      },
    ],
    notes: [
      "AI features use Apple Intelligence when it is enabled on macOS 26, or any open-source model through Ollama or an OpenAI-compatible local server. Prompts stay on your Mac or local network, and the tool says which provider it will use before it runs.",
      "Extract Text reads selectable text only. Use Make PDF Searchable for scans, or Capture Text for text on screen.",
      "Transcribe produces plain text. Timestamped and SRT export are still planned.",
    ],
  },
  files: {
    steps: [
      {
        title: "Point at the files",
        body: "Pick a folder or choose files. Batch Rename previews every new name before writing anything.",
      },
      {
        title: "Set the rule",
        body: "A name pattern with {name}, {n}, {ext} and {date}, or a ZIP to create or extract.",
      },
      {
        title: "Write the copies",
        body: "Renamed files land in a dated folder and archives extract into a fresh folder. Originals stay where they are.",
      },
    ],
    notes: [
      "Batch Rename copies files rather than moving them, so the originals remain in place.",
      "ZIP creation and extraction use the archive tools built into macOS.",
      "Extraction always goes to a new folder, never over the current directory.",
    ],
  },
  mac: {
    steps: [
      {
        title: "Open the utility",
        body: "Most Mac tools read a system value immediately and show it without a setup step.",
      },
      {
        title: "Change what you came for",
        body: "Start a power assertion, eject a volume, or look up a saved password after macOS confirms it is you.",
      },
      {
        title: "Put it back",
        body: "Temporary modes such as Keep Awake stop when their timer ends, when you stop them, or when Nookit quits.",
      },
    ],
    notes: [
      "System values are read with public APIs and macOS command-line tools; nothing is sent to a server.",
      "The current tools do not delete files. Storage Explorer ranks folders and reveals them in Finder.",
      "Some utilities need a permission; the reason is shown before macOS prompts.",
    ],
  },
  developer: {
    steps: [
      {
        title: "Paste the input",
        body: "Text, a token or a timestamp. The tool parses it locally and reports errors without uploading anything.",
      },
      {
        title: "Read the result",
        body: "Output is selectable and copyable, with match offsets or parse details where the tool provides them.",
      },
      {
        title: "Copy it out",
        body: "One click copies the result. Large inputs stay in the window; nothing leaves the Mac.",
      },
    ],
    notes: [
      "Everything runs locally.",
      "JWT Decoder reads the header and payload only. It does not verify signatures.",
      "Hash Generator hashes text, not files.",
    ],
  },
};

export function toolDetail(category: CategoryId): Detail {
  return BY_CATEGORY[category];
}
