import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var webSocketManager = WebSocketManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var serverURL = BridgeAuthStore.activeWebSocketURL()?.absoluteString ?? ""
    @State private var userInput = ""
    @State private var isDarkMode = false
    @State private var showProjectMenu = false
    @State private var showFileSelector = false
    @State private var showImagePicker = false
    @State private var selectedImages: [UIImage] = []
    @State private var selectedOptions: Set<String> = []
    @State private var isDropTargeted = false
    @State private var zoomedImageURL: URL? = nil
    @State private var imageCache: [URL: UIImage] = [:]
    @State private var showMainPage = false
    @State private var showSettings = false
    @State private var normalPromptItems: [PromptItem] = []
    @State private var draggingPrompt: PromptItem? = nil
    @StateObject private var speechManager = SpeechRecognitionManager()

    private var theme: IterateTheme { isDarkMode ? .dark : .light }
    private var currentMessage: MCPMessage? { webSocketManager.mcpMessages.first }
    private var currentRequest: MCPRequest? { currentMessage?.payload?.request }
    private var hasOptions: Bool { !(currentRequest?.predefinedOptions ?? []).isEmpty }
    private var promptSyncToken: String {
        guard let prompts = webSocketManager.customPrompts?.prompts else { return "" }
        return prompts.map {
            "\($0.id):\($0.name):\($0.type ?? "normal"):\($0.content)"
        }.joined(separator: "||")
    }

    private var orderedSelectedOptions: [String] {
        guard let options = currentRequest?.predefinedOptions else {
            return Array(selectedOptions)
        }
        return options.filter { selectedOptions.contains($0) }
    }

    private var connectionStatus: String {
        if webSocketManager.isConnecting {
            return "正在连接"
        }
        if webSocketManager.isWaitingForReply {
            return "已发送"
        }
        if webSocketManager.isReconnecting {
            return "重连中"
        }
        return webSocketManager.isConnected ? "已连接" : "连接已断开"
    }

    private var statusDotColor: Color {
        if webSocketManager.isConnecting {
            return theme.warning
        }
        if webSocketManager.isWaitingForReply {
            return .blue  // 已发送用蓝色
        }
        if webSocketManager.isReconnecting {
            return .orange  // 重连中用橙色
        }
        return webSocketManager.isConnected ? theme.success : theme.error
    }

    private var projectName: String {
        if let path = currentRequest?.projectPath, !path.isEmpty {
            return path.split(separator: "/").last.map(String.init) ?? path
        }
        return "等待中"
    }

    private var requestStatusText: String {
        guard let request = currentRequest else { return "等待中" }
        let source = request.mcpHostLabel ?? request.mcpHostId ?? "未知 MCP Host"
        let task = request.taskDisplayName ?? request.taskId ?? "未提供任务标识"
        let waiting = request.deadline.map { "截止：\($0)" } ?? "原始 Host 正在等待"
        return "来源：\(source) · 任务：\(task) · \(waiting)"
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                if showMainPage {
                    InlineWebView(serverURL: serverURL)
                } else {
                    GeometryReader { geo in
                        HStack(alignment: .top, spacing: 8) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    if let messageText = currentRequest?.message {
                                        messageCard(messageText: messageText)
                                        inputSection
                                    } else {
                                        emptyState
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                            }
                            .scrollDismissesKeyboard(.immediately)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                            if !webSocketManager.timelineNodes.isEmpty {
                                TimelineDotBar(
                                    nodes: webSocketManager.timelineNodes,
                                    currentNodeId: webSocketManager.currentTimelineNodeId,
                                    theme: theme,
                                    onDotTap: { content in
                                        userInput = stripAutoPrompt(content)
                                    }
                                )
                                .frame(height: geo.size.height, alignment: .top)
                                .padding(.trailing, 8)
                            }
                        }
                    }

                    if currentMessage != nil {
                        footerBar
                    }
                }
            }

            // 全屏图片预览 overlay
            if let imageURL = zoomedImageURL {
                ImageOverlayView(url: imageURL, theme: theme, cachedImage: imageCache[imageURL], onImageCached: { url, image in
                    imageCache[url] = image
                    // 缓存淘汰：最多保留 10 张
                    if imageCache.count > 10 {
                        if let firstKey = imageCache.keys.first(where: { $0 != url }) {
                            imageCache.removeValue(forKey: firstKey)
                        }
                    }
                }) {
                    zoomedImageURL = nil
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: zoomedImageURL != nil)
                .zIndex(100)
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onAppear {
            if !serverURL.isEmpty {
                webSocketManager.connect(to: serverURL)
            }
            syncNormalPromptItems()
            speechManager.requestAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowLatestMessage"))) { notification in
            // 点击通知后，关闭所有弹出的 sheet 并刷新状态
            showProjectMenu = false
            showFileSelector = false
            showImagePicker = false
            
            // 如果有项目路径信息，更新当前项目
            if let projectPath = notification.object as? String {
                print("[通知点击] 设置项目路径: \(projectPath)")
                // 这里可以添加切换到指定项目的逻辑
                // 例如：webSocketManager.switchToProject(projectPath)
            } else {
                webSocketManager.requestSync()
            }
            print("[通知点击] 已关闭所有弹窗并刷新状态")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("APNsMessageReceived"))) { _ in
            webSocketManager.requestSync()
            print("[APNs] 收到远程推送，触发同步")
        }
        .onReceive(NotificationCenter.default.publisher(for: BridgePairingLinkRouter.notification)) { notification in
            guard let url = notification.object as? URL else { return }
            webSocketManager.importPairingLink(url.absoluteString) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let message):
                        if let pairedURL = self.webSocketManager.bridgeWebSocketURL() {
                            self.serverURL = pairedURL
                        }
                        self.webSocketManager.addMessage(message)
                    case .failure(let error):
                        self.webSocketManager.addMessage("安全配对失败: \(error.localizedDescription)")
                    }
                }
            }
        }
        .onChange(of: currentMessage?.id ?? "") { _ in
            resetInputState()
            // 收到新 MCP 消息时自动退出主页面 WebView
            if showMainPage {
                showMainPage = false
            }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                webSocketManager.handleAppDidBecomeActive()
                BackgroundAudioService.shared.stopBackgroundAudio()
                print("[生命周期] 回到前台，停止后台音频")
            case .inactive, .background:
                webSocketManager.handleAppWillResignActive()
                BackgroundAudioService.shared.startBackgroundAudio()
                print("[生命周期] 进入后台，启动后台音频保活")
            @unknown default:
                break
            }
        }
        .onChange(of: userInput) { newValue in
            if newValue.hasSuffix("@") || newValue.hasSuffix("爱特") {
                showFileSelector = true
            }
        }
        .onChange(of: promptSyncToken) { _ in
            syncNormalPromptItems()
        }
        .sheet(isPresented: $showProjectMenu) {
            ProjectMenuView(webSocketManager: webSocketManager, isPresented: $showProjectMenu)
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .sheet(isPresented: $showFileSelector) {
            FileSelectorView(
                webSocketManager: webSocketManager,
                isPresented: $showFileSelector,
                userInput: $userInput
            )
            .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImages: $selectedImages)
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(serverURL: $serverURL, webSocketManager: webSocketManager)
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }

    private func restartTunnel() {
        // 从 WebSocket URL 推导 HTTP base URL
        var httpBase = serverURL
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")
        if httpBase.hasSuffix("/ws") {
            httpBase = String(httpBase.dropLast(3))
        }
        
        guard let url = URL(string: httpBase + "/api/restart-tunnel") else { return }
        var request = webSocketManager.authorizedRequest(for: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        
        webSocketManager.addMessage("正在重启 Tunnel...")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.webSocketManager.addMessage("重启 Tunnel 失败: \(error.localizedDescription)")
                } else {
                    self.webSocketManager.addMessage("Tunnel 重启指令已发送，等待恢复...")
                    // 5秒后尝试重连 WebSocket
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        self.webSocketManager.connect(to: self.serverURL)
                    }
                }
            }
        }.resume()
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Button(action: { showProjectMenu = true }) {
                HStack(spacing: 8) {
                    Text("∞")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(theme.logo)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(projectName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(theme.text)
                            .lineLimit(1)
                        Text(requestStatusText)
                            .font(.system(size: 10))
                            .foregroundColor(theme.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .layoutPriority(0)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                CircleIconButton(
                    systemName: showMainPage ? "message.fill" : "house.fill",
                    theme: theme,
                    action: {
                        showMainPage.toggle()
                    }
                )

                CircleIconButton(
                    systemName: webSocketManager.preventSleepEnabled ? "cup.and.saucer.fill" : "cup.and.saucer",
                    theme: theme,
                    action: { webSocketManager.togglePreventSleep() }
                )
                
                CircleIconButton(
                    systemName: webSocketManager.notificationsEnabled ? "bell.fill" : "bell.slash",
                    theme: theme,
                    action: { webSocketManager.notificationsEnabled.toggle() }
                )

                CircleIconButton(
                    systemName: isDarkMode ? "sun.max.fill" : "moon.fill",
                    theme: theme,
                    action: { isDarkMode.toggle() }
                )

                CircleIconButton(
                    systemName: "gearshape.fill",
                    theme: theme,
                    action: { showSettings = true }
                )

                Button(action: { restartTunnel() }) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 8, height: 8)
                        Text(connectionStatus)
                            .font(.system(size: 12))
                            .foregroundColor(theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(theme.background)
        .overlay(
            Rectangle()
                .fill(theme.border)
                .frame(height: 2),
            alignment: .bottom
        )
    }

    private func messageCard(messageText: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MarkdownView(text: messageText, theme: theme, onImageTap: { url in
                zoomedImageURL = url
            })

            Divider()
                .background(theme.border)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    DropUploadButton(
                        title: "上传图片",
                        theme: theme,
                        isTargeted: $isDropTargeted,
                        onTap: { showImagePicker = true },
                        onDrop: handleImageDrop
                    )

                    BridgeActionButton(
                        title: "@文件",
                        systemImage: "plus.circle",
                        theme: theme,
                        action: { showFileSelector = true }
                    )

                    BridgeActionButton(
                        title: "复制原文",
                        systemImage: "doc.on.doc",
                        theme: theme,
                        action: { UIPasteboard.general.string = preprocessQuoteContent(messageText) }
                    )

                    BridgeActionButton(
                        title: "引用原文",
                        systemImage: "text.quote",
                        theme: theme,
                        action: { userInput = preprocessQuoteContent(messageText) }
                    )
                }
            }
        }
        .padding(16)
        .background(theme.card)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.accent.opacity(0.3), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("当前没有待处理的 MCP 请求")
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondary)
            Button(action: { webSocketManager.requestSync() }) {
                Text("重新尝试同步")
                    .font(.system(size: 12))
                    .foregroundColor(theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !selectedImages.isEmpty {
                ImagePreviewGrid(images: $selectedImages, theme: theme)
            }

            BridgeTextEditor(
                text: $userInput,
                placeholder: inputPlaceholder,
                theme: theme,
                onPasteImage: appendImage
            )
            .onChange(of: speechManager.transcript) { newValue in
                if !newValue.isEmpty {
                    userInput = newValue
                }
            }

            VStack(spacing: 8) {
                Text(speechManager.isRecording ? "再次点击以完成" : "点击开始语音输入")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textSecondary)

                VoiceInputButton(
                    isRecording: speechManager.isRecording,
                    theme: theme,
                    action: {
                        if !speechManager.isAuthorized {
                            speechManager.requestAuthorization()
                            return
                        }
                        speechManager.toggleRecording()
                    }
                )
            }
            .frame(maxWidth: .infinity)

            if hasOptions {
                SectionTitle(text: "预定义选项", theme: theme)

                VStack(spacing: 8) {
                    ForEach(currentRequest?.predefinedOptions ?? [], id: \.self) { option in
                        OptionRow(
                            option: option,
                            isSelected: selectedOptions.contains(option),
                            theme: theme,
                            action: { toggleOption(option) }
                        )
                    }
                }
            }

            if let prompts = webSocketManager.customPrompts?.prompts {
                let conditionalPrompts = prompts.filter { $0.type == "conditional" }

                if !normalPromptItems.isEmpty {
                    SectionTitle(text: "快捷模板", theme: theme)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(normalPromptItems) { prompt in
                                PromptChip(
                                    title: prompt.name,
                                    theme: theme,
                                    action: { userInput = prompt.content }
                                )
                                .opacity(draggingPrompt?.id == prompt.id ? 0.4 : 1)
                                .onDrag {
                                    draggingPrompt = prompt
                                    return NSItemProvider(object: prompt.id as NSString)
                                }
                                .onDrop(
                                    of: [UTType.plainText.identifier],
                                    delegate: PromptReorderDropDelegate(
                                        destination: prompt,
                                        items: $normalPromptItems,
                                        draggedItem: $draggingPrompt,
                                        onDropCompleted: persistPromptOrderIfNeeded
                                    )
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !conditionalPrompts.isEmpty {
                    SectionTitle(text: "上下文追加", theme: theme)

                    VStack(spacing: 8) {
                        ForEach(conditionalPrompts) { prompt in
                            ConditionalToggleRow(
                                prompt: prompt,
                                webSocketManager: webSocketManager,
                                theme: theme
                            )
                        }
                    }
                }
            }
        }
    }

    private var inputPlaceholder: String {
        if let placeholder = currentRequest?.inputPlaceholder, !placeholder.isEmpty {
            return placeholder
        }
        if hasOptions {
            return "您可以在这里添加补充说明... (支持粘贴图片)"
        }
        return "请输入您的回复... (支持粘贴图片)"
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            BridgeSecondaryButton(title: "继续", theme: theme, action: handleContinue)
            BridgePrimaryButton(title: "确认", theme: theme, action: handleSubmit)
        }
        .padding(16)
        .background(theme.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(theme.border)
                .frame(height: 2),
            alignment: .top
        )
    }

    private func toggleOption(_ option: String) {
        if selectedOptions.contains(option) {
            selectedOptions.remove(option)
        } else {
            selectedOptions.insert(option)
        }
    }

    private func appendImage(_ image: UIImage) {
        if !selectedImages.contains(where: { $0.pngData() == image.pngData() }) {
            selectedImages.append(image)
        }
    }

    private func syncNormalPromptItems() {
        let prompts = webSocketManager.customPrompts?.prompts ?? []
        normalPromptItems = prompts.filter { $0.type == nil || $0.type == "normal" }
    }

    private func persistPromptOrderIfNeeded() {
        let newPromptIds = normalPromptItems.map { $0.id }
        guard !newPromptIds.isEmpty else {
            draggingPrompt = nil
            return
        }

        let currentPromptIds = (webSocketManager.customPrompts?.prompts ?? [])
            .filter { $0.type == nil || $0.type == "normal" }
            .map { $0.id }

        guard newPromptIds != currentPromptIds else {
            draggingPrompt = nil
            return
        }

        webSocketManager.updateCustomPromptOrder(promptIds: newPromptIds)
        draggingPrompt = nil
    }

    private func handleImageDrop(providers: [NSItemProvider]) -> Bool {
        let supportedProviders = providers.filter { $0.canLoadObject(ofClass: UIImage.self) }
        guard !supportedProviders.isEmpty else { return false }

        for provider in supportedProviders {
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        appendImage(image)
                    }
                }
            }
        }
        return true
    }

    private func handleContinue() {
        speechManager.stopRecording()
        guard currentMessage != nil else { return }
        let projectPath = currentRequest?.projectPath

        // 主页面 tab 切换：拦截选项并发送 request_main_page
        if projectPath == "main_page" {
            let selected = orderedSelectedOptions.first ?? ""
            let tabMap: [String: String] = [
                "📋 介绍": "intro",
                "🔧 MCP 工具": "tools",
                "📝 提示词库": "prompts",
                "⚙️ 设置": "settings"
            ]
            if selected == "💬 返回消息" {
                // 返回消息视图：请求同步恢复原始 mcp_state
                webSocketManager.requestSync(projectPath: nil)
                selectedOptions = []
                return
            }
            if let tab = tabMap[selected] {
                webSocketManager.requestMainPage(tab: tab)
                selectedOptions = []
                return
            }
        }

        webSocketManager.sendAction(
            "continue",
            userInput: userInput,
            selectedOptions: orderedSelectedOptions,
            projectPath: projectPath,
            requestId: currentRequest?.requestId,
            invocationId: currentRequest?.invocationId,
            stateRevision: currentRequest?.stateRevision
        )
        selectedImages = []
    }

    private func handleSubmit() {
        speechManager.stopRecording()
        guard let lastMessage = currentMessage else { return }
        let finalInput = userInput + generateConditionalContent()
        webSocketManager.sendResponse(
            text: finalInput,
            images: selectedImages,
            selectedOptions: orderedSelectedOptions,
            forMessage: lastMessage
        )
        resetInputState()
    }

    private func resetInputState() {
        userInput = ""
        selectedImages = []
        selectedOptions = []
    }

    private func preprocessQuoteContent(_ content: String) -> String {
        var processedContent = content
        let markersToRemove = [
            "### BEGIN RESPONSE ###",
            "Here is an enhanced version of the original instruction that is more specific and clear:",
            "<augment-enhanced-prompt>",
            "</augment-enhanced-prompt>",
            "### END RESPONSE ###"
        ]
        for marker in markersToRemove {
            processedContent = processedContent.replacingOccurrences(of: marker, with: "")
        }
        while processedContent.contains("\n\n\n") {
            processedContent = processedContent.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return processedContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func generateConditionalContent() -> String {
        guard let prompts = webSocketManager.customPrompts?.prompts else { return "" }
        let conditionalPrompts = prompts.filter { $0.type == "conditional" }
        var contents: [String] = []

        for prompt in conditionalPrompts {
            if prompt.isActive == false {
                continue
            }
            let isEnabled = prompt.currentState ?? false
            let template = isEnabled ? prompt.templateTrue : prompt.templateFalse
            if let template, !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                contents.append(template.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        if contents.isEmpty {
            return ""
        }
        return "\n\n" + contents.joined(separator: "\n")
    }
}

struct CircleIconButton: View {
    let systemName: String
    let theme: IterateTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.text)
                .frame(width: 32, height: 32)
                .background(theme.card)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct DropUploadButton: View {
    let title: String
    let theme: IterateTheme
    @Binding var isTargeted: Bool
    let onTap: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("ID")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(theme.activeText)
                .frame(width: 22, height: 22)
                .background(theme.activeBackground)
                .cornerRadius(6)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.background)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isTargeted ? theme.accent : theme.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(perform: onTap)
        .onDrop(of: ["public.image"], isTargeted: $isTargeted, perform: onDrop)
    }
}

struct BridgeActionButton: View {
    let title: String
    let systemImage: String
    let theme: IterateTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundColor(theme.text)
            .background(theme.background)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct VoiceInputButton: View {
    let isRecording: Bool
    let theme: IterateTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isRecording ? "mic.fill" : "mic")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(isRecording ? theme.activeText : theme.textSecondary)
                .frame(width: 56, height: 56)
                .background(isRecording ? theme.activeBackground : theme.card)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(isRecording ? theme.activeBackground : theme.border, lineWidth: 1.5)
                )
                .shadow(color: isRecording ? theme.activeBackground.opacity(0.3) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
    }
}

