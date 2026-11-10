import SwiftUI

/// The single place that maps catalog slugs to real screens.
/// A tool is "Ready" only when a builder is registered here.
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()

    private var builders: [String: () -> AnyView] = [:]

    private init() {
        registerAll()
    }

    func has(_ slug: String) -> Bool {
        builders[slug] != nil
    }

    func view(for slug: String) -> AnyView? {
        builders[slug]?()
    }

    func readyCount(in catalog: CatalogData) -> Int {
        catalog.tools.filter { has($0.slug) }.count
    }

    private func add(_ slug: String, _ make: @escaping () -> AnyView) {
        builders[slug] = make
    }

    // MARK: - Registrations

    private func registerAll() {
        // Developer
        add("json-formatter") { AnyView(JSONFormatterTool()) }
        add("base64") { AnyView(Base64Tool()) }
        add("hash-generator") { AnyView(HashGeneratorTool()) }
        add("uuid-generator") { AnyView(UUIDGeneratorTool()) }
        add("jwt-decoder") { AnyView(JWTDecoderTool()) }
        add("timestamp-converter") { AnyView(TimestampConverterTool()) }
        add("diff-checker") { AnyView(DiffCheckerTool()) }
        add("regex-tester") { AnyView(RegexTesterTool()) }
        add("clean-links") { AnyView(CleanLinksTool()) }
        add("unicode-inspector") { AnyView(UnicodeInspectorTool()) }
        add("lorem-ipsum") { AnyView(LoremIpsumTool()) }

        // Text & speech
        add("word-counter") { AnyView(WordCounterTool()) }
        add("case-converter") { AnyView(CaseConverterTool()) }
        add("extract-text") { AnyView(ExtractTextTool()) }
        add("text-to-speech") { AnyView(TextToSpeechTool()) }
        add("transcribe") { AnyView(TranscribeTool()) }

        // Files
        add("qr-code") { AnyView(QRCodeTool()) }
        add("batch-rename") { AnyView(BatchRenameTool()) }
        add("zip-unzip") { AnyView(ZipUnzipTool()) }

        // Images
        add("convert-images") { AnyView(ImageBatchTool(operation: .convert)) }
        add("resize-images") { AnyView(ImageBatchTool(operation: .resize)) }
        add("compress-images") { AnyView(ImageBatchTool(operation: .compress)) }
        add("rotate-images") { AnyView(ImageBatchTool(operation: .rotate)) }
        add("remove-metadata") { AnyView(ImageBatchTool(operation: .strip)) }
        add("beautify-screenshot") { AnyView(ImageBatchTool(operation: .beautify)) }

        // PDFs
        add("merge-pdfs") { AnyView(PDFTool(operation: .merge)) }
        add("split-pdf") { AnyView(PDFTool(operation: .split)) }
        add("extract-pdf-pages") { AnyView(PDFTool(operation: .extract)) }
        add("images-to-pdf") { AnyView(PDFTool(operation: .imagesToPDF)) }
        add("pdf-to-images") { AnyView(PDFTool(operation: .toImages)) }
        add("compress-pdf") { AnyView(PDFTool(operation: .compress)) }
        add("remove-pdf-password") { AnyView(PDFTool(operation: .unlock)) }

        // Video & audio
        add("media-info") { AnyView(MediaInfoTool()) }
        add("convert-video") { AnyView(VideoTool(operation: .convert)) }
        add("trim-video") { AnyView(VideoTool(operation: .trim)) }
        add("mute-video") { AnyView(VideoTool(operation: .mute)) }
        add("extract-audio") { AnyView(VideoTool(operation: .extractAudio)) }
        add("record-audio") { AnyView(RecordAudioTool()) }

        // Audio (extended)
        add("clean-up-audio") { AnyView(CleanUpAudioTool()) }
        add("trim-audio") { AnyView(TrimAudioTool()) }
        add("convert-audio") { AnyView(ConvertAudioTool()) }

        // Images (extended)
        add("blur-faces") { AnyView(BlurFacesTool()) }
        add("remove-background") { AnyView(RemoveBackgroundTool()) }
        add("color-picker") { AnyView(ColorPickerTool()) }
        add("redact-image") { AnyView(RedactImageTool()) }
        add("annotate-screenshot") { AnyView(AnnotateScreenshotTool()) }

        // Documents (extended)
        add("scan-document") { AnyView(ScanDocumentTool()) }
        add("redact-pdf") { AnyView(RedactPDFTool()) }
        add("fill-pdf-forms") { AnyView(FillPDFFormsTool()) }
        add("ocr-pdf") { AnyView(OCRPDFTool()) }
        add("pdf-to-word") { AnyView(PDFToWordTool()) }
        add("sign-pdf") { AnyView(SignPDFTool()) }
        add("organize-pdf") { AnyView(OrganizePDFTool()) }
        add("delete-pdf-pages") { AnyView(DeletePDFPagesTool()) }
        add("password-protect-pdf") { AnyView(PasswordProtectPDFTool()) }
        add("convert-documents") { AnyView(ConvertDocumentsTool()) }
        add("word-to-pdf") { AnyView(WordToPDFTool()) }
        add("powerpoint-to-pdf") { AnyView(PowerPointToPDFTool()) }
        add("excel-to-pdf") { AnyView(ExcelToPDFTool()) }
        add("webpage-to-pdf") { AnyView(WebpageToPDFTool()) }
        add("markdown-to-pdf") { AnyView(MarkdownToPDFTool()) }

        // Text
        add("summarize") { AnyView(SummarizeTool()) }
        add("capture-text") { AnyView(CaptureTextTool()) }
        add("translate") { AnyView(TranslateTool()) }
        add("ask-a-document") { AnyView(AskDocumentTool()) }

        // Files
        add("find-duplicates") { AnyView(FindDuplicatesTool()) }

        // Video (extended)
        add("download-video") { AnyView(DownloadVideoTool()) }
        add("burn-subtitles") { AnyView(BurnSubtitlesTool()) }
        add("change-speed") { AnyView(ChangeSpeedTool()) }
        add("extract-frames") { AnyView(ExtractFramesTool()) }
        add("record-screen") { AnyView(RecordScreenTool()) }
        add("compress-video") { AnyView(CompressVideoTool()) }
        add("resize-video") { AnyView(ResizeVideoTool()) }
        add("crop-rotate-video") { AnyView(CropRotateVideoTool()) }
        add("merge-videos") { AnyView(MergeVideosTool()) }
        add("replace-audio") { AnyView(ReplaceAudioTool()) }
        add("video-to-gif") { AnyView(VideoToGIFTool()) }

        // Mac
        add("keep-awake") { AnyView(KeepAwakeTool()) }
        add("eject-all-disks") { AnyView(EjectDisksTool()) }
        add("battery-health") { AnyView(BatteryHealthTool()) }
        add("storage-explorer") { AnyView(StorageExplorerTool()) }
        add("network-speed-test") { AnyView(NetworkSpeedTestTool()) }
        add("wifi-password") { AnyView(WiFiPasswordTool()) }
        add("uninstall-app") { AnyView(UninstallAppTool()) }
        add("presentation-mode") { AnyView(PresentationModeTool()) }
        add("clean-keyboard") { AnyView(CleanKeyboardTool()) }
        add("dead-pixel-test") { AnyView(DeadPixelTestTool()) }
        add("login-items") { AnyView(LoginItemsTool()) }
        add("fix-app-damaged") { AnyView(FixAppDamagedTool()) }
        add("reset-permissions") { AnyView(ResetPermissionsTool()) }
        add("hidden-settings") { AnyView(HiddenSettingsTool()) }
        add("display-control") { AnyView(DisplayControlTool()) }
        add("mouse-fixes") { AnyView(MouseFixesTool()) }

        // Developer
        add("coordinate-picker") { AnyView(CoordinatePickerTool()) }

        // An unregistered slug still appears in the dashboard with a "Soon" badge.
    }
}
