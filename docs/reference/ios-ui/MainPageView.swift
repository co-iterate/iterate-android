import SwiftUI
import WebKit

struct MainPageView: View {
    let serverURL: String
    let theme: IterateTheme
    @Environment(\.dismiss) var dismiss
    @State private var isLoading = true
    @State private var loadError: String? = nil

    private var mobileURL: String {
        // Convert ws://host:port/ws → http://host:port/mobile
        var url = serverURL
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")
        // Remove /ws path if present
        if url.hasSuffix("/ws") {
            url = String(url.dropLast(3))
        }
        return url + "/mobile"
    }

    var body: some View {
        NavigationView {
            ZStack {
                theme.background.ignoresSafeArea()

                if let error = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 40))
                            .foregroundColor(theme.textSecondary)
                        Text("加载失败")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(theme.text)
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(theme.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("重试") {
                            loadError = nil
                            isLoading = true
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.accent)
                        .padding(.top, 8)
                    }
                    .padding()
                } else {
                    WebView(
                        urlString: mobileURL,
                        isLoading: $isLoading,
                        loadError: $loadError
                    )
                    .ignoresSafeArea(edges: .bottom)

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: theme.accent))
                            .scaleEffect(1.2)
                    }
                }
            }
            .navigationTitle("iterate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct WebView: UIViewRepresentable {
    let urlString: String
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)
        webView.scrollView.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)

        if let url = URL(string: urlString) {
            let request = BridgeAuthStore.authorizedRequest(for: url)
            if let cookie = BridgeAuthStore.cookie(for: url) {
                config.websiteDataStore.httpCookieStore.setCookie(cookie) {
                    webView.load(request)
                }
            } else {
                webView.load(request)
            }
        } else {
            DispatchQueue.main.async {
                self.loadError = "无效的 URL: \(urlString)"
                self.isLoading = false
            }
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, loadError: $loadError)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        @Binding var loadError: String?

        init(isLoading: Binding<Bool>, loadError: Binding<String?>) {
            _isLoading = isLoading
            _loadError = loadError
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.loadError = error.localizedDescription
                self.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.loadError = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

/// Inline WebView for embedding directly in ContentView (no sheet)
struct InlineWebView: View {
    let serverURL: String
    @State private var isLoading = true
    @State private var loadError: String? = nil

    private var mobileURL: String {
        var url = serverURL
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")
        if url.hasSuffix("/ws") {
            url = String(url.dropLast(3))
        }
        return url + "/mobile"
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.04).ignoresSafeArea()

            if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundColor(.gray)
                    Text("加载失败")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        loadError = nil
                        isLoading = true
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.06, green: 0.73, blue: 0.51))
                    .padding(.top, 6)
                }
                .padding()
            } else {
                WebView(
                    urlString: mobileURL,
                    isLoading: $isLoading,
                    loadError: $loadError
                )

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.06, green: 0.73, blue: 0.51)))
                        .scaleEffect(1.2)
                }
            }
        }
    }
}