struct BridgeSecondaryButton: View {
    let title: String
    let theme: IterateTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundColor(theme.text)
                .background(theme.background)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct BridgePrimaryButton: View {
    let title: String
    let theme: IterateTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundColor(theme.activeText)
                .background(theme.activeBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.activeBackground, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct SectionTitle: View {
    let text: String
    let theme: IterateTheme

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(theme.textSecondary)
            .textCase(.uppercase)
            .tracking(1.2)
    }
}

struct OptionRow: View {
    let option: String
    let isSelected: Bool
    let theme: IterateTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(option)
                    .font(.system(size: 14))
                    .foregroundColor(theme.text)
                Spacer()
            }
            .padding(10)
            .background(isSelected ? theme.accent.opacity(0.12) : theme.card)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? theme.accent : theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct PromptChip: View {
    let title: String
    let theme: IterateTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.card)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.borderLight, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct PromptReorderDropDelegate: DropDelegate {
    let destination: PromptItem
    @Binding var items: [PromptItem]
    @Binding var draggedItem: PromptItem?
    let onDropCompleted: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedItem,
              draggedItem.id != destination.id,
              let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == destination.id }),
              fromIndex != toIndex else {
            return
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            items.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggedItem = nil }
        guard draggedItem != nil else { return false }
        onDropCompleted()
        return true
    }
}

