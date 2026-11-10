import SwiftUI
import WebKit

/// Live price pages need the real site. This sheet embeds a small, safe browser
/// with back/forward/reload and an escape hatch to Safari.
struct WebBrowserSheet: View {
    let title: String
    let url: URL
    /// When embedded inline (not as a sheet), provide a close handler instead of
    /// relying on the environment dismiss.
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var pageTitle = ""
    @State private var reloadToken = UUID()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            WebView(
                url: url,
                reloadToken: reloadToken,
                isLoading: $isLoading,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                pageTitle: $pageTitle
            )
        }
        .frame(minWidth: 600, idealWidth: 900, maxWidth: .infinity, minHeight: 500, idealHeight: 640)
        .background(Theme.background)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.ember.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: "safari.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ember)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(pageTitle.isEmpty ? title : pageTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(url.host ?? url.absoluteString)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.75)
            }

            Spacer()

            HStack(spacing: 3) {
                browserButton("chevron.left", help: "Back", enabled: canGoBack) { send(.goBack) }
                browserButton("chevron.right", help: "Forward", enabled: canGoForward) { send(.goForward) }
                browserButton("arrow.clockwise", help: "Reload", enabled: true) { reloadToken = UUID() }
            }

            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Open in Safari", systemImage: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Open this page in your default browser")

            Button("Done") {
                if let onClose { onClose() } else { dismiss() }
            }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Theme.raised)
    }

    private func browserButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Theme.textSecondary : Theme.textTertiary.opacity(0.5))
                .frame(width: 26, height: 26)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    private func send(_ action: BrowserAction) {
        NotificationCenter.default.post(name: .nookitBrowserAction, object: action)
    }
}

enum BrowserAction: String {
    case goBack
    case goForward
}

extension Notification.Name {
    static let nookitBrowserAction = Notification.Name("NookitBrowserAction")
}

// MARK: - WKWebView wrapper

private struct WebView: NSViewRepresentable {
    let url: URL
    let reloadToken: UUID
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var pageTitle: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        context.coordinator.webView = webView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleAction(_:)),
            name: .nookitBrowserAction,
            object: nil
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastToken != reloadToken {
            context.coordinator.lastToken = reloadToken
            if context.coordinator.loadedOnce {
                webView.reload()
            } else {
                context.coordinator.loadedOnce = true
                webView.load(URLRequest(url: url))
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        weak var webView: WKWebView?
        var lastToken = UUID()
        var loadedOnce = false

        init(_ parent: WebView) {
            self.parent = parent
            self.lastToken = parent.reloadToken
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func handleAction(_ note: Notification) {
            guard let action = note.object as? BrowserAction, let webView else { return }
            switch action {
            case .goBack: if webView.canGoBack { webView.goBack() }
            case .goForward: if webView.canGoForward { webView.goForward() }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            update(webView, loading: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            update(webView, loading: false)
            let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let current = webView.url?.absoluteString ?? ""
            DispatchQueue.main.async {
                self.parent.pageTitle = title.isEmpty ? current : title
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            update(webView, loading: false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            update(webView, loading: false)
        }

        private func update(_ webView: WKWebView, loading: Bool) {
            DispatchQueue.main.async {
                self.parent.isLoading = loading
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }
        }
    }
}
