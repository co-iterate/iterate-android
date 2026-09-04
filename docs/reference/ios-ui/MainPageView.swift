import SwiftUI
import WebKit
import Foundation
import Speech
import AVFoundation

private let speechMuscleMemoryStorageKey = "speech_muscle_memory_store"
private let speechCorrectionMemoryStorageKey = "speech_correction_memory_store"
private let speechMuscleMemoryScriptHandler = "iterateSpeechMuscleMemory"
private let speechCorrectionMemoryScriptHandler = "iterateSpeechCorrectionMemory"
private let speechTrainingScriptHandler = "iterateSpeechTraining"
private let ghostSuggestionSettingsScriptHandler = "iterateGhostSuggestionSettings"
private let homeRequestScriptHandler = "iterateHomeRequest"

@MainActor
final class WebSpeechTrainer {
    private let config: SpeechRecognitionConfig
    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var pendingCompletion: ((_ transcript: String?, _ error: String?) -> Void)?
    private var lastTranscript = ""
    private var isRecording = false
    private var finalizationWorkItem: DispatchWorkItem?
    private var hasInputTap = false

    init(config: SpeechRecognitionConfig = .standard) {
        self.config = config
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: config.localeIdentifier))
    }

    func startRecording(
        contextualStrings: [String],
        completion: @escaping (_ error: String?) -> Void
    ) {
        guard pendingCompletion == nil else {
            completion("已有一段训练录音正在进行")
            return
        }
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { [weak self] newStatus in
                Task { @MainActor in
                    guard let self else { return }
                    guard newStatus == .authorized else {
                        completion("语音识别权限未开启")
                        return
                    }
                    self.beginRecognition(
                        contextualStrings: contextualStrings,
                        onStarted: completion
                    )
                }
            }
            return
        }

        guard status == .authorized else {
            completion("语音识别权限未开启")
            return
        }

        beginRecognition(contextualStrings: contextualStrings, onStarted: completion)
    }

    func stopRecording(
        completion: @escaping (_ transcript: String?, _ error: String?) -> Void
    ) {
        guard pendingCompletion != nil else {
            completion(nil, "当前没有正在进行的录音")
            return
        }

        pendingCompletion = completion
        isRecording = false
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        recognitionRequest?.endAudio()

        finalizationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.pendingCompletion != nil else { return }
                if !self.lastTranscript.isEmpty {
                    self.finishRecognition(transcript: self.lastTranscript, error: nil)
                } else {
                    self.finishRecognition(transcript: nil, error: "No speech detected")
                }
            }
        }
        finalizationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + config.finalizationGracePeriod, execute: workItem)
    }

    private func beginRecognition(
        contextualStrings: [String],
        onStarted: @escaping (_ error: String?) -> Void
    ) {
        resetRecognition()

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            onStarted("语音识别当前不可用")
            return
        }

        lastTranscript = ""
        isRecording = true

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setPreferredIOBufferDuration(config.preferredIOBufferDuration)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            onStarted("音频会话配置失败")
            return
        }

        pendingCompletion = { _, _ in }

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        if #available(iOS 13, *), config.prefersOnDeviceRecognition, speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        if !contextualStrings.isEmpty {
            recognitionRequest.contextualStrings = Array(contextualStrings.prefix(config.contextualStringsLimit))
        }
        if #available(iOS 16, *) {
            recognitionRequest.addsPunctuation = config.addsPunctuation
        }
        self.recognitionRequest = recognitionRequest

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        if hasInputTap {
            inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        inputNode.installTap(onBus: 0, bufferSize: config.audioBufferSize, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        hasInputTap = true

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.lastTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finishRecognition(transcript: self.lastTranscript, error: nil)
                        return
                    }
                }

                if let error {
                    let message = self.lastTranscript.isEmpty ? error.localizedDescription : nil
                    self.finishRecognition(
                        transcript: self.lastTranscript.isEmpty ? nil : self.lastTranscript,
                        error: message
                    )
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            onStarted(nil)
        } catch {
            resetRecognition()
            onStarted("音频引擎启动失败")
        }
    }

    private func finishRecognition(transcript: String?, error: String?) {
        let completion = pendingCompletion
        pendingCompletion = nil
        finalizationWorkItem?.cancel()
        finalizationWorkItem = nil
        resetRecognition()
        completion?(transcript, error)
    }

    private func resetRecognition() {
        isRecording = false
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

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
                        loadError: $loadError,
                        onGhostSuggestionSettingsRequested: nil
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
    let onGhostSuggestionSettingsRequested: (() -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: speechMuscleMemoryScriptHandler)
        contentController.add(context.coordinator, name: speechCorrectionMemoryScriptHandler)
        contentController.add(context.coordinator, name: speechTrainingScriptHandler)
        contentController.add(context.coordinator, name: ghostSuggestionSettingsScriptHandler)
        contentController.add(context.coordinator, name: homeRequestScriptHandler)
        let bridgeScript = WKUserScript(
            source: """
            window.__iterateSpeechMuscleMemoryPending = {};
            window.__iterateSpeechMuscleMemoryReceive = function(payload) {
              if (!payload || !payload.requestId) return;
              const pending = window.__iterateSpeechMuscleMemoryPending[payload.requestId];
              if (!pending) return;
              delete window.__iterateSpeechMuscleMemoryPending[payload.requestId];
              if (payload.error) {
                pending.reject(payload.error);
              } else {
                pending.resolve(payload.entries || []);
              }
            };
            window.iterateSpeechMuscleMemory = {
              available: true,
              getEntries: function() {
                return new Promise(function(resolve, reject) {
                  const requestId = 'get-' + Date.now() + '-' + Math.random().toString(36).slice(2);
                  window.__iterateSpeechMuscleMemoryPending[requestId] = { resolve: resolve, reject: reject };
                  window.webkit.messageHandlers.\(speechMuscleMemoryScriptHandler).postMessage({
                    action: 'getEntries',
                    requestId: requestId
                  });
                });
              },
              saveEntries: function(entries) {
                return new Promise(function(resolve, reject) {
                  const requestId = 'save-' + Date.now() + '-' + Math.random().toString(36).slice(2);
                  window.__iterateSpeechMuscleMemoryPending[requestId] = { resolve: resolve, reject: reject };
                  window.webkit.messageHandlers.\(speechMuscleMemoryScriptHandler).postMessage({
                    action: 'saveEntries',
                    requestId: requestId,
                    entries: Array.isArray(entries) ? entries : []
                  });
                });
              }
            };
            window.__iterateSpeechCorrectionMemoryPending = {};
            window.__iterateSpeechCorrectionMemoryReceive = function(payload) {
              if (!payload || !payload.requestId) return;
              const pending = window.__iterateSpeechCorrectionMemoryPending[payload.requestId];
              if (!pending) return;
              delete window.__iterateSpeechCorrectionMemoryPending[payload.requestId];
              if (payload.error) {
                pending.reject(payload.error);
              } else {
                pending.resolve(payload.entries || []);
              }
            };
            window.iterateSpeechCorrectionMemory = {
              available: true,
              getEntries: function() {
                return new Promise(function(resolve, reject) {
                  const requestId = 'correction-get-' + Date.now() + '-' + Math.random().toString(36).slice(2);
                  window.__iterateSpeechCorrectionMemoryPending[requestId] = { resolve: resolve, reject: reject };
                  window.webkit.messageHandlers.\(speechCorrectionMemoryScriptHandler).postMessage({
                    action: 'getEntries',
                    requestId: requestId
                  });
                });
              },
              saveEntries: function(entries) {
                return new Promise(function(resolve, reject) {
                  const requestId = 'correction-save-' + Date.now() + '-' + Math.random().toString(36).slice(2);
                  window.__iterateSpeechCorrectionMemoryPending[requestId] = { resolve: resolve, reject: reject };
                  window.webkit.messageHandlers.\(speechCorrectionMemoryScriptHandler).postMessage({
                    action: 'saveEntries',
                    requestId: requestId,
                    entries: Array.isArray(entries) ? entries : []
                  });
                });
              }
            };
            window.__iterateSpeechTrainingPending = {};
            window.__iterateSpeechTrainingReceive = function(payload) {
              if (!payload || !payload.requestId) return;
              const pending = window.__iterateSpeechTrainingPending[payload.requestId];
              if (!pending) return;
              delete window.__iterateSpeechTrainingPending[payload.requestId];
              if (payload.error) {
                pending.reject(payload.error);
              } else {
                pending.resolve(payload.transcript || '');
              }
            };
            window.iterateSpeechTraining = {
              available: true,
              startRecording: function(contextualStrings) {
                return new Promise(function(resolve, reject) {
                  const requestId = 'train-start-' + Date.now() + '-' + Math.random().toString(36).slice(2);
                  window.__iterateSpeechTrainingPending[requestId] = { resolve: resolve, reject: reject };
                  window.webkit.messageHandlers.\(speechTrainingScriptHandler).postMessage({
                    action: 'startRecording',
                    requestId: requestId,
                    contextualStrings: Array.isArray(contextualStrings) ? contextualStrings : []
                  });
                });
              },
              stopRecording: function() {
                return new Promise(function(resolve, reject) {
                  const requestId = 'train-stop-' + Date.now() + '-' + Math.random().toString(36).slice(2);
                  window.__iterateSpeechTrainingPending[requestId] = { resolve: resolve, reject: reject };
                  window.webkit.messageHandlers.\(speechTrainingScriptHandler).postMessage({
                    action: 'stopRecording',
                    requestId: requestId
                  });
                });
              }
            };
            window.iterateGhostSuggestionSettings = {
              available: true,
              open: function() {
                window.webkit.messageHandlers.\(ghostSuggestionSettingsScriptHandler).postMessage({
                  action: 'open'
                });
              }
            };
            window.__iterateHomeRequestPending = {};
            window.__iterateHomeRequestReceive = function(payload) {
              if (!payload || !payload.requestId) return;
              const pending = window.__iterateHomeRequestPending[payload.requestId];
              if (!pending) return;
              delete window.__iterateHomeRequestPending[payload.requestId];
              clearTimeout(pending.timeout);
              if (payload.error) {
                pending.reject(new Error(payload.error));
                return;
              }
              const body = payload.body || '';
              pending.resolve({
                ok: payload.status >= 200 && payload.status < 300,
                status: payload.status || 0,
                text: function() { return Promise.resolve(body); },
                json: function() {
                  try { return Promise.resolve(body ? JSON.parse(body) : {}); }
                  catch (error) { return Promise.reject(error); }
                }
              });
            };
            window.iterateHomeFetch = function(path, options) {
              options = options || {};
              return new Promise(function(resolve, reject) {
                const requestId = 'home-' + Date.now() + '-' + Math.random().toString(36).slice(2);
                const timeout = setTimeout(function() {
                  delete window.__iterateHomeRequestPending[requestId];
                  reject(new Error('请求超时'));
                }, 20000);
                window.__iterateHomeRequestPending[requestId] = {
                  resolve: resolve,
                  reject: reject,
                  timeout: timeout
                };
                window.webkit.messageHandlers.\(homeRequestScriptHandler).postMessage({
                  action: 'request',
                  requestId: requestId,
                  path: path,
                  method: (options.method || 'GET').toUpperCase(),
                  body: options.body || null
                });
              });
            };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(bridgeScript)
        config.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        context.coordinator.webView = webView

        if let url = URL(string: urlString) {
            webView.load(DeviceAuthStore.authorizedRequest(url: url))
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
        Coordinator(
            authorizedBaseURL: URL(string: urlString),
            isLoading: $isLoading,
            loadError: $loadError,
            onGhostSuggestionSettingsRequested: onGhostSuggestionSettingsRequested
        )
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        @Binding var loadError: String?
        weak var webView: WKWebView?
        private let speechTrainer = WebSpeechTrainer()
        private let authorizedBaseURL: URL?
        private let onGhostSuggestionSettingsRequested: (() -> Void)?

        init(
            authorizedBaseURL: URL?,
            isLoading: Binding<Bool>,
            loadError: Binding<String?>,
            onGhostSuggestionSettingsRequested: (() -> Void)?
        ) {
            self.authorizedBaseURL = authorizedBaseURL
            _isLoading = isLoading
            _loadError = loadError
            self.onGhostSuggestionSettingsRequested = onGhostSuggestionSettingsRequested
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

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let targetURL = navigationAction.request.url,
                  let authorizedBaseURL,
                  targetURL.scheme?.lowercased() == authorizedBaseURL.scheme?.lowercased(),
                  targetURL.host?.lowercased() == authorizedBaseURL.host?.lowercased(),
                  targetURL.port == authorizedBaseURL.port else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

extension WebView.Coordinator: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == ghostSuggestionSettingsScriptHandler {
            Task { @MainActor in
                self.onGhostSuggestionSettingsRequested?()
            }
            return
        }

        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              let requestId = body["requestId"] as? String else {
            return
        }

        if message.name == homeRequestScriptHandler {
            let expectedPort = authorizedBaseURL?.port
                ?? (authorizedBaseURL?.scheme?.lowercased() == "https" ? 443 : 80)
            let originPort = message.frameInfo.securityOrigin.port > 0
                ? message.frameInfo.securityOrigin.port
                : (message.frameInfo.securityOrigin.protocol.lowercased() == "https" ? 443 : 80)
            guard message.frameInfo.isMainFrame,
                  let authorizedBaseURL,
                  let authorizedScheme = authorizedBaseURL.scheme?.lowercased(),
                  let authorizedHost = authorizedBaseURL.host?.lowercased(),
                  message.frameInfo.securityOrigin.protocol.lowercased() == authorizedScheme,
                  message.frameInfo.securityOrigin.host.lowercased() == authorizedHost,
                  originPort == expectedPort else {
                sendHomeResponse(
                    requestId: requestId,
                    status: 0,
                    body: "",
                    error: "拒绝非 iterate 页面调用"
                )
                return
            }
            handleHomeRequest(body: body, requestId: requestId)
            return
        }

        if message.name == speechCorrectionMemoryScriptHandler {
            switch action {
            case "getEntries":
                fetchRemoteSpeechCorrectionMemoryEntries { remoteEntries in
                    if let remoteEntries {
                        _ = self.saveSpeechCorrectionMemoryEntries(remoteEntries)
                        self.sendSpeechCorrectionMemoryResponse(
                            requestId: requestId,
                            entries: remoteEntries,
                            error: nil
                        )
                    } else {
                        let entries = self.loadSpeechCorrectionMemoryEntries()
                        self.sendSpeechCorrectionMemoryResponse(requestId: requestId, entries: entries, error: nil)
                    }
                }
            case "saveEntries":
                let entries = body["entries"] as? [[String: Any]] ?? []
                pushRemoteSpeechCorrectionMemoryEntries(entries) { savedEntries, error in
                    guard let savedEntries, error == nil else {
                        self.sendSpeechCorrectionMemoryResponse(
                            requestId: requestId,
                            entries: [],
                            error: error ?? "远端保存失败"
                        )
                        return
                    }
                    guard self.saveSpeechCorrectionMemoryEntries(savedEntries) else {
                        self.sendSpeechCorrectionMemoryResponse(
                            requestId: requestId,
                            entries: [],
                            error: "远端已保存，但本地缓存失败"
                        )
                        return
                    }
                    self.sendSpeechCorrectionMemoryResponse(
                        requestId: requestId,
                        entries: savedEntries,
                        error: nil
                    )
                }
            default:
                sendSpeechCorrectionMemoryResponse(
                    requestId: requestId,
                    entries: [],
                    error: "未知操作"
                )
            }
            return
        }

        if message.name == speechTrainingScriptHandler {
            switch action {
            case "startRecording":
                let contextualStrings = body["contextualStrings"] as? [String] ?? []
                Task { @MainActor in
                    self.speechTrainer.startRecording(contextualStrings: contextualStrings) { error in
                        self.sendSpeechTrainingResponse(
                            requestId: requestId,
                            transcript: nil,
                            error: error
                        )
                    }
                }
            case "stopRecording":
                Task { @MainActor in
                    self.speechTrainer.stopRecording { transcript, error in
                        self.sendSpeechTrainingResponse(
                            requestId: requestId,
                            transcript: transcript,
                            error: error
                        )
                    }
                }
            default:
                sendSpeechTrainingResponse(
                    requestId: requestId,
                    transcript: nil,
                    error: "未知操作"
                )
            }
            return
        }

        guard message.name == speechMuscleMemoryScriptHandler else { return }

        switch action {
        case "getEntries":
            fetchRemoteSpeechMuscleMemoryEntries { remoteEntries in
                if let remoteEntries {
                    _ = self.saveSpeechMuscleMemoryEntries(remoteEntries)
                    self.sendSpeechMuscleMemoryResponse(
                        requestId: requestId,
                        entries: remoteEntries,
                        error: nil
                    )
                } else {
                    let entries = self.loadSpeechMuscleMemoryEntries()
                    self.sendSpeechMuscleMemoryResponse(requestId: requestId, entries: entries, error: nil)
                }
            }
        case "saveEntries":
            let entries = body["entries"] as? [[String: Any]] ?? []
            pushRemoteSpeechMuscleMemoryEntries(entries) { savedEntries, error in
                guard let savedEntries, error == nil else {
                    self.sendSpeechMuscleMemoryResponse(
                        requestId: requestId,
                        entries: [],
                        error: error ?? "远端保存失败"
                    )
                    return
                }
                guard self.saveSpeechMuscleMemoryEntries(savedEntries) else {
                    self.sendSpeechMuscleMemoryResponse(
                        requestId: requestId,
                        entries: [],
                        error: "远端已保存，但本地缓存失败"
                    )
                    return
                }
                self.sendSpeechMuscleMemoryResponse(
                    requestId: requestId,
                    entries: savedEntries,
                    error: nil
                )
            }
        default:
            sendSpeechMuscleMemoryResponse(
                requestId: requestId,
                entries: [],
                error: "未知操作"
            )
        }
    }

    private func handleHomeRequest(body: [String: Any], requestId: String) {
        guard let rawPath = body["path"] as? String,
              rawPath.hasPrefix("/"),
              !rawPath.hasPrefix("//"),
              let components = URLComponents(string: rawPath),
              components.scheme == nil,
              components.host == nil,
              let baseURL = authorizedBaseURL,
              ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""),
              let targetURL = components.url(relativeTo: baseURL)?.absoluteURL else {
            sendHomeResponse(requestId: requestId, status: 0, body: "", error: "请求地址无效")
            return
        }

        let method = (body["method"] as? String ?? "GET").uppercased()
        let path = components.path
        let allowedRequests: Set<String> = [
            "GET /api/version",
            "GET /api/mcp-tools",
            "POST /api/mcp-tools",
            "GET /api/prompt-library",
            "POST /api/prompt-library",
            "DELETE /api/prompt-library",
            "POST /api/import-prompts-dir",
            "GET /api/config",
            "POST /api/config",
            "GET /api/show-window",
            "GET /api/audio-assets",
            "POST /api/test-audio",
            "GET /api/speech-muscle-memory",
            "POST /api/speech-muscle-memory",
        ]
        guard allowedRequests.contains("\(method) \(path)") else {
            sendHomeResponse(requestId: requestId, status: 0, body: "", error: "请求不在 Home 白名单中")
            return
        }

        guard baseURL.scheme == targetURL.scheme,
              baseURL.host == targetURL.host,
              baseURL.port == targetURL.port else {
            sendHomeResponse(requestId: requestId, status: 0, body: "", error: "拒绝跨站请求")
            return
        }

        var request = DeviceAuthStore.authorizedRequest(url: targetURL)
        request.httpMethod = method
        if let requestBody = body["body"] as? String {
            guard requestBody.utf8.count <= 512 * 1024 else {
                sendHomeResponse(requestId: requestId, status: 0, body: "", error: "请求内容过大")
                return
            }
            request.httpBody = requestBody.data(using: .utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                self?.sendHomeResponse(
                    requestId: requestId,
                    status: 0,
                    body: "",
                    error: error.localizedDescription
                )
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard data?.count ?? 0 <= 2 * 1024 * 1024 else {
                self?.sendHomeResponse(
                    requestId: requestId,
                    status: 0,
                    body: "",
                    error: "响应内容过大"
                )
                return
            }
            let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            _ = DeviceAuthStore.clearAuthIfUnauthorized(
                response: response,
                data: data,
                context: "home_request"
            )
            self?.sendHomeResponse(
                requestId: requestId,
                status: status,
                body: responseBody,
                error: nil
            )
        }.resume()
    }

    private func sendHomeResponse(
        requestId: String,
        status: Int,
        body: String,
        error: String?
    ) {
        var payload: [String: Any] = [
            "requestId": requestId,
            "status": status,
            "body": body,
        ]
        if let error {
            payload["error"] = error
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript("window.__iterateHomeRequestReceive(\(json));")
        }
    }

    private func loadSpeechMuscleMemoryEntries() -> [[String: Any]] {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: speechMuscleMemoryStorageKey),
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json
    }

    private func saveSpeechMuscleMemoryEntries(_ entries: [[String: Any]]) -> Bool {
        guard JSONSerialization.isValidJSONObject(entries),
              let data = try? JSONSerialization.data(withJSONObject: entries),
              let raw = String(data: data, encoding: .utf8) else {
            return false
        }
        UserDefaults.standard.set(raw, forKey: speechMuscleMemoryStorageKey)
        return true
    }

    private func loadSpeechCorrectionMemoryEntries() -> [[String: Any]] {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: speechCorrectionMemoryStorageKey),
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json
    }

    private func saveSpeechCorrectionMemoryEntries(_ entries: [[String: Any]]) -> Bool {
        guard JSONSerialization.isValidJSONObject(entries),
              let data = try? JSONSerialization.data(withJSONObject: entries),
              let raw = String(data: data, encoding: .utf8) else {
            return false
        }
        UserDefaults.standard.set(raw, forKey: speechCorrectionMemoryStorageKey)
        return true
    }

    private func speechMuscleMemoryAPIURL() -> URL? {
        guard let authorizedBaseURL else { return nil }
        guard var components = URLComponents(url: authorizedBaseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/api/speech-muscle-memory"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func speechCorrectionMemoryAPIURL() -> URL? {
        guard let authorizedBaseURL else { return nil }
        guard var components = URLComponents(url: authorizedBaseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/api/speech-correction-memory"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func fetchRemoteSpeechMuscleMemoryEntries(
        completion: @escaping ([[String: Any]]?) -> Void
    ) {
        guard let url = speechMuscleMemoryAPIURL() else {
            completion(nil)
            return
        }

        let request = DeviceAuthStore.authorizedRequest(url: url)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "web_speech_memory_fetch") {
                completion(nil)
                return
            }
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = object["entries"] as? [[String: Any]] else {
                completion(nil)
                return
            }
            completion(entries)
        }.resume()
    }

    private func pushRemoteSpeechMuscleMemoryEntries(
        _ entries: [[String: Any]],
        completion: @escaping ([[String: Any]]?, String?) -> Void
    ) {
        guard let url = speechMuscleMemoryAPIURL(),
              let body = try? JSONSerialization.data(withJSONObject: ["entries": entries]) else {
            completion(nil, "无法创建远端保存请求")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        DeviceAuthStore.applyAuthHeaders(to: &request)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "web_speech_memory_push") {
                completion(nil, "设备授权已失效")
                return
            }
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["ok"] as? Bool == true,
                  let savedEntries = object["entries"] as? [[String: Any]] else {
                completion(nil, error?.localizedDescription ?? "远端保存失败")
                return
            }
            completion(savedEntries, nil)
        }.resume()
    }

    private func fetchRemoteSpeechCorrectionMemoryEntries(
        completion: @escaping ([[String: Any]]?) -> Void
    ) {
        guard let url = speechCorrectionMemoryAPIURL() else {
            completion(nil)
            return
        }

        let request = DeviceAuthStore.authorizedRequest(url: url)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "web_speech_correction_memory_fetch") {
                completion(nil)
                return
            }
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = object["entries"] as? [[String: Any]] else {
                completion(nil)
                return
            }
            completion(entries)
        }.resume()
    }

    private func pushRemoteSpeechCorrectionMemoryEntries(
        _ entries: [[String: Any]],
        completion: @escaping ([[String: Any]]?, String?) -> Void
    ) {
        guard let url = speechCorrectionMemoryAPIURL(),
              let body = try? JSONSerialization.data(withJSONObject: ["entries": entries]) else {
            completion(nil, "无法创建远端保存请求")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        DeviceAuthStore.applyAuthHeaders(to: &request)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "web_speech_correction_memory_push") {
                completion(nil, "设备授权已失效")
                return
            }
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["ok"] as? Bool == true,
                  let savedEntries = object["entries"] as? [[String: Any]] else {
                completion(nil, error?.localizedDescription ?? "远端保存失败")
                return
            }
            completion(savedEntries, nil)
        }.resume()
    }

    private func sendSpeechMuscleMemoryResponse(
        requestId: String,
        entries: [[String: Any]],
        error: String?
    ) {
        guard let webView else { return }
        let payload: [String: Any] = [
            "requestId": requestId,
            "entries": entries,
            "error": error as Any
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        let script = "window.__iterateSpeechMuscleMemoryReceive(\(json));"
        DispatchQueue.main.async {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func sendSpeechCorrectionMemoryResponse(
        requestId: String,
        entries: [[String: Any]],
        error: String?
    ) {
        guard let webView else { return }
        let payload: [String: Any] = [
            "requestId": requestId,
            "entries": entries,
            "error": error as Any
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        let script = "window.__iterateSpeechCorrectionMemoryReceive(\(json));"
        DispatchQueue.main.async {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func sendSpeechTrainingResponse(
        requestId: String,
        transcript: String?,
        error: String?
    ) {
        guard let webView else { return }
        let payload: [String: Any] = [
            "requestId": requestId,
            "transcript": transcript ?? "",
            "error": error as Any
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        let script = "window.__iterateSpeechTrainingReceive(\(json));"
        DispatchQueue.main.async {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

/// Inline WebView for embedding directly in ContentView (no sheet)
struct InlineWebView: View {
    let serverURL: String
    let onGhostSuggestionSettingsRequested: (() -> Void)?
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
            Color.white.ignoresSafeArea()

            if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundColor(.gray)
                    Text("加载失败")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.12, green: 0.16, blue: 0.22))
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
                    loadError: $loadError,
                    onGhostSuggestionSettingsRequested: onGhostSuggestionSettingsRequested
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