struct ConditionalToggleRow: View {
    let prompt: PromptItem
    @ObservedObject var webSocketManager: WebSocketManager
    let theme: IterateTheme
    @State private var isOn: Bool = false
    @State private var isActive: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggleActive) {
                Image(systemName: isActive ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isActive ? theme.success : theme.textSecondary)
            }
            .buttonStyle(.plain)

            Text(prompt.name)
                .font(.system(size: 12))
                .foregroundColor(isActive ? (isOn ? theme.activeBackground : theme.textSecondary) : theme.textSecondary)
                .fontWeight(isActive && isOn ? .semibold : .regular)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: theme.activeBackground))
                .onChange(of: isOn) { newValue in
                    if !isActive {
                        setActive(true)
                    }
                    webSocketManager.updateConditionalState(promptId: prompt.id, newState: newValue)
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.card)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isOn ? theme.activeBackground : theme.border, lineWidth: 1)
        )
        .opacity(isActive ? 1 : 0.6)
        .onAppear {
            isOn = prompt.currentState ?? false
            isActive = prompt.isActive ?? true
        }
        .onChange(of: prompt.currentState ?? false) { newValue in
            isOn = newValue
        }
        .onChange(of: prompt.isActive ?? true) { newValue in
            isActive = newValue
        }
    }

    private func toggleActive() {
        setActive(!isActive)
    }

    private func setActive(_ value: Bool) {
        isActive = value
        webSocketManager.updateConditionalActive(promptId: prompt.id, isActive: value)
    }
}

struct ImagePreviewGrid: View {
    @Binding var images: [UIImage]
    let theme: IterateTheme

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], spacing: 8) {
            ForEach(images.indices, id: \.self) { index in
                ImageThumbnail(image: images[index], theme: theme) {
                    images.remove(at: index)
                }
            }
        }
    }
}

struct ImageThumbnail: View {
    let image: UIImage
    let theme: IterateTheme
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(theme.border, lineWidth: 1)
                )

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .offset(x: 6, y: -6)
        }
    }
}

struct BridgeTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let theme: IterateTheme
    let onPasteImage: (UIImage) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            PasteAwareTextView(text: $text, theme: theme, onPasteImage: onPasteImage)
                .frame(minHeight: 120, maxHeight: 180)

            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
        }
    }
}

struct PasteAwareTextView: UIViewRepresentable {
    @Binding var text: String
    let theme: IterateTheme
    let onPasteImage: (UIImage) -> Void

    func makeUIView(context: Context) -> ImagePasteTextView {
        let textView = ImagePasteTextView()
        textView.onPasteImage = onPasteImage
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.textColor = UIColor(theme.text)
        textView.backgroundColor = UIColor(theme.backgroundSecondary)
        textView.isScrollEnabled = true
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor(theme.border).cgColor
        textView.clipsToBounds = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        return textView
    }

    func updateUIView(_ uiView: ImagePasteTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.textColor = UIColor(theme.text)
        uiView.backgroundColor = UIColor(theme.backgroundSecondary)
        uiView.layer.borderColor = UIColor(theme.border).cgColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}

final class ImagePasteTextView: UITextView {
    var onPasteImage: ((UIImage) -> Void)?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // 当剪贴板有图片或文本时，显示粘贴选项
        if action == #selector(paste(_:)) {
            let pasteboard = UIPasteboard.general
            return pasteboard.hasImages || pasteboard.hasStrings
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        if let images = pasteboard.images, !images.isEmpty {
            images.forEach { onPasteImage?($0) }
            return
        }
        if let image = pasteboard.image {
            onPasteImage?(image)
            return
        }
        super.paste(sender)
    }
}

struct ProjectMenuView: View {
    @ObservedObject var webSocketManager: WebSocketManager
    @Binding var isPresented: Bool
    @State private var projects: [ProjectInfo] = []
    @State private var isLoading = true

    var body: some View {
        NavigationView {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if projects.isEmpty {
                    Text("暂无活跃项目")
                        .foregroundColor(.gray)
                } else {
                    ForEach(projects, id: \.requestId) { project in
                        Button(action: {
                            webSocketManager.switchProject(to: project.projectPath, requestId: project.requestId)
                            isPresented = false
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(project.isCurrent ? .blue : .primary)
                                    if !project.title.isEmpty {
                                        Text(project.title)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    Text(project.projectPath)
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if project.isWaiting {
                                    // 已发送等待回复 - 蓝色圆点
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 8, height: 8)
                                } else if project.isCurrent {
                                    // 当前项目 - 黑色圆点
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("活跃项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { isPresented = false }
                }
            }
        }
        .onAppear {
            fetchProjects()
        }
    }

    func fetchProjects() {
        isLoading = true
        guard let baseURL = webSocketManager.bridgeHTTPBaseURL() else {
            isLoading = false
            return
        }
        guard let url = URL(string: "\(baseURL)/api/active-sessions") else {
            isLoading = false
            return
        }

        URLSession.shared.dataTask(with: webSocketManager.authorizedRequest(for: url)) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let sessions = json["sessions"] as? [[String: Any]] else {
                    return
                }

                let currentRequestId = webSocketManager.mcpMessages.first?.payload?.request?.requestId
                projects = sessions.compactMap { session in
                    guard let requestId = session["request_id"] as? String else { return nil }
                    let projectPath = session["project_path"] as? String ?? "Unknown"
                    let projectName = session["project_name"] as? String ?? projectPath.components(separatedBy: "/").last ?? projectPath
                    let title = session["title"] as? String ?? ""
                    let isWaiting = webSocketManager.projectWaitingStatus[projectPath] ?? false
                    return ProjectInfo(
                        requestId: requestId,
                        name: projectName,
                        projectPath: projectPath,
                        title: title,
                        isCurrent: requestId == currentRequestId,
                        isWaiting: isWaiting
                    )
                }
            }
        }.resume()
    }
}

struct ProjectInfo {
    let requestId: String
    let name: String
    let projectPath: String
    let title: String
    let isCurrent: Bool
    let isWaiting: Bool  // 是否处于"已发送"等待状态
}

struct SettingsView: View {
    @Binding var serverURL: String
    @ObservedObject var webSocketManager: WebSocketManager
    @Environment(\.dismiss) var dismiss
    @State private var pairingLink = ""
    @State private var pairingStatus: String?

    var body: some View {
        NavigationView {
            Form {
                Section("服务器设置") {
                    TextField("WebSocket URL", text: $serverURL)
                        .autocapitalization(.none)

                    Button(webSocketManager.isConnected ? "断开连接" : "连接服务器") {
                        if webSocketManager.isConnected {
                            webSocketManager.disconnect()
                        } else {
                            webSocketManager.connect(to: serverURL)
                        }
                    }
                }

                Section("安全配对") {
                    Text("从桌面端扫描二维码后会自动打开；也可以在这里粘贴配对链接。凭证仅保存在本机钥匙串。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    TextField("iterate://pair?pairing=…", text: $pairingLink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("导入并验证配对") {
                        pairingStatus = "正在验证…"
                        webSocketManager.importPairingLink(pairingLink) { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let message):
                                    if let pairedURL = webSocketManager.bridgeWebSocketURL() {
                                        serverURL = pairedURL
                                    }
                                    pairingLink = ""
                                    pairingStatus = message
                                case .failure(let error):
                                    pairingStatus = "配对失败：\(error.localizedDescription)"
                                }
                            }
                        }
                    }
                    .disabled(pairingLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let pairingStatus {
                        Text(pairingStatus)
                            .font(.footnote)
                            .foregroundColor(pairingStatus.hasPrefix("配对失败") ? .red : .secondary)
                    }
                }

                Section("调试") {
                    Button("发送测试通知") {
                        NotificationManager.shared.sendNotification(title: "测试", body: "测试通知")
                    }

                    Button("清除消息") {
                        webSocketManager.clearMessages()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 文件选择器
struct FileSelectorView: View {
    @ObservedObject var webSocketManager: WebSocketManager
    @Binding var isPresented: Bool
    @Binding var userInput: String
    @State private var files: [String] = []
    @State private var searchText = ""
    @State private var isLoading = true

    var filteredFiles: [String] {
        if searchText.isEmpty {
            return files
        }
        return files.filter { $0.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("搜索文件...", text: $searchText)
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding()

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if filteredFiles.isEmpty {
                    Spacer()
                    Text("未找到文件")
                        .foregroundColor(.gray)
                    Spacer()
                } else {
                    List(filteredFiles, id: \.self) { file in
                        Button(action: {
                            selectFile(file)
                        }) {
                            HStack {
                                Image(systemName: file.hasSuffix("/") ? "folder" : "doc")
                                    .foregroundColor(.gray)
                                Text(file)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
            }
        }
        .onAppear {
            fetchFiles()
        }
    }

    func fetchFiles() {
        guard let projectPath = webSocketManager.mcpMessages.first?.payload?.request?.projectPath else {
            isLoading = false
            return
        }

        guard let baseURL = webSocketManager.bridgeHTTPBaseURL() else {
            isLoading = false
            return
        }
        guard let url = URL(string: "\(baseURL)/files?project_path=\(projectPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else {
            isLoading = false
            return
        }

        URLSession.shared.dataTask(with: webSocketManager.authorizedRequest(for: url)) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let fileList = json["files"] as? [String] else {
                    return
                }
                files = fileList
            }
        }.resume()
    }

    func selectFile(_ file: String) {
        let fileRef = "@\(file)"
        if userInput.isEmpty {
            userInput = fileRef
        } else if userInput.hasSuffix(" ") {
            userInput += fileRef
        } else {
            userInput += " \(fileRef)"
        }
        isPresented = false
    }
}

// MARK: - 图片选择器
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 5
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()

            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                        if let image = image as? UIImage {
                            DispatchQueue.main.async {
                                self?.parent.selectedImages.append(image)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct IterateTheme {
    let background: Color
    let backgroundSecondary: Color
    let card: Color
    let text: Color
    let textSecondary: Color
    let border: Color
    let borderLight: Color
    let activeBackground: Color
    let activeText: Color
    let logo: Color
    let accent: Color
    let success: Color
    let warning: Color
    let error: Color

    static let dark = IterateTheme(
        background: Color(hex: "#000000"),
        backgroundSecondary: Color(hex: "#111111"),
        card: Color(hex: "#1a1a1a"),
        text: Color(hex: "#ffffff"),
        textSecondary: Color(hex: "#9ca3af"),
        border: Color(hex: "#333333"),
        borderLight: Color(hex: "#444444"),
        activeBackground: Color(hex: "#ffffff"),
        activeText: Color(hex: "#000000"),
        logo: Color(hex: "#ffffff"),
        accent: Color(hex: "#3b82f6"),
        success: Color(hex: "#10b981"),
        warning: Color(hex: "#f59e0b"),
        error: Color(hex: "#ef4444")
    )

    static let light = IterateTheme(
        background: Color(hex: "#ffffff"),
        backgroundSecondary: Color(hex: "#f9fafb"),
        card: Color(hex: "#f3f4f6"),
        text: Color(hex: "#1f2937"),
        textSecondary: Color(hex: "#6b7280"),
        border: Color(hex: "#e5e7eb"),
        borderLight: Color(hex: "#d1d5db"),
        activeBackground: Color(hex: "#000000"),
        activeText: Color(hex: "#ffffff"),
        logo: Color(hex: "#000000"),
        accent: Color(hex: "#3b82f6"),
        success: Color(hex: "#10b981"),
        warning: Color(hex: "#f59e0b"),
        error: Color(hex: "#ef4444")
    )
}

struct ImageOverlayView: View {
    let url: URL
    let theme: IterateTheme
    var cachedImage: UIImage? = nil
    var onImageCached: ((URL, UIImage) -> Void)? = nil
    let onClose: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showSaveAlert = false
    @State private var saveMessage = ""
    @State private var loadedImage: UIImage? = nil
    @State private var loadFailed = false
    @State private var downloadTask: URLSessionDataTask? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            Group {
                if let img = loadedImage ?? cachedImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { value in
                                    lastScale = scale
                                    if scale < 1.0 {
                                        withAnimation { scale = 1.0 }
                                        lastScale = 1.0
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                    if scale <= 1.0 {
                                        withAnimation {
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                if scale > 1.0 {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.5
                                    lastScale = 2.5
                                }
                            }
                        }
                } else if loadFailed {
                    VStack {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 40))
                        Text("加载失败")
                            .font(.system(size: 14))
                        Button("重试") {
                            loadFailed = false
                            downloadImage()
                        }
                        .padding(.top, 8)
                        .foregroundColor(theme.accent)
                    }
                    .foregroundColor(.white)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .padding(16)
            .onAppear {
                if loadedImage == nil && cachedImage == nil {
                    downloadImage()
                } else if loadedImage == nil, let cached = cachedImage {
                    loadedImage = cached
                }
            }
            .onDisappear {
                downloadTask?.cancel()
                downloadTask = nil
            }

            // 顶部关闭 + 保存按钮
            VStack {
                HStack {
                    Spacer()
                    if loadedImage != nil {
                        Button(action: saveImage) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Spacer()
            }
        }
        .alert(saveMessage, isPresented: $showSaveAlert) {
            Button("OK") {}
        }
    }

    private func downloadImage() {
        let task = URLSession.shared.dataTask(with: BridgeAuthStore.authorizedRequest(for: url)) { data, _, error in
            DispatchQueue.main.async {
                if let data = data, let img = UIImage(data: data) {
                    loadedImage = img
                    onImageCached?(url, img)
                } else if error != nil || data != nil {
                    loadFailed = true
                }
            }
        }
        downloadTask = task
        task.resume()
    }

    private func saveImage() {
        guard let image = loadedImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        saveMessage = "已保存到相册"
        showSaveAlert = true
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 8:
            a = (int >> 24) & 0xff
            r = (int >> 16) & 0xff
            g = (int >> 8) & 0xff
            b = int & 0xff
        case 6:
            a = 0xff
            r = (int >> 16) & 0xff
            g = (int >> 8) & 0xff
            b = int & 0xff
        default:
            a = 0xff
            r = 0
            g = 0
            b = 0
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - 过滤自动触发的模板文字（与 Rust/TypeScript strip_auto_prompt 保持一致）
func stripAutoPrompt(_ input: String) -> String {
    let exactSentinels = ["<!-- CONTEXT_INJECTION_START -->", "<!-- AUTO_PROMPT_START -->"]
    let lineMarkers = [
        "✔️不明白的地方反问我",
        "✔️继续调用 zhi",
        "✔️请记住",
        "✔继续调用 zhi",
        "快捷触发词",
    ]
    
    // 找精确 sentinel 的最早位置
    var cut: String.Index? = nil
    for sentinel in exactSentinels {
        if let range = input.range(of: sentinel) {
            if cut == nil || range.lowerBound < cut! {
                cut = range.lowerBound
            }
        }
    }
    
    // 找行首 marker 的最早位置
    let lines = input.components(separatedBy: "\n")
    var offset = input.startIndex
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if lineMarkers.contains(where: { trimmed.hasPrefix($0) }) {
            if cut == nil || offset < cut! {
                cut = offset
            }
            break
        }
        // 移动到下一行开头（+1 for \n）
        if let nextIndex = input.index(offset, offsetBy: line.count + 1, limitedBy: input.endIndex) {
            offset = nextIndex
        } else {
            break
        }
    }
    
    if let cutIndex = cut {
        return String(input[..<cutIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return input
}
