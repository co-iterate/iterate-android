import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import WatchConnectivity
import CryptoKit
import QuartzCore

enum StableReorderAxis {
    case horizontal
    case vertical
}

struct StableLongPressReorderSession {
    var sourceID: String?
    var targetID: String?
    var startLocation: CGPoint = .zero
    var translation: CGSize = .zero
    var hasCrossedMovementThreshold = false
    var suppressedTapID: String?

    var isActive: Bool {
        sourceID != nil
    }

    mutating func begin(id: String, at location: CGPoint) {
        sourceID = id
        targetID = id
        startLocation = location
        translation = .zero
        hasCrossedMovementThreshold = false
        suppressedTapID = id
    }

    @discardableResult
    mutating func update(to location: CGPoint, movementThreshold: CGFloat = 6) -> Bool {
        let delta = CGSize(
            width: location.x - startLocation.x,
            height: location.y - startLocation.y
        )
        let crossedThreshold = hypot(delta.width, delta.height) >= movementThreshold
        guard hasCrossedMovementThreshold || crossedThreshold else { return false }

        let didBeginMoving = !hasCrossedMovementThreshold
        hasCrossedMovementThreshold = true
        translation = delta
        return didBeginMoving
    }

    mutating func reset(keepTapSuppression: Bool = false) {
        let tapID = keepTapSuppression ? (sourceID ?? suppressedTapID) : nil
        sourceID = nil
        targetID = nil
        startLocation = .zero
        translation = .zero
        hasCrossedMovementThreshold = false
        suppressedTapID = tapID
    }
}

struct StableReorderItemFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct LongPressReorderGestureBridge: UIViewRepresentable {
    let isEnabled: Bool
    var minimumPressDuration: TimeInterval = 0.42
    var allowableMovement: CGFloat = 14
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.coordinator = context.coordinator
        context.coordinator.update(
            isEnabled: isEnabled,
            minimumPressDuration: minimumPressDuration,
            allowableMovement: allowableMovement,
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded
        )
        return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {
        uiView.coordinator = context.coordinator
        context.coordinator.update(
            isEnabled: isEnabled,
            minimumPressDuration: minimumPressDuration,
            allowableMovement: allowableMovement,
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded
        )
        context.coordinator.attach(from: uiView)
    }

    static func dismantleUIView(_ uiView: InstallerView, coordinator: Coordinator) {
        coordinator.detach()
        uiView.coordinator = nil
    }

    final class InstallerView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(from: self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            coordinator?.attach(from: self)
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            false
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var scrollView: UIScrollView?
        private var recognizer: UILongPressGestureRecognizer?
        private var isEnabled = true
        private var minimumPressDuration: TimeInterval = 0.42
        private var allowableMovement: CGFloat = 14
        private var onBegan: (CGPoint) -> Void = { _ in }
        private var onChanged: (CGPoint) -> Void = { _ in }
        private var onEnded: (Bool) -> Void = { _ in }

        func update(
            isEnabled: Bool,
            minimumPressDuration: TimeInterval,
            allowableMovement: CGFloat,
            onBegan: @escaping (CGPoint) -> Void,
            onChanged: @escaping (CGPoint) -> Void,
            onEnded: @escaping (Bool) -> Void
        ) {
            self.isEnabled = isEnabled
            self.minimumPressDuration = minimumPressDuration
            self.allowableMovement = allowableMovement
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            recognizer?.minimumPressDuration = minimumPressDuration
            recognizer?.allowableMovement = allowableMovement
            recognizer?.isEnabled = isEnabled
        }

        func attach(from view: UIView) {
            var ancestor = view.superview
            while let current = ancestor, !(current is UIScrollView) {
                ancestor = current.superview
            }
            guard let nextScrollView = ancestor as? UIScrollView else { return }
            guard scrollView !== nextScrollView else { return }

            detach()
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = minimumPressDuration
            longPress.allowableMovement = allowableMovement
            longPress.cancelsTouchesInView = false
            longPress.delaysTouchesBegan = false
            longPress.delaysTouchesEnded = false
            longPress.delegate = self
            longPress.isEnabled = isEnabled
            nextScrollView.addGestureRecognizer(longPress)
            scrollView = nextScrollView
            recognizer = longPress
        }

        func detach() {
            if let recognizer {
                scrollView?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            scrollView = nil
        }

        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            let location = recognizer.location(in: recognizer.view?.window)
            switch recognizer.state {
            case .began:
                onBegan(location)
            case .changed:
                onChanged(location)
            case .ended:
                onEnded(false)
            case .cancelled, .failed:
                onEnded(true)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            isEnabled
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

func stableReorderOffset(
    for itemID: String,
    orderedIDs: [String],
    frames: [String: CGRect],
    session: StableLongPressReorderSession,
    axis: StableReorderAxis,
    spacing: CGFloat
) -> CGSize {
    guard let sourceID = session.sourceID,
          let targetID = session.targetID,
          let sourceIndex = orderedIDs.firstIndex(of: sourceID),
          let targetIndex = orderedIDs.firstIndex(of: targetID),
          let itemIndex = orderedIDs.firstIndex(of: itemID) else {
        return .zero
    }

    if itemID == sourceID {
        return session.hasCrossedMovementThreshold ? session.translation : .zero
    }

    let sourceFrame = frames[sourceID] ?? .zero
    let extent = axis == .vertical
        ? sourceFrame.height + spacing
        : sourceFrame.width + spacing
    guard extent > spacing else { return .zero }

    if sourceIndex < targetIndex, itemIndex > sourceIndex, itemIndex <= targetIndex {
        return axis == .vertical ? CGSize(width: 0, height: -extent) : CGSize(width: -extent, height: 0)
    }
    if sourceIndex > targetIndex, itemIndex >= targetIndex, itemIndex < sourceIndex {
        return axis == .vertical ? CGSize(width: 0, height: extent) : CGSize(width: extent, height: 0)
    }
    return .zero
}

func stableReorderTargetID(
    at location: CGPoint,
    orderedIDs: [String],
    frames: [String: CGRect],
    axis: StableReorderAxis,
    fallback: String?
) -> String? {
    let candidates = orderedIDs.compactMap { id -> (String, CGRect)? in
        guard let frame = frames[id], !frame.isEmpty else { return nil }
        return (id, frame)
    }
    guard !candidates.isEmpty else { return fallback }

    let bounds = candidates.map(\.1).dropFirst().reduce(candidates[0].1) { $0.union($1) }
    let expandedBounds = bounds.insetBy(dx: -32, dy: -32)
    guard expandedBounds.contains(location) else { return fallback }

    return candidates.min { left, right in
        let leftDistance = axis == .vertical
            ? abs(left.1.midY - location.y)
            : abs(left.1.midX - location.x)
        let rightDistance = axis == .vertical
            ? abs(right.1.midY - location.y)
            : abs(right.1.midX - location.x)
        return leftDistance < rightDistance
    }?.0 ?? fallback
}

extension View {
    func reportStableReorderFrame(id: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: StableReorderItemFramesPreferenceKey.self,
                    value: [id: proxy.frame(in: .global)]
                )
            }
        )
    }
}

private struct SpeechVocabularyBridgeEntry: Decodable {
    let term: String
}

enum SpeechVocabularyBridgeSync {
    static func merge(
        localTerms: [String],
        reason: String,
        completion: @escaping (Bool, [String]) -> Void
    ) {
        update(terms: localTerms, mode: "merge", reason: reason, completion: completion)
    }

    static func record(
        terms: [String],
        reason: String,
        completion: @escaping (Bool, [String]) -> Void
    ) {
        update(terms: terms, mode: "record", reason: reason, completion: completion)
    }

    private static func update(
        terms: [String],
        mode: String,
        reason: String,
        completion: @escaping (Bool, [String]) -> Void
    ) {
        guard let url = URL(string: "\(ServerConfig.currentHTTPBaseURL())/api/speech-vocabulary"),
              let body = try? JSONSerialization.data(withJSONObject: [
                  "terms": terms,
                  "mode": mode,
              ]) else {
            completion(false, [])
            return
        }

        var request = DeviceAuthStore.authorizedRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if DeviceAuthStore.clearAuthIfUnauthorized(
                response: response,
                data: data,
                context: "speech_vocabulary_\(mode)"
            ) {
                DispatchQueue.main.async { completion(false, []) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let didSucceed = error == nil && (200..<300).contains(status)
            let entries = data.flatMap { data -> [SpeechVocabularyBridgeEntry]? in
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let entriesValue = object["entries"],
                      let entriesData = try? JSONSerialization.data(withJSONObject: entriesValue) else {
                    return nil
                }
                return try? JSONDecoder().decode([SpeechVocabularyBridgeEntry].self, from: entriesData)
            } ?? []
            let resolvedTerms = entries.map(\.term)
            if !didSucceed {
                print("[SpeechVocabulary] bridge sync failed reason=\(reason) status=\(status)")
            }
            DispatchQueue.main.async {
                completion(didSucceed, resolvedTerms)
            }
        }.resume()
    }
}

struct SpeechMuscleMemoryEntry: Identifiable, Codable, Equatable {
    var id: String
    var spokenPhrase: String
    var outputText: String
    var trainingCount: Int
    var isEnabled: Bool

    init(
        id: String = UUID().uuidString,
        spokenPhrase: String,
        outputText: String,
        trainingCount: Int = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.spokenPhrase = spokenPhrase
        self.outputText = outputText
        self.trainingCount = trainingCount
        self.isEnabled = isEnabled
    }
}

private struct ShortcutSuggestion: Identifiable {
    let key: String
    let description: String

    var id: String { key }
}

private func matchingShortcutSuggestions(
    _ suggestions: [ShortcutSuggestion],
    token rawToken: String
) -> [ShortcutSuggestion] {
    let token = rawToken.lowercased()
    guard !token.isEmpty else { return [] }

    return suggestions
        .enumerated()
        .map { index, suggestion in
            (
                suggestion: suggestion,
                index: index,
                key: suggestion.key.lowercased()
            )
        }
        .filter { item in item.key.hasPrefix(token) }
        .sorted { left, right in
            let leftExact = left.key == token
            let rightExact = right.key == token
            if leftExact != rightExact {
                return leftExact
            }

            return left.index < right.index
        }
        .map { item in item.suggestion }
}

private func visibleShortcutSuggestion(
    _ suggestions: [ShortcutSuggestion],
    token: String
) -> ShortcutSuggestion? {
    guard let suggestion = matchingShortcutSuggestions(suggestions, token: token).first else {
        return nil
    }

    return suggestion.key.lowercased() == token ? nil : suggestion
}

private let baseShortcutSuggestions: [ShortcutSuggestion] = [
    .init(key: "ji", description: "沉淀/记忆"),
    .init(key: "cha", description: "代码审查"),
    .init(key: "pai", description: "多终端并发编排"),
    .init(key: "qiu", description: "咨询建议"),
    .init(key: "copilot", description: "多模型执行"),
    .init(key: "sou", description: "网络搜索"),
    .init(key: "xi", description: "查询历史经验"),
    .init(key: "sync", description: "同步知识库"),
    .init(key: "yan", description: "并行调研"),
    .init(key: "plan", description: "Codex 计划"),
    .init(key: "auto", description: "软件自动化工作流"),
    .init(key: "hui", description: "项目记忆回溯"),
    .init(key: "回", description: "项目记忆回溯"),
    .init(key: "debug", description: "系统化调试")
]

private let seededShortcutSuggestions: [ShortcutSuggestion] = [
    .init(key: "cunzhiknowledge", description: "hui 高频词"),
    .init(key: "global_rules.md", description: "hui 高频词"),
    .init(key: "index.md", description: "hui 高频词"),
    .init(key: "context.md", description: "hui 高频词"),
    .init(key: "progress.md", description: "hui 高频词"),
    .init(key: "skills", description: "hui 高频词"),
    .init(key: "prompts", description: "hui 高频词"),
    .init(key: "memories", description: "hui 高频词"),
    .init(key: "localhost", description: "hui 高频词")
]

private func normalizeShortcutTerm(_ raw: String) -> String? {
    let normalized = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "`\"'()[]{};,"))
        .lowercased()

    guard normalized.count >= 2, normalized.count <= 24 else { return nil }
    guard !normalized.hasPrefix("http"),
          !normalized.contains("/"),
          !normalized.contains("\\"),
          !normalized.contains("__") else {
        return nil
    }

    let stopwords: Set<String> = [
        "true",
        "false",
        "null",
        "none",
        "void",
        "return",
        "const",
        "function",
        "async",
        "await",
        "input",
        "output",
        "message",
        "messages",
        "apple",
        "users",
        "macbook-air",
        "debug",
        "popup",
        "textarea",
    ]

    guard !stopwords.contains(normalized) else { return nil }
    guard normalized.contains(where: \.isLetter) else { return nil }
    return normalized
}

private func canonicalizeShortcutTerm(_ term: String) -> String {
    switch term {
    case "ji1", "ji2", "ji3":
        return "ji"
    case "cunzhi", "cunzhi-knowledge":
        return "cunzhiknowledge"
    default:
        return term
    }
}

/// 语音半圆 Dock 尺寸（相对初版约 +50%）。
private enum VoiceHalfCircleDockMetrics {
    static let width: CGFloat = 132
    static let semicircleHeight: CGFloat = 69
    static let outerHeight: CGFloat = 78
    static let micButtonSize: CGFloat = 51
    static let micFontSize: CGFloat = 26
    /// 越大越靠下；略小让黑球更贴上弧底。
    static let micButtonYOffset: CGFloat = 2
    /// 录音态横向电平条单独上抬，贴近半圆上沿。
    static var recordingBarLift: CGFloat { micButtonSize * 0.18 }
    static let arcStrokeWidth: CGFloat = 1.5
}

/// 底部语音 Dock + 透明占位 + 按钮：用数值对齐半圆底与 footer 内容，避免负 spacing。
private enum VoiceFooterBarLayout {
    /// 透明占位距 footer 顶的距离；半圆「平底」与此对齐。
    static let dividerTopFromFooterTop: CGFloat = 30
    /// `dividerTop - outerHeight`，使 Dock 外框底边落在预留槽位处。
    static var dockVerticalOffset: CGFloat { dividerTopFromFooterTop - VoiceHalfCircleDockMetrics.outerHeight }
    static let dividerHeight: CGFloat = 1
    /// iOS 26 Glass 按钮共享内容高度，避免字号不同导致左右外框不等高。
    static let footerActionLabelHeight: CGFloat = 26
    /// 首帧尚未测得 modern overlay 高度时，保守容纳 Dock、按钮行与既有 16pt 上下 padding。
    static var modernFooterFallbackHeight: CGFloat {
        VoiceHalfCircleDockMetrics.outerHeight
            + VoiceHalfCircleDockMetrics.micButtonSize
            + (16 * 2)
    }
}

private struct VoiceFooterGlassShape: Shape {
    func path(in rect: CGRect) -> Path {
        let panelTop = min(VoiceHalfCircleDockMetrics.outerHeight, rect.maxY)
        let radius = VoiceHalfCircleDockMetrics.width / 2
        let center = CGPoint(x: rect.midX, y: panelTop)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: panelTop))
        path.addLine(to: CGPoint(x: center.x - radius, y: panelTop))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: panelTop))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct VoiceFooterHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HeaderHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TimelineEdgePanInstaller: UIViewRepresentable {
    let isRevealEnabled: Bool
    let isDismissEnabled: Bool
    let onReveal: () -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.coordinator = context.coordinator
        context.coordinator.update(
            isRevealEnabled: isRevealEnabled,
            isDismissEnabled: isDismissEnabled,
            onReveal: onReveal,
            onDismiss: onDismiss
        )
        return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {
        uiView.coordinator = context.coordinator
        context.coordinator.update(
            isRevealEnabled: isRevealEnabled,
            isDismissEnabled: isDismissEnabled,
            onReveal: onReveal,
            onDismiss: onDismiss
        )
        context.coordinator.attach(to: uiView.window)
    }

    static func dismantleUIView(_ uiView: InstallerView, coordinator: Coordinator) {
        coordinator.detach()
        uiView.coordinator = nil
    }

    final class InstallerView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: window)
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            false
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private var revealRecognizer: UIScreenEdgePanGestureRecognizer?
        private var dismissRecognizer: UIPanGestureRecognizer?
        private var isRevealEnabled = false
        private var isDismissEnabled = false
        private var onReveal: () -> Void = {}
        private var onDismiss: () -> Void = {}

        func update(
            isRevealEnabled: Bool,
            isDismissEnabled: Bool,
            onReveal: @escaping () -> Void,
            onDismiss: @escaping () -> Void
        ) {
            self.isRevealEnabled = isRevealEnabled
            self.isDismissEnabled = isDismissEnabled
            self.onReveal = onReveal
            self.onDismiss = onDismiss
        }

        func attach(to newWindow: UIWindow?) {
            guard window !== newWindow else { return }
            detach()
            guard let newWindow else { return }

            let reveal = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleReveal(_:)))
            reveal.edges = .right
            reveal.cancelsTouchesInView = false
            reveal.delegate = self
            newWindow.addGestureRecognizer(reveal)

            let dismiss = UIPanGestureRecognizer(target: self, action: #selector(handleDismiss(_:)))
            dismiss.cancelsTouchesInView = false
            dismiss.delegate = self
            newWindow.addGestureRecognizer(dismiss)

            window = newWindow
            revealRecognizer = reveal
            dismissRecognizer = dismiss
        }

        func detach() {
            if let revealRecognizer {
                window?.removeGestureRecognizer(revealRecognizer)
            }
            if let dismissRecognizer {
                window?.removeGestureRecognizer(dismissRecognizer)
            }
            revealRecognizer = nil
            dismissRecognizer = nil
            window = nil
        }

        @objc private func handleReveal(_ recognizer: UIScreenEdgePanGestureRecognizer) {
            guard isRevealEnabled, recognizer.state == .ended else { return }
            let translation = recognizer.translation(in: recognizer.view)
            let velocity = recognizer.velocity(in: recognizer.view)
            if translation.x < -20 || velocity.x < -120 {
                onReveal()
            }
        }

        @objc private func handleDismiss(_ recognizer: UIPanGestureRecognizer) {
            guard isDismissEnabled, recognizer.state == .ended else { return }
            let translation = recognizer.translation(in: recognizer.view)
            let velocity = recognizer.velocity(in: recognizer.view)
            if translation.x > 20 || velocity.x > 120 {
                onDismiss()
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === revealRecognizer {
                return isRevealEnabled
            }

            if gestureRecognizer === dismissRecognizer,
               let view = gestureRecognizer.view,
               let pan = gestureRecognizer as? UIPanGestureRecognizer {
                guard isDismissEnabled else { return false }
                let location = pan.location(in: view)
                let velocity = pan.velocity(in: view)
                return location.x >= view.bounds.width - 96
                    && velocity.x > 80
                    && abs(velocity.x) > abs(velocity.y) * 1.25
            }

            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private struct PendingPhoneActionEnvelope: Codable {
    let request: PhoneActionRequest
    let createdAt: Date
    let retryCount: Int
    let reason: String

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) >= PendingPhoneActionStore.ttl
    }

    func incrementingRetry(reason nextReason: String) -> PendingPhoneActionEnvelope {
        PendingPhoneActionEnvelope(
            request: request,
            createdAt: createdAt,
            retryCount: retryCount + 1,
            reason: nextReason
        )
    }
}

private enum PendingPhoneActionStore {
    static let storageKey = "iterate_pending_phone_action_envelope"
    static let ttl: TimeInterval = 10 * 60

    static func load() -> PendingPhoneActionEnvelope? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(PendingPhoneActionEnvelope.self, from: data)
    }

    static func save(_ envelope: PendingPhoneActionEnvelope) {
        guard let data = try? JSONEncoder().encode(envelope) else {
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func clear(actionId: String? = nil) {
        if let actionId,
           let envelope = load(),
           envelope.request.id != actionId {
            return
        }
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

private struct PhoneActionJobResponse: Decodable {
    let ok: Bool
    let job: PhoneActionJob
}

private struct PhoneActionJob: Decodable {
    let id: String
    let actionId: String
    let action: String
    let payload: PhoneActionJobPayload
    let payloadSizeBytes: Int
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case actionId = "action_id"
        case action
        case payload
        case payloadSizeBytes = "payload_size_bytes"
        case expiresAt = "expires_at"
    }
}

enum SpeechMuscleMemoryStore {
    static let storageKey = "speech_muscle_memory_store"
    static let pendingSyncKey = "speech_muscle_memory_pending_sync_store"
    static let lastPushedHashKey = "speech_muscle_memory_last_pushed_hash"
    static let deletedEntryIDsKey = "speech_muscle_memory_deleted_ids_store"
    static let activationThreshold = 4

    static func decode(_ rawValue: String) -> [SpeechMuscleMemoryEntry] {
        guard let data = rawValue.data(using: .utf8),
              let entries = try? JSONDecoder().decode([SpeechMuscleMemoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    static func encode(_ entries: [SpeechMuscleMemoryEntry]) -> String {
        guard let data = try? JSONEncoder().encode(entries),
              let raw = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return raw
    }

    static func merge(
        local: [SpeechMuscleMemoryEntry],
        remote: [SpeechMuscleMemoryEntry],
        deletedEntryIDs: Set<String> = []
    ) -> [SpeechMuscleMemoryEntry] {
        var merged: [SpeechMuscleMemoryEntry] = []
        var indexesByID: [String: Int] = [:]
        var indexesByKey: [String: Int] = [:]

        func rememberIndex(_ entry: SpeechMuscleMemoryEntry, at index: Int) {
            indexesByID[entry.id] = index
            indexesByKey[syncKey(for: entry)] = index
        }

        func upsert(_ entry: SpeechMuscleMemoryEntry, preferIncomingFields: Bool) {
            guard !deletedEntryIDs.contains(entry.id) else { return }
            let key = syncKey(for: entry)
            let existingIndex = indexesByID[entry.id] ?? indexesByKey[key]
            guard let index = existingIndex else {
                rememberIndex(entry, at: merged.count)
                merged.append(entry)
                return
            }

            var existing = merged[index]
            let oldKey = syncKey(for: existing)
            let trainingCount = max(existing.trainingCount, entry.trainingCount)
            if preferIncomingFields {
                existing = entry
            }
            existing.trainingCount = trainingCount
            merged[index] = existing
            indexesByID[existing.id] = index
            indexesByKey.removeValue(forKey: oldKey)
            indexesByKey[syncKey(for: existing)] = index
        }

        remote.forEach { upsert($0, preferIncomingFields: false) }
        local.forEach { upsert($0, preferIncomingFields: true) }
        return merged
    }

    static func syncKey(for entry: SpeechMuscleMemoryEntry) -> String {
        let phrase = normalize(entry.spokenPhrase)
        let output = normalize(entry.outputText)
        if phrase.isEmpty && output.isEmpty {
            return "id:\(entry.id)"
        }
        return "\(phrase)::\(output)"
    }

    static func decodeDeletedEntryIDs(_ rawValue: String) -> Set<String> {
        guard let data = rawValue.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    static func encodeDeletedEntryIDs(_ ids: Set<String>) -> String {
        let sortedIDs = ids.sorted()
        guard let data = try? JSONEncoder().encode(sortedIDs),
              let raw = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return raw
    }

    static func fingerprint(_ rawValue: String) -> String {
        let hash = rawValue.utf8.reduce(UInt64(1469598103934665603)) { partial, byte in
            (partial ^ UInt64(byte)) &* UInt64(1099511628211)
        }
        return String(hash, radix: 16)
    }

    static func contextualTerms(from rawValue: String) -> [String] {
        decode(rawValue)
            .filter(\.isEnabled)
            .sorted { $0.trainingCount > $1.trainingCount }
            .flatMap { entry in
                [
                    entry.spokenPhrase,
                    entry.outputText,
                ]
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func enabledEntries(from rawValue: String) -> [SpeechMuscleMemoryEntry] {
        decode(rawValue)
            .filter(\.isEnabled)
    }

    static func activeEntries(from rawValue: String) -> [SpeechMuscleMemoryEntry] {
        enabledEntries(from: rawValue)
            .filter { $0.trainingCount >= activationThreshold }
    }

    static func candidate(transcript: String, in rawValue: String) -> SpeechMuscleMemoryEntry? {
        let normalizedTranscript = normalize(transcript)
        guard !normalizedTranscript.isEmpty else { return nil }

        return enabledEntries(from: rawValue)
            .sorted { $0.trainingCount > $1.trainingCount }
            .first { normalize($0.spokenPhrase) == normalizedTranscript }
    }

    /// 已激活短语：除整句完全一致外，允许整段识别结果以前缀/后缀命中短语（避免「说完了派发」无法触发）。
    /// 多条命中时优先更长口语、同长度时训练次数更高者优先。
    static func substitutionCandidate(transcript: String, in rawValue: String) -> SpeechMuscleMemoryEntry? {
        let normalizedTranscript = normalize(transcript)
        guard !normalizedTranscript.isEmpty else { return nil }

        let sorted = activeEntries(from: rawValue).sorted { a, b in
            let na = normalize(a.spokenPhrase)
            let nb = normalize(b.spokenPhrase)
            if na.count != nb.count {
                return na.count > nb.count
            }
            if a.trainingCount != b.trainingCount {
                return a.trainingCount > b.trainingCount
            }
            return na > nb
        }

        for entry in sorted {
            let p = normalize(entry.spokenPhrase)
            guard !p.isEmpty else { continue }
            if normalizedTranscript == p { return entry }
            if normalizedTranscript.contains(p) { return entry }
            if normalizedTranscript.hasSuffix(p) { return entry }
            if normalizedTranscript.hasPrefix(p) { return entry }
            // ASR 常把「派发」收成「派」：允许「口语短语 hasPrefix(识别结果)」且识别更短
            if p.count > normalizedTranscript.count, p.hasPrefix(normalizedTranscript) {
                return entry
            }
        }
        return nil
    }

    static func entry(id: String, from rawValue: String) -> SpeechMuscleMemoryEntry? {
        decode(rawValue).first { $0.id == id }
    }

    static func bumpTraining(for id: String, in rawValue: String) -> String {
        var entries = decode(rawValue)
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return rawValue
        }
        entries[index].trainingCount += 1
        return encode(entries)
    }

    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let scalars = lowered.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}").contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

struct SpeechCorrectionMemoryEntry: Identifiable, Codable, Equatable {
    var id: String
    var observedText: String
    var intendedText: String
    var contextTerms: [String]
    var hitCount: Int
    var confirmCount: Int
    var rejectCount: Int
    var isEnabled: Bool
    var source: String
    var createdAt: String
    var updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case observedText
        case intendedText
        case contextTerms
        case hitCount
        case confirmCount
        case rejectCount
        case isEnabled
        case source
        case createdAt
        case updatedAt
    }

    init(
        id: String = UUID().uuidString,
        observedText: String,
        intendedText: String,
        contextTerms: [String] = [],
        hitCount: Int = 0,
        confirmCount: Int = 0,
        rejectCount: Int = 0,
        isEnabled: Bool = true,
        source: String = "manual",
        createdAt: String = SpeechCorrectionMemoryStore.nowString(),
        updatedAt: String = SpeechCorrectionMemoryStore.nowString()
    ) {
        self.id = id
        self.observedText = observedText
        self.intendedText = intendedText
        self.contextTerms = contextTerms
        self.hitCount = hitCount
        self.confirmCount = confirmCount
        self.rejectCount = rejectCount
        self.isEnabled = isEnabled
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        observedText = try container.decodeIfPresent(String.self, forKey: .observedText) ?? ""
        intendedText = try container.decodeIfPresent(String.self, forKey: .intendedText) ?? ""
        contextTerms = try container.decodeIfPresent([String].self, forKey: .contextTerms) ?? []
        hitCount = try container.decodeIfPresent(Int.self, forKey: .hitCount) ?? 0
        confirmCount = try container.decodeIfPresent(Int.self, forKey: .confirmCount) ?? 0
        rejectCount = try container.decodeIfPresent(Int.self, forKey: .rejectCount) ?? 0
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "legacy"
        let now = SpeechCorrectionMemoryStore.nowString()
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? now
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
    }
}

struct SpeechCorrectionMemoryMatch {
    let entry: SpeechCorrectionMemoryEntry
    let correctedText: String
}

struct SpeechCorrectionLearningCandidate: Identifiable, Equatable {
    let id: UUID
    let observedText: String
    let intendedText: String
    let contextTerms: [String]
    let rawTranscript: String
    let resolvedTranscript: String
    let finalText: String
    let source: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        observedText: String,
        intendedText: String,
        contextTerms: [String],
        rawTranscript: String,
        resolvedTranscript: String,
        finalText: String,
        source: String,
        createdAt: Date
    ) {
        self.id = id
        self.observedText = observedText
        self.intendedText = intendedText
        self.contextTerms = contextTerms
        self.rawTranscript = rawTranscript
        self.resolvedTranscript = resolvedTranscript
        self.finalText = finalText
        self.source = source
        self.createdAt = createdAt
    }

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > SpeechCorrectionMemoryStore.learningCandidateTTL
    }
}

enum SpeechCorrectionMemoryStore {
    static let storageKey = "speech_correction_memory_store"
    static let pendingSyncKey = "speech_correction_memory_pending_sync_store"
    static let lastPushedHashKey = "speech_correction_memory_last_pushed_hash"
    static let trustedConfirmThreshold = 3
    static let learningCandidateTTL: TimeInterval = 10 * 60

    static func nowString() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    static func decode(_ rawValue: String) -> [SpeechCorrectionMemoryEntry] {
        guard let data = rawValue.data(using: .utf8),
              let entries = try? JSONDecoder().decode([SpeechCorrectionMemoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    static func encode(_ entries: [SpeechCorrectionMemoryEntry]) -> String {
        guard let data = try? JSONEncoder().encode(entries),
              let raw = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return raw
    }

    static func merge(
        local: [SpeechCorrectionMemoryEntry],
        remote: [SpeechCorrectionMemoryEntry]
    ) -> [SpeechCorrectionMemoryEntry] {
        var merged: [SpeechCorrectionMemoryEntry] = []
        var indexesByID: [String: Int] = [:]
        var indexesByKey: [String: Int] = [:]

        func rememberIndex(_ entry: SpeechCorrectionMemoryEntry, at index: Int) {
            indexesByID[entry.id] = index
            indexesByKey[syncKey(for: entry)] = index
        }

        func upsert(_ entry: SpeechCorrectionMemoryEntry, preferIncomingFields: Bool) {
            let key = syncKey(for: entry)
            let existingIndex = indexesByID[entry.id] ?? indexesByKey[key]
            guard let index = existingIndex else {
                rememberIndex(entry, at: merged.count)
                merged.append(entry)
                return
            }

            let previous = merged[index]
            var resolved = preferIncomingFields ? entry : previous
            resolved.hitCount = max(previous.hitCount, entry.hitCount)
            resolved.confirmCount = max(previous.confirmCount, entry.confirmCount)
            resolved.rejectCount = max(previous.rejectCount, entry.rejectCount)
            resolved.contextTerms = cleanedTerms(
                previous.contextTerms + entry.contextTerms + [previous.intendedText, entry.intendedText],
                excluding: [previous.observedText, entry.observedText]
            )
            resolved.createdAt = min(previous.createdAt, entry.createdAt)
            resolved.updatedAt = max(previous.updatedAt, entry.updatedAt)

            let oldKey = syncKey(for: previous)
            merged[index] = resolved
            indexesByID[resolved.id] = index
            indexesByKey.removeValue(forKey: oldKey)
            indexesByKey[syncKey(for: resolved)] = index
        }

        remote.forEach { upsert($0, preferIncomingFields: false) }
        local.forEach { upsert($0, preferIncomingFields: true) }
        return merged
    }

    static func syncKey(for entry: SpeechCorrectionMemoryEntry) -> String {
        let observed = normalize(entry.observedText)
        let intended = normalize(entry.intendedText)
        if observed.isEmpty && intended.isEmpty {
            return "id:\(entry.id)"
        }
        return "\(observed)::\(intended)"
    }

    static func fingerprint(_ rawValue: String) -> String {
        SpeechMuscleMemoryStore.fingerprint(rawValue)
    }

    static func contextualTerms(from rawValue: String) -> [String] {
        decode(rawValue)
            .filter(\.isEnabled)
            .sorted { left, right in
                let leftScore = left.confirmCount + left.hitCount
                let rightScore = right.confirmCount + right.hitCount
                if leftScore != rightScore {
                    return leftScore > rightScore
                }
                return left.updatedAt > right.updatedAt
            }
            .flatMap { entry in
                [entry.intendedText] + entry.contextTerms
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func correctionCandidate(
        transcript: String,
        in rawValue: String,
        contextTerms: [String]
    ) -> SpeechCorrectionMemoryEntry? {
        correctionMatch(transcript: transcript, in: rawValue, contextTerms: contextTerms)?.entry
    }

    static func correctionMatch(
        transcript: String,
        in rawValue: String,
        contextTerms: [String]
    ) -> SpeechCorrectionMemoryMatch? {
        let normalizedTranscript = normalize(transcript)
        guard !normalizedTranscript.isEmpty else { return nil }

        let transcriptTerms = SpeechContextProvider.extractTerms(from: transcript)
        let normalizedContextTerms = Set((contextTerms + transcriptTerms).map(normalize).filter { !$0.isEmpty })
        let matches = decode(rawValue)
            .filter(\.isEnabled)
            .compactMap { entry -> (entry: SpeechCorrectionMemoryEntry, correctedText: String)? in
                guard entry.confirmCount >= trustedConfirmThreshold,
                      entry.rejectCount == 0,
                      normalize(entry.intendedText) != normalizedTranscript,
                      let correctedText = correctedTranscript(for: entry, transcript: transcript),
                      correctedText != transcript,
                      !isExplicitComparisonContext(transcript: transcript, entry: entry),
                      isContextAllowed(
                        for: entry,
                        transcript: transcript,
                        normalizedContextTerms: normalizedContextTerms
                      ) else {
                    return nil
                }

                return (entry, correctedText)
            }
            .sorted { left, right in
                let leftScore = left.entry.confirmCount * 3 + left.entry.hitCount - left.entry.rejectCount * 4
                let rightScore = right.entry.confirmCount * 3 + right.entry.hitCount - right.entry.rejectCount * 4
                if leftScore != rightScore {
                    return leftScore > rightScore
                }
                let leftObservedLength = normalize(left.entry.observedText).count
                let rightObservedLength = normalize(right.entry.observedText).count
                if leftObservedLength != rightObservedLength {
                    return leftObservedLength > rightObservedLength
                }
                return left.entry.updatedAt > right.entry.updatedAt
            }

        guard let match = matches.first else { return nil }
        return SpeechCorrectionMemoryMatch(entry: match.entry, correctedText: match.correctedText)
    }

    static func upsertCorrection(
        observedText: String,
        intendedText: String,
        contextTerms: [String],
        source: String,
        in rawValue: String
    ) -> String {
        let trimmedObserved = observedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIntended = intendedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedObserved = normalize(trimmedObserved)
        let normalizedIntended = normalize(trimmedIntended)
        guard !normalizedObserved.isEmpty,
              !normalizedIntended.isEmpty,
              normalizedObserved != normalizedIntended else {
            return rawValue
        }

        let now = nowString()
        let cleanedContextTerms = cleanedTerms(contextTerms + [trimmedIntended], excluding: [trimmedObserved])
        var entries = decode(rawValue)
        if let index = entries.firstIndex(where: {
            normalize($0.observedText) == normalizedObserved
                && normalize($0.intendedText) == normalizedIntended
        }) {
            entries[index].confirmCount += 1
            entries[index].rejectCount = max(0, entries[index].rejectCount - 1)
            entries[index].contextTerms = cleanedTerms(
                entries[index].contextTerms + cleanedContextTerms,
                excluding: [trimmedObserved]
            )
            entries[index].isEnabled = true
            entries[index].source = source
            entries[index].updatedAt = now
            return encode(entries)
        }

        entries.insert(
            SpeechCorrectionMemoryEntry(
                observedText: trimmedObserved,
                intendedText: trimmedIntended,
                contextTerms: cleanedContextTerms,
                confirmCount: 1,
                isEnabled: true,
                source: source,
                createdAt: now,
                updatedAt: now
            ),
            at: 0
        )
        return encode(entries)
    }

    static func recordRejection(
        observedText: String,
        intendedText: String,
        contextTerms: [String],
        source: String,
        in rawValue: String
    ) -> String {
        let trimmedObserved = observedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIntended = intendedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedObserved = normalize(trimmedObserved)
        let normalizedIntended = normalize(trimmedIntended)
        guard !normalizedObserved.isEmpty,
              !normalizedIntended.isEmpty,
              normalizedObserved != normalizedIntended else {
            return rawValue
        }

        let now = nowString()
        let cleanedContextTerms = cleanedTerms(contextTerms + [trimmedIntended], excluding: [trimmedObserved])
        var entries = decode(rawValue)
        if let index = entries.firstIndex(where: {
            normalize($0.observedText) == normalizedObserved
                && normalize($0.intendedText) == normalizedIntended
        }) {
            entries[index].rejectCount += 1
            entries[index].contextTerms = cleanedTerms(
                entries[index].contextTerms + cleanedContextTerms,
                excluding: [trimmedObserved]
            )
            entries[index].isEnabled = true
            entries[index].source = source
            entries[index].updatedAt = now
            return encode(entries)
        }

        entries.insert(
            SpeechCorrectionMemoryEntry(
                observedText: trimmedObserved,
                intendedText: trimmedIntended,
                contextTerms: cleanedContextTerms,
                rejectCount: 1,
                isEnabled: true,
                source: source,
                createdAt: now,
                updatedAt: now
            ),
            at: 0
        )
        return encode(entries)
    }

#if DEBUG
    static func applyingDebugSeeds(from rawSeeds: String, in rawValue: String) -> String {
        guard let data = rawSeeds.data(using: .utf8),
              let seeds = try? JSONDecoder().decode([DebugSeed].self, from: data),
              !seeds.isEmpty else {
            return rawValue
        }

        var entries = decode(rawValue)
        var didChange = false
        let now = nowString()

        for seed in seeds {
            let trimmedObserved = seed.observedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedIntended = seed.intendedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedObserved = normalize(trimmedObserved)
            let normalizedIntended = normalize(trimmedIntended)
            guard !normalizedObserved.isEmpty,
                  !normalizedIntended.isEmpty,
                  normalizedObserved != normalizedIntended else {
                continue
            }

            let confirmCount = max(1, seed.confirmCount ?? trustedConfirmThreshold)
            let cleanedContextTerms = cleanedTerms(
                seed.contextTerms + [trimmedIntended],
                excluding: [trimmedObserved]
            )

            if let index = entries.firstIndex(where: {
                normalize($0.observedText) == normalizedObserved
                    && normalize($0.intendedText) == normalizedIntended
            }) {
                let previous = entries[index]
                entries[index].confirmCount = max(entries[index].confirmCount, confirmCount)
                entries[index].rejectCount = 0
                entries[index].contextTerms = cleanedTerms(
                    entries[index].contextTerms + cleanedContextTerms,
                    excluding: [trimmedObserved]
                )
                entries[index].isEnabled = true
                entries[index].source = "debug_seed"
                entries[index].updatedAt = now
                didChange = didChange || entries[index] != previous
                continue
            }

            entries.insert(
                SpeechCorrectionMemoryEntry(
                    observedText: trimmedObserved,
                    intendedText: trimmedIntended,
                    contextTerms: cleanedContextTerms,
                    confirmCount: confirmCount,
                    rejectCount: 0,
                    isEnabled: true,
                    source: "debug_seed",
                    createdAt: now,
                    updatedAt: now
                ),
                at: 0
            )
            didChange = true
        }

        return didChange ? encode(entries) : rawValue
    }

    private struct DebugSeed: Decodable {
        let observedText: String
        let intendedText: String
        let contextTerms: [String]
        let confirmCount: Int?

        private enum CodingKeys: String, CodingKey {
            case observedText
            case intendedText
            case contextTerms
            case confirmCount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            observedText = try container.decode(String.self, forKey: .observedText)
            intendedText = try container.decode(String.self, forKey: .intendedText)
            contextTerms = try container.decodeIfPresent([String].self, forKey: .contextTerms) ?? []
            confirmCount = try container.decodeIfPresent(Int.self, forKey: .confirmCount)
        }
    }
#endif

    static func recordHit(for id: String, in rawValue: String) -> String {
        var entries = decode(rawValue)
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return rawValue
        }
        entries[index].hitCount += 1
        entries[index].updatedAt = nowString()
        return encode(entries)
    }

    static func normalize(_ text: String) -> String {
        SpeechMuscleMemoryStore.normalize(text)
    }

    static func inferredCorrectionPair(
        observedText: String,
        intendedText: String
    ) -> (observedText: String, intendedText: String)? {
        let observedTokens = correctionTokens(observedText)
        let intendedTokens = correctionTokens(intendedText)
        guard observedTokens.count == intendedTokens.count,
              !observedTokens.isEmpty else {
            return nil
        }

        var changedPair: (observedText: String, intendedText: String)?
        for (observedToken, intendedToken) in zip(observedTokens, intendedTokens) {
            let normalizedObserved = normalize(observedToken)
            let normalizedIntended = normalize(intendedToken)
            guard !normalizedObserved.isEmpty, !normalizedIntended.isEmpty else { continue }
            if normalizedObserved == normalizedIntended {
                continue
            }
            if changedPair != nil {
                return nil
            }
            changedPair = (observedToken, intendedToken)
        }

        return changedPair
    }

    static func learningCandidate(
        observedText: String,
        resolvedText: String,
        intendedText: String,
        contextTerms: [String],
        source: String,
        createdAt: Date = Date()
    ) -> SpeechCorrectionLearningCandidate? {
        let observed = observedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = resolvedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let intended = intendedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard observed.count >= 2,
              intended.count >= 2,
              observed.count <= 80,
              intended.count <= 120,
              !intended.contains("\n") else {
            return nil
        }

        let normalizedObserved = normalize(observed)
        let normalizedResolved = normalize(resolved)
        let normalizedIntended = normalize(intended)
        guard !normalizedObserved.isEmpty,
              !normalizedIntended.isEmpty,
              normalizedObserved == normalizedResolved,
              normalizedObserved != normalizedIntended,
              let inferredPair = inferredCorrectionPair(
                observedText: observed,
                intendedText: intended
              ) else {
            return nil
        }

        let cleanedContextTerms = cleanedTerms(
            contextTerms + [inferredPair.intendedText],
            excluding: [inferredPair.observedText]
        )
        return SpeechCorrectionLearningCandidate(
            observedText: inferredPair.observedText,
            intendedText: inferredPair.intendedText,
            contextTerms: cleanedContextTerms,
            rawTranscript: observed,
            resolvedTranscript: resolved,
            finalText: intended,
            source: source,
            createdAt: createdAt
        )
    }

    private static func isContextAllowed(
        for entry: SpeechCorrectionMemoryEntry,
        transcript: String,
        normalizedContextTerms: Set<String>
    ) -> Bool {
        let observed = normalize(entry.observedText)
        let intended = normalize(entry.intendedText)
        guard !intended.isEmpty else { return false }
        guard !isBlockedByNegativeContext(for: entry, transcript: transcript, normalizedContextTerms: normalizedContextTerms) else {
            return false
        }

        if requiresStrongStyleContext(observed: observed, intended: intended) {
            return hasStrongStyleContext(transcript: transcript, normalizedContextTerms: normalizedContextTerms)
        }

        if normalizedContextTerms.contains(intended) {
            return true
        }

        let contextMatchesEntry = ([entry.intendedText] + entry.contextTerms)
            .map(normalize)
            .filter { !$0.isEmpty }
            .contains { term in
                normalizedContextTerms.contains(term)
                    || normalizedContextTerms.contains { context in
                        context.count >= 2 && term.count >= 2 && (context.contains(term) || term.contains(context))
                    }
            }

        return contextMatchesEntry
    }

    private static func requiresStrongStyleContext(observed: String, intended: String) -> Bool {
        intended == "style" && ["sell", "sale", "cell", "ceo"].contains(observed)
    }

    private static func hasStrongStyleContext(
        transcript: String,
        normalizedContextTerms: Set<String>
    ) -> Bool {
        let exactTranscriptTerms = Set(
            SpeechContextProvider.extractTerms(from: transcript)
                .map(normalize)
                .filter { !$0.isEmpty }
        )
        let exactPositiveTerms: Set<String> = ["style", "ui"]
        if !exactTranscriptTerms.isDisjoint(with: exactPositiveTerms) {
            return true
        }

        let positiveTerms = [
            "css", "styles", "stylesheet", "frontend",
            "样式", "前端", "界面", "组件", "设计"
        ]
        let normalizedTranscript = normalize(transcript)
        return positiveTerms.contains { term in
            let normalizedTerm = normalize(term)
            return normalizedContextTerms.contains(normalizedTerm)
                || normalizedTranscript.contains(normalizedTerm)
        }
    }

    private static func correctedTranscript(
        for entry: SpeechCorrectionMemoryEntry,
        transcript: String
    ) -> String? {
        let trimmedIntended = entry.intendedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIntended.isEmpty,
              normalize(entry.observedText) != normalize(entry.intendedText),
              let range = observedRange(for: entry.observedText, in: transcript) else {
            return nil
        }

        var corrected = transcript
        corrected.replaceSubrange(range, with: trimmedIntended)
        return corrected
    }

    private static func observedRange(for observedText: String, in transcript: String) -> Range<String.Index>? {
        let trimmedObserved = observedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedObserved.isEmpty else { return nil }

        if usesWordBoundaries(trimmedObserved),
           let range = regexRange(for: trimmedObserved, in: transcript) {
            return range
        }

        if let range = transcript.range(
            of: trimmedObserved,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            return range
        }

        if normalize(transcript) == normalize(trimmedObserved) {
            return transcript.startIndex..<transcript.endIndex
        }

        return nil
    }

    private static func regexRange(for observedText: String, in transcript: String) -> Range<String.Index>? {
        let escaped = NSRegularExpression.escapedPattern(for: observedText)
        let pattern = #"(?i)(?<![A-Za-z0-9_])"# + escaped + #"(?![A-Za-z0-9_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsRange = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        guard let match = regex.firstMatch(in: transcript, options: [], range: nsRange) else {
            return nil
        }
        return Range(match.range, in: transcript)
    }

    private static func usesWordBoundaries(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57)
                || (scalar.value >= 65 && scalar.value <= 90)
                || (scalar.value >= 97 && scalar.value <= 122)
                || scalar.value == 95
        }
    }

    private static func isExplicitComparisonContext(
        transcript: String,
        entry: SpeechCorrectionMemoryEntry
    ) -> Bool {
        let normalizedTranscript = normalize(transcript)
        let observed = normalize(entry.observedText)
        let intended = normalize(entry.intendedText)
        guard !observed.isEmpty,
              !intended.isEmpty,
              normalizedTranscript.contains(observed),
              normalizedTranscript.contains(intended) else {
            return false
        }

        let markers = ["识别成", "不要把", "不是", "而是", "改成", "纠错", "替换", "->", "=>"]
        return markers.contains { transcript.localizedCaseInsensitiveContains($0) }
    }

    private static func isBlockedByNegativeContext(
        for entry: SpeechCorrectionMemoryEntry,
        transcript: String,
        normalizedContextTerms: Set<String>
    ) -> Bool {
        let observed = normalize(entry.observedText)
        let intended = normalize(entry.intendedText)
        let isStyleCorrectionPair = intended == "style"
            && ["sell", "sale", "cell", "ceo"].contains(observed)
        guard isStyleCorrectionPair else { return false }

        let negativeTerms: Set<String> = [
            "销售", "客户", "报价", "成交", "漏斗", "转化", "业务",
            "sales", "selling", "customer", "business", "funnel", "revenue", "pricing"
        ]
        let normalizedTranscript = normalize(transcript)
        return negativeTerms.contains { term in
            normalizedContextTerms.contains(normalize(term))
                || normalizedTranscript.contains(normalize(term))
        }
    }

    private static func correctionTokens(_ text: String) -> [String] {
        let pattern = #"[A-Za-z0-9_]+|[\p{Han}]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).map { match in
            nsText.substring(with: match.range)
        }
    }

    private static func cleanedTerms(_ terms: [String], excluding excludedTerms: [String]) -> [String] {
        let excluded = Set(excludedTerms.map(normalize).filter { !$0.isEmpty })
        var seen = Set<String>()
        var cleaned: [String] = []

        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 48 else { continue }

            let normalized = normalize(trimmed)
            guard !normalized.isEmpty,
                  !excluded.contains(normalized),
                  !seen.contains(normalized) else {
                continue
            }

            seen.insert(normalized)
            cleaned.append(trimmed)
            if cleaned.count >= 16 {
                break
            }
        }

        return cleaned
    }
}

enum SpeechMuscleMemoryBridgeSync {
    static func fetchRemoteEntries(reason: String, completion: @escaping ([SpeechMuscleMemoryEntry]) -> Void) {
        fetchRemoteEntriesWithStatus(reason: reason) { _, entries in
            completion(entries)
        }
    }

    static func fetchRemoteEntriesWithStatus(
        reason: String,
        completion: @escaping (Bool, [SpeechMuscleMemoryEntry]) -> Void
    ) {
        guard let url = URL(string: "\(ServerConfig.currentHTTPBaseURL())/api/speech-muscle-memory") else {
            completion(false, [])
            return
        }

        let request = DeviceAuthStore.authorizedRequest(url: url)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "speech_memory_fetch") {
                DispatchQueue.main.async {
                    completion(false, [])
                }
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let didSucceed = error == nil && (200..<300).contains(statusCode)
            let entries = decodeEntries(from: data)
            if let error {
                print("[SpeechMemory] bridge sync failed reason=\(reason) error=\(error.localizedDescription)")
            } else if !didSucceed {
                print("[SpeechMemory] bridge sync failed reason=\(reason) status=\(statusCode)")
            } else {
                print("[SpeechMemory] bridge sync fetched reason=\(reason) entries=\(entries.count)")
            }
            DispatchQueue.main.async {
                completion(didSucceed, entries)
            }
        }.resume()
    }

    static func mergeAndPush(
        localEntries: [SpeechMuscleMemoryEntry],
        deletedEntryIDs: Set<String> = [],
        reason: String,
        completion: @escaping (Bool, [SpeechMuscleMemoryEntry]) -> Void
    ) {
        fetchRemoteEntriesWithStatus(reason: "\(reason)_prefetch") { didFetch, remoteEntries in
            guard didFetch else {
                completion(false, localEntries)
                return
            }

            let mergedEntries = SpeechMuscleMemoryStore.merge(
                local: localEntries,
                remote: remoteEntries,
                deletedEntryIDs: deletedEntryIDs
            )
            pushRemoteEntries(mergedEntries, reason: reason, completion: completion)
        }
    }

    static func pushRemoteEntries(
        _ entries: [SpeechMuscleMemoryEntry],
        reason: String,
        completion: @escaping (Bool, [SpeechMuscleMemoryEntry]) -> Void
    ) {
        guard let url = URL(string: "\(ServerConfig.currentHTTPBaseURL())/api/speech-muscle-memory"),
              let body = try? JSONEncoder().encode(PushRequest(entries: entries)) else {
            completion(false, entries)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        DeviceAuthStore.applyAuthHeaders(to: &request)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "speech_memory_push") {
                DispatchQueue.main.async {
                    completion(false, entries)
                }
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let didSucceed = error == nil && (200..<300).contains(statusCode)
            let savedEntries = decodeEntries(from: data)
            let resolvedEntries = savedEntries.isEmpty ? entries : savedEntries
            if let error {
                print("[SpeechMemory] bridge push failed reason=\(reason) error=\(error.localizedDescription)")
            } else if !didSucceed {
                print("[SpeechMemory] bridge push failed reason=\(reason) status=\(statusCode)")
            } else {
                print("[SpeechMemory] bridge push saved reason=\(reason) entries=\(resolvedEntries.count)")
            }
            DispatchQueue.main.async {
                completion(didSucceed, resolvedEntries)
            }
        }.resume()
    }

    private static func decodeEntries(from data: Data?) -> [SpeechMuscleMemoryEntry] {
        guard let data else { return [] }
        let decoder = JSONDecoder()
        if let response = try? JSONDecoder().decode(Response.self, from: data) {
            return response.entries
        }
        return (try? decoder.decode([SpeechMuscleMemoryEntry].self, from: data)) ?? []
    }

    private struct Response: Decodable {
        let entries: [SpeechMuscleMemoryEntry]
    }

    private struct PushRequest: Encodable {
        let entries: [SpeechMuscleMemoryEntry]
    }
}

enum SpeechCorrectionMemoryBridgeSync {
    static func fetchRemoteEntries(reason: String, completion: @escaping ([SpeechCorrectionMemoryEntry]) -> Void) {
        fetchRemoteEntriesWithStatus(reason: reason) { _, entries in
            completion(entries)
        }
    }

    static func fetchRemoteEntriesWithStatus(
        reason: String,
        completion: @escaping (Bool, [SpeechCorrectionMemoryEntry]) -> Void
    ) {
        guard let url = URL(string: "\(ServerConfig.currentHTTPBaseURL())/api/speech-correction-memory") else {
            completion(false, [])
            return
        }

        let request = DeviceAuthStore.authorizedRequest(url: url)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "speech_correction_memory_fetch") {
                DispatchQueue.main.async {
                    completion(false, [])
                }
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let didSucceed = error == nil && (200..<300).contains(statusCode)
            let entries = decodeEntries(from: data)
            if let error {
                print("[SpeechCorrectionMemory] bridge sync failed reason=\(reason) error=\(error.localizedDescription)")
            } else if !didSucceed {
                print("[SpeechCorrectionMemory] bridge sync failed reason=\(reason) status=\(statusCode)")
            } else {
                print("[SpeechCorrectionMemory] bridge sync fetched reason=\(reason) entries=\(entries.count)")
            }
            DispatchQueue.main.async {
                completion(didSucceed, entries)
            }
        }.resume()
    }

    static func mergeAndPush(
        localEntries: [SpeechCorrectionMemoryEntry],
        reason: String,
        completion: @escaping (Bool, [SpeechCorrectionMemoryEntry]) -> Void
    ) {
        fetchRemoteEntriesWithStatus(reason: "\(reason)_prefetch") { didFetch, remoteEntries in
            guard didFetch else {
                completion(false, localEntries)
                return
            }

            let mergedEntries = SpeechCorrectionMemoryStore.merge(
                local: localEntries,
                remote: remoteEntries
            )
            pushRemoteEntries(mergedEntries, reason: reason, completion: completion)
        }
    }

    static func pushRemoteEntries(
        _ entries: [SpeechCorrectionMemoryEntry],
        reason: String,
        completion: @escaping (Bool, [SpeechCorrectionMemoryEntry]) -> Void
    ) {
        guard let url = URL(string: "\(ServerConfig.currentHTTPBaseURL())/api/speech-correction-memory"),
              let body = try? JSONEncoder().encode(PushRequest(entries: entries)) else {
            completion(false, entries)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        DeviceAuthStore.applyAuthHeaders(to: &request)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "speech_correction_memory_push") {
                DispatchQueue.main.async {
                    completion(false, entries)
                }
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let didSucceed = error == nil && (200..<300).contains(statusCode)
            let savedEntries = decodeEntries(from: data)
            let resolvedEntries = savedEntries.isEmpty ? entries : savedEntries
            if let error {
                print("[SpeechCorrectionMemory] bridge push failed reason=\(reason) error=\(error.localizedDescription)")
            } else if !didSucceed {
                print("[SpeechCorrectionMemory] bridge push failed reason=\(reason) status=\(statusCode)")
            } else {
                print("[SpeechCorrectionMemory] bridge push saved reason=\(reason) entries=\(resolvedEntries.count)")
            }
            DispatchQueue.main.async {
                completion(didSucceed, resolvedEntries)
            }
        }.resume()
    }

    private static func decodeEntries(from data: Data?) -> [SpeechCorrectionMemoryEntry] {
        guard let data else { return [] }
        let decoder = JSONDecoder()
        if let response = try? JSONDecoder().decode(Response.self, from: data) {
            return response.entries
        }
        return (try? decoder.decode([SpeechCorrectionMemoryEntry].self, from: data)) ?? []
    }

    private struct Response: Decodable {
        let entries: [SpeechCorrectionMemoryEntry]
    }

    private struct PushRequest: Encodable {
        let entries: [SpeechCorrectionMemoryEntry]
    }
}

private struct SpeechCorrectionObservation {
    let observedText: String
    let resolvedText: String
    let createdAt: Date
}

struct ContentView: View {
    private typealias CompanionTransportCandidate = MobilePairingCandidate

    private struct RecoveryRoute {
        let transportMode: String
        let baseURL: String
        let wsURL: String
        let relayDeviceID: String?

        var normalizedWSURL: String {
            wsURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        var label: String {
            switch transportMode {
            case "tailscale":
                return "Tailscale"
            case "public_tunnel":
                return "公网"
            case "cloudflare_tunnel":
                return "Cloudflare"
            case "relay":
                return "Relay"
            case "lan_fallback":
                return "LAN"
            case "loopback_fallback":
                return "本机"
            default:
                return "当前通道"
            }
        }
    }

    private typealias CompanionPairingPayload = MobilePairingEnvelope

    private struct CompanionPairingResponse: Decodable {
        let pairing: CompanionPairingPayload?
    }

    private static let transportCandidatesStorageKey = "iterate_transport_candidates"

    @AppStorage("speech_vocabulary_store") private var speechVocabularyStore = ""
    @AppStorage(SpeechMuscleMemoryStore.storageKey) private var speechMuscleMemoryStore = "[]"
    @AppStorage(SpeechMuscleMemoryStore.pendingSyncKey) private var speechMuscleMemoryPendingSync = false
    @AppStorage(SpeechMuscleMemoryStore.lastPushedHashKey) private var speechMuscleMemoryLastPushedHash = ""
    @AppStorage(SpeechMuscleMemoryStore.deletedEntryIDsKey) private var speechMuscleMemoryDeletedEntryIDs = "[]"
    @AppStorage(SpeechCorrectionMemoryStore.storageKey) private var speechCorrectionMemoryStore = "[]"
    @AppStorage(SpeechCorrectionMemoryStore.pendingSyncKey) private var speechCorrectionMemoryPendingSync = false
    @AppStorage(SpeechCorrectionMemoryStore.lastPushedHashKey) private var speechCorrectionMemoryLastPushedHash = ""
    @AppStorage(ServerConfig.storageKey) private var serverURL = ServerConfig.defaultWebSocketURL
    @AppStorage(ServerConfig.relayControlBaseURLKey) private var relayControlBaseURL = ""
    @AppStorage(ServerConfig.relayMacDeviceIDKey) private var relayMacDeviceID = "local-mac"
    @AppStorage(ServerConfig.relayAutoRecoverOnActivationKey) private var relayAutoRecoverOnActivation = false
    @AppStorage(ServerConfig.relayLastAutoRecoverAtKey) private var relayLastAutoRecoverAt = 0.0
    @StateObject private var webSocketManager = WebSocketManager()
    @State private var hasDeviceAuthorization = DeviceAuthStore.load() != nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var relayAutoRecoveryInFlight = false
    @State private var userInput = ""
    @State private var isDarkMode = false
    @State private var showProjectMenu = false
    @State private var showFileSelector = false
    @State private var showCodexDefaultPathSelector = false
    @State private var codexDefaultPathVersion = 0
    @State private var showImagePicker = false
    @State private var selectedImages: [UIImage] = []
    @State private var selectedOptions: Set<String> = []
    @State private var isDropTargeted = false
    @State private var isInputDropTargeted = false
    @State private var zoomedImageURL: URL? = nil
    @State private var imageCache: [URL: UIImage] = [:]
    @State private var showMainPage = false
    @State private var showUnpairConfirmation = false
    @State private var modernVoiceFooterHeight: CGFloat = 0
    @State private var modernHeaderHeight: CGFloat = 0
    @State private var isTimelineRailExpanded = false
    @State private var timelinePreviewNode: TimelineNode? = nil
    @State private var textSelection = NSRange(location: 0, length: 0)
    @State private var speechDraftSession = SpeechDraftSession()
    @State private var cachedSpeechRequestId: String? = nil
    @State private var cachedSpeechRequestMessage = ""
    @State private var cachedSpeechRequestTerms: [String] = []
    @State private var isApplyingSpeechUpdate = false
    @State private var speechMuscleMemoryPushInFlight = false
    @State private var speechCorrectionMemoryPushInFlight = false
    @State private var shouldAutoResumeRecording = false
    @State private var tailscaleCandidateRefreshInFlight = false
    @State private var publicTunnelCandidateRefreshInFlight = false
    @State private var pendingSpeechRestart: DispatchWorkItem? = nil
    @State private var pendingVoiceLaunchStart: DispatchWorkItem? = nil
    @State private var lastAutoTrainedPhrase = ""
    @State private var lastSpeechCorrectionObservation: SpeechCorrectionObservation? = nil
    @State private var pendingSpeechCorrectionCandidate: SpeechCorrectionLearningCandidate? = nil
    @State private var suppressPendingSpeechFinalCommit = false
    @State private var activeSpeechInputTarget: SpeechInputTargetSnapshot? = nil
    @State private var normalPromptItems: [PromptItem] = []
    @State private var promptReorderFrames: [String: CGRect] = [:]
    @State private var promptReorderSession = StableLongPressReorderSession()
    @StateObject private var speechManager = SpeechRecognitionManager()
    @StateObject private var codexLiveManager = CodexLiveManager()
    @StateObject private var watchRelay = WatchRelayCoordinator.shared
    @State private var focusedRequestId: String? = nil
    @State private var focusedProjectPath: String? = nil
    @State private var focusedRoutePreviewMessage: String? = nil
    @State private var isManualRouteSelection = false
    @State private var hasRequestedStartupRouteRefresh = false
    @State private var manualRouteRefreshGeneration = 0
    @State private var isInputFocused = false
    @State private var showQuotaSheet = false
    @State private var showGhostSuggestionSheet = false
    @State private var showPromptorLibrary = false
    @State private var showDesktopPairingGuide = false
    @State private var shouldFocusInputAfterPromptorDismiss = false
    @State private var showRelaySettings = false
    @State private var showPhoneActionAlert = false
    @State private var phoneActionAlertTitle = "手机动作消息"
    @State private var phoneActionAlertMessage = ""
    @State private var preventSleepFeedbackText: String? = nil
    @State private var preventSleepFeedbackIsWarning = false
    @State private var pendingPreventSleepTarget: Bool? = nil
    @State private var preventSleepFeedbackGeneration = 0
    @State private var voiceSemanticInputBeforeRecording = ""
    @State private var lastVoiceSemanticRawTranscript = ""
    @State private var lastVoiceSemanticResolvedTranscript = ""
    @State private var pendingVoiceSemanticIntent: VoiceIntent? = nil
    @State private var pendingVoiceSemanticSource: VoiceSemanticActionSource? = nil
    @State private var showVoiceSemanticPreview = false
    @State private var mobilePairingCoordinator = MobilePairingCoordinator()
    @State private var mobilePairingPhase: MobilePairingPhase = .idle
    @State private var activeMobilePairingAttempt: MobilePairingAttempt?

    private struct ActiveShortcutContext {
        let range: NSRange
        let token: String
    }

    private enum VoiceSemanticActionSource {
        case submit
        case goal
    }

    private struct SpeechInputTargetSnapshot {
        let routeIdentity: String
        let requestId: String?
        let projectPath: String?
        let inputBeforeRecording: String
        let selectionBeforeRecording: NSRange
    }

    private var theme: IterateTheme { isDarkMode ? .dark : .light }
    private var currentMessage: MCPMessage? {
        if let focusedMessage = focusedRouteMessage {
            return focusedMessage
        }
        if hasFocusedRouteHint {
            return routePlaceholderMessage
        }
        return webSocketManager.mcpMessages.first(where: {
            renderableRequestMessage($0.payload?.request) != nil
        })
    }
    private var currentRequest: MCPRequest? { currentMessage?.payload?.request }
    private var hasOptions: Bool { !(currentRequest?.predefinedOptions ?? []).isEmpty }
    private var enableContextAppend: Bool { true }
    private var latestRenderableRequest: MCPRequest? {
        webSocketManager.mcpMessages.first(where: {
            renderableRequestMessage($0.payload?.request) != nil
        })?.payload?.request
    }
    private var latestHeadRequestId: String? {
        latestRenderableRequest?.requestId
    }
    private var visibleTimelineProjectPath: String? {
        currentRequest?.projectPath ?? focusedProjectPath
    }
    private var visibleTimelineRequestId: String? {
        currentRequest?.timelineRouteKey ?? focusedRequestId
    }

    @ViewBuilder
    private func mobilePairingBanner() -> some View {
        if mobilePairingPhase.shouldShowBanner {
            Text(mobilePairingPhase.statusText)
                .font(.caption)
                .foregroundStyle(mobilePairingPhase.isFailure ? Color.red : theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }
    private var visibleTimelineNodes: [TimelineNode] {
        webSocketManager.timelineNodes(
            forProjectPath: visibleTimelineProjectPath,
            requestId: visibleTimelineRequestId
        )
    }
    private var visibleTimelineCurrentNodeId: String? {
        webSocketManager.currentTimelineNodeId(
            forProjectPath: visibleTimelineProjectPath,
            requestId: visibleTimelineRequestId
        )
    }
    private var hasDraftPayload: Bool {
        !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedOptions.isEmpty
            || !selectedImages.isEmpty
            || speechManager.isRecording
    }
    private var isHoldingDraftInput: Bool {
        hasDraftPayload
    }
    private var isCurrentRouteWaitingForReply: Bool {
        if currentRequest?.requestId != nil || currentRequest?.projectPath != nil {
            return webSocketManager.waitingStatus(
                projectPath: currentRequest?.projectPath,
                requestId: currentRequest?.requestId
            )
        }
        return webSocketManager.isWaitingForReply
    }
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

    private var isConnectionRouteConfigured: Bool {
        ServerConfig.hasConfiguredWebSocketURL(serverURL)
    }

    private var shouldShowDesktopCompanionOnboarding: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--force-desktop-companion-onboarding") {
            return true
        }
#endif
        return CompanionOnboardingPolicy.shouldShow(
            hasConfiguredRoute: isConnectionRouteConfigured,
            hasDeviceAuthorization: hasDeviceAuthorization
        )
    }

    private var isAppBackgroundedForConnectionStatus: Bool {
        scenePhase == .inactive || scenePhase == .background
    }

    private var connectionPresentationState: ConnectionPresentationState {
        ConnectionPresentationState.resolve(
            isConfigured: isConnectionRouteConfigured,
            requiresDeviceRePairing: webSocketManager.requiresDeviceRePairing,
            isWaitingForReply: isCurrentRouteWaitingForReply,
            isConnected: webSocketManager.isConnected,
            isConnecting: webSocketManager.isConnecting,
            isReconnecting: webSocketManager.isReconnecting,
            isRecoveryGraceActive: webSocketManager.isConnectionRecoveryGraceActive,
            isRouteSwitching: webSocketManager.isRouteSwitching,
            isAppBackgrounded: isAppBackgroundedForConnectionStatus,
            hasEverConnected: webSocketManager.hasEverConnected
        )
    }

    private var connectionStatus: String {
        connectionPresentationState.title
    }

    private var statusDotColor: Color {
        switch connectionPresentationState.dot {
        case .success:
            return theme.success
        case .warning:
            return theme.warning
        case .accent:
            return .blue
        case .error:
            return theme.error
        case .neutral:
            return theme.textSecondary
        }
    }

    private var projectName: String {
        if let path = currentRequest?.projectPath, !path.isEmpty {
            return path.split(separator: "/").last.map(String.init) ?? path
        }
        return "等待中"
    }

    private var syncRequestIdHint: String? {
        focusedRequestId
            ?? currentRequest?.requestId
            ?? webSocketManager.mcpMessages.first?.payload?.request?.requestId
    }

    private var syncProjectPathHint: String? {
        focusedProjectPath
            ?? currentRequest?.projectPath
            ?? webSocketManager.mcpMessages.first?.payload?.request?.projectPath
    }

    private var activeSessionsBaseURL: String {
        serverURL
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")
            .replacingOccurrences(of: "/ws", with: "")
    }

    private var activeSessionsCacheKey: String {
        if webSocketManager.currentTransportMode == "relay",
           let relayBaseURL = normalizedRelayControlBaseURL() {
            let configuredMacDeviceID = relayMacDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let macDeviceID = configuredMacDeviceID.isEmpty ? "local-mac" : configuredMacDeviceID
            return "\(relayBaseURL)/api/devices/\(relayPathComponent(macDeviceID))"
        }
        return activeSessionsBaseURL
    }

    private func activeSessionsRequest() -> URLRequest? {
        if webSocketManager.currentTransportMode == "relay",
           let relayBaseURL = normalizedRelayControlBaseURL() {
            let configuredMacDeviceID = relayMacDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let macDeviceID = configuredMacDeviceID.isEmpty ? "local-mac" : configuredMacDeviceID
            guard let url = URL(string: "\(relayBaseURL)/api/devices/\(relayPathComponent(macDeviceID))/sessions") else {
                return nil
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 8
            applyRelayHeaders(to: &request)
            return request
        }

        guard let url = URL(string: "\(activeSessionsBaseURL)/api/active-sessions") else {
            return nil
        }
        return DeviceAuthStore.authorizedRequest(url: url)
    }

    private var hasFocusedRouteHint: Bool {
        let requestId = focusedRequestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let projectPath = focusedProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !requestId.isEmpty || !projectPath.isEmpty
    }

    private var currentRouteIdentity: String {
        routeIdentity(
            for: currentRequest,
            fallbackRequestId: focusedRequestId,
            fallbackProjectPath: focusedProjectPath
        )
    }

    private func normalizedRouteComponent(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private func routeIdentity(
        for request: MCPRequest?,
        fallbackRequestId: String?,
        fallbackProjectPath: String?
    ) -> String {
        let routeId = normalizedRouteComponent(request?.timelineRouteKey)
            ?? normalizedRouteComponent(request?.requestId)
            ?? normalizedRouteComponent(fallbackRequestId)
        let projectPath = normalizedRouteComponent(request?.projectPath)
            ?? normalizedRouteComponent(fallbackProjectPath)

        switch (routeId, projectPath) {
        case let (routeId?, projectPath?):
            return "request:\(routeId)|project:\(projectPath)"
        case let (routeId?, nil):
            return "request:\(routeId)"
        case let (nil, projectPath?):
            return "project:\(projectPath)"
        default:
            return "none"
        }
    }

    private var focusedRouteMessage: MCPMessage? {
        if let focusedRequestId,
           !focusedRequestId.isEmpty,
           let focusedMessage = webSocketManager.mcpMessages.first(where: {
               $0.payload?.request?.requestId == focusedRequestId
                   && renderableRequestMessage($0.payload?.request) != nil
           }) {
            return focusedMessage
        }
        if let focusedProjectPath,
           !focusedProjectPath.isEmpty,
           let focusedMessage = webSocketManager.mcpMessages.first(where: {
               $0.payload?.request?.projectPath == focusedProjectPath
                   && renderableRequestMessage($0.payload?.request) != nil
           }) {
            return focusedMessage
        }
        return nil
    }

    private func renderableRequestMessage(_ request: MCPRequest?) -> String? {
        guard let message = request?.message,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return message
    }

    private var isFocusedRouteLoadFailure: Bool {
        guard let failure = webSocketManager.projectSwitchFailure else { return false }
        if let requestId = failure.requestId, !requestId.isEmpty {
            return requestId == focusedRequestId
        }
        if let projectPath = failure.projectPath, !projectPath.isEmpty {
            return projectPath == focusedProjectPath
        }
        return false
    }

    private var routePlaceholderMessage: MCPMessage? {
        let routeRequestId = focusedRequestId
        let routeProjectPath = focusedProjectPath
        guard routeRequestId != nil || routeProjectPath != nil else { return nil }

        let projectName = routeProjectPath?
            .split(separator: "/")
            .last
            .map(String.init)
            ?? "目标项目"
        let stableId = routeRequestId ?? routeProjectPath ?? "route-placeholder"
        let normalizedPreview = focusedRoutePreviewMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholderMessage: String
        if isFocusedRouteLoadFailure {
            placeholderMessage = "未能加载 \(projectName)。请重新同步或返回最新消息。"
        } else if let normalizedPreview, !normalizedPreview.isEmpty {
            placeholderMessage = normalizedPreview
        } else {
            placeholderMessage = "正在加载 \(projectName)..."
        }

        return MCPMessage(
            id: "route-placeholder-\(stableId)",
            messageType: "mcp_state",
            payload: MCPPayload(
                request: MCPRequest(
                    requestId: routeRequestId,
                    message: placeholderMessage,
                    browserAiResponse: nil,
                    projectPath: routeProjectPath,
                    predefinedOptions: [],
                    inputPlaceholder: nil
                ),
                response: nil,
                customPrompts: nil
            )
        )
    }

    private func shouldAutoAdoptLatestHeadRequest(_ latestRequestId: String) -> Bool {
        guard !latestRequestId.isEmpty else { return false }
        if focusedRequestId == latestRequestId {
            return false
        }
        if isManualRouteSelection {
            return false
        }
        guard hasFocusedRouteHint else { return true }
        return true
    }

    private func adoptLatestHeadRequest(_ latestRequestId: String) {
        let latestRequest = webSocketManager.mcpMessages.first(where: {
            $0.payload?.request?.requestId == latestRequestId
                && renderableRequestMessage($0.payload?.request) != nil
        })?.payload?.request
        focusedRequestId = latestRequest?.requestId ?? latestRequestId
        focusedProjectPath = latestRequest?.projectPath
        focusedRoutePreviewMessage = nil
        isManualRouteSelection = false
    }

    private func pinFocusedRouteToCurrentMessageIfNeeded() {
        guard !hasFocusedRouteHint,
              let request = currentMessage?.payload?.request else {
            return
        }
        focusedRequestId = request.requestId
        focusedProjectPath = request.projectPath
        focusedRoutePreviewMessage = nil
    }

    private func requestSyncForCurrentRoute() {
        webSocketManager.recoverAndSync(
            projectPath: syncProjectPathHint,
            requestId: syncRequestIdHint,
            reason: "current_route_sync"
        )
    }

    private func refreshCurrentRouteManually() async {
        manualRouteRefreshGeneration &+= 1
        if let projectPath = syncProjectPathHint,
           !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            webSocketManager.retryProjectSwitch(
                projectPath: projectPath,
                requestId: syncRequestIdHint
            )
        } else {
            webSocketManager.recoverAndSync(
                projectPath: nil,
                requestId: syncRequestIdHint,
                reason: "manual_pull_to_refresh"
            )
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
    }

    private func returnToLatestMessage() {
        webSocketManager.cancelProjectSwitchRecovery(reason: "return_latest")
        webSocketManager.discardCachedRoute(
            requestId: syncRequestIdHint,
            projectPath: syncProjectPathHint
        )
        if let latestRequest = latestRenderableRequest {
            focusedRequestId = latestRequest.requestId
            focusedProjectPath = latestRequest.projectPath
            focusedRoutePreviewMessage = nil
            isManualRouteSelection = false
        } else {
            focusedRequestId = nil
            focusedProjectPath = nil
            focusedRoutePreviewMessage = nil
            isManualRouteSelection = false
        }
    }

    private var routeRecoveryActions: some View {
        HStack(spacing: 8) {
            Button {
                webSocketManager.retryProjectSwitch(
                    projectPath: syncProjectPathHint,
                    requestId: syncRequestIdHint
                )
            } label: {
                Label {
                    Text("重新同步")
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)

            Button {
                returnToLatestMessage()
            } label: {
                Label {
                    Text("返回最新消息")
                } icon: {
                    Image(systemName: "arrow.uturn.backward")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func appendPromptContent(_ content: String) {
        guard !content.isEmpty else { return }

        let separator: String
        if userInput.isEmpty
            || userInput.hasSuffix("\n")
            || userInput.hasSuffix(" ")
            || content.hasPrefix("\n")
            || content.hasPrefix(" ") {
            separator = ""
        } else {
            separator = "\n"
        }

        let updatedText = userInput + separator + content
        userInput = updatedText
        textSelection = NSRange(location: (updatedText as NSString).length, length: 0)
    }

    private func focusInputAfterPromptorSelectionIfNeeded() {
        guard shouldFocusInputAfterPromptorDismiss else { return }
        shouldFocusInputAfterPromptorDismiss = false
        DispatchQueue.main.async {
            isInputFocused = true
        }
    }

    private func appendSelectedQuote(_ selectedText: String) {
        guard let update = SelectedQuoteComposer.appending(selection: selectedText, to: userInput) else {
            return
        }

        userInput = update.text
        textSelection = update.selection
        isInputFocused = true
    }

    private func searchSelectedText(_ selectedText: String) {
        let query = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let searchURL = googleSearchURL(for: query) else {
            return
        }

        UIApplication.shared.open(searchURL, options: [:])
    }

    private var activeShortcutContext: ActiveShortcutContext? {
        guard textSelection.length == 0 else { return nil }

        let text = userInput as NSString
        let cursorLocation = min(textSelection.location, text.length)
        guard cursorLocation > 0 else { return nil }

        let prefixText = text.substring(to: cursorLocation)
        guard let regex = try? NSRegularExpression(pattern: #"[[:alpha:]\p{Han}][[:alnum:]\p{Han}._:-]*$"#) else {
            return nil
        }

        let searchRange = NSRange(location: 0, length: (prefixText as NSString).length)
        guard let match = regex.matches(in: prefixText, range: searchRange).last else {
            return nil
        }

        let token = (prefixText as NSString).substring(with: match.range)
        guard !token.isEmpty else { return nil }

        return ActiveShortcutContext(range: match.range, token: token)
    }

    private var activeShortcutSuggestion: ShortcutSuggestion? {
        guard let context = activeShortcutContext else { return nil }

        let token = context.token.lowercased()
        guard !token.isEmpty else { return nil }

        return visibleShortcutSuggestion(mergedShortcutSuggestions, token: token)
    }

    private var syncedGhostShortcutSuggestions: [ShortcutSuggestion]? {
        guard let store = webSocketManager.ghostSuggestionStore,
              !store.suggestions.isEmpty else {
            return nil
        }

        return store.suggestions
            .filter { $0.enabled }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { suggestion in
                ShortcutSuggestion(
                    key: suggestion.key,
                    description: suggestion.description.isEmpty ? "幽灵补全" : suggestion.description
                )
            }
    }

    private var mergedShortcutSuggestions: [ShortcutSuggestion] {
        var merged = [ShortcutSuggestion]()
        var seen = Set<String>()
        let baseSuggestions = syncedGhostShortcutSuggestions ?? baseShortcutSuggestions

        for suggestion in baseSuggestions + seededShortcutSuggestions + projectShortcutSuggestions {
            let normalizedKey = suggestion.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty, seen.insert(normalizedKey).inserted else { continue }
            merged.append(.init(key: normalizedKey, description: suggestion.description))
        }

        return merged
    }

    private var projectShortcutSuggestions: [ShortcutSuggestion] {
        var suggestions = [ShortcutSuggestion]()

        if let projectPath = currentRequest?.projectPath,
           let projectName = projectPath.split(separator: "/").last.map(String.init),
           let normalized = normalizeShortcutTerm(projectName) {
            let key = canonicalizeShortcutTerm(normalized)
            suggestions.append(.init(key: key, description: "当前项目词"))
        }

        return suggestions
    }

    private var activeShortcutGhostText: String? {
        guard let context = activeShortcutContext,
              let suggestion = activeShortcutSuggestion else {
            return nil
        }

        let typedCount = context.token.count
        guard suggestion.key.count > typedCount else { return nil }
        return String(suggestion.key.dropFirst(typedCount))
    }

    private func acceptShortcutSuggestion(_ suggestion: ShortcutSuggestion) {
        guard let context = activeShortcutContext else { return }

        let currentText = userInput as NSString
        let updatedText = currentText.replacingCharacters(in: context.range, with: suggestion.key)
        let nextLocation = context.range.location + (suggestion.key as NSString).length
        userInput = updatedText
        textSelection = NSRange(location: nextLocation, length: 0)
        webSocketManager.recordGhostSuggestionLearning(
            event: "accepted",
            terms: [(key: suggestion.key, description: suggestion.description)]
        )
    }

    private func recordSubmittedGhostSuggestionLearning(from text: String) {
        let terms = GhostSuggestionLearning.extractTerms(from: text)
            .map { (key: $0, description: "自动学习 / 手动输入高频候选") }
        webSocketManager.recordGhostSuggestionLearning(event: "typed", terms: terms)
    }

    private var voiceSemanticPreviewTitle: String {
        guard let intent = pendingVoiceSemanticIntent else {
            return "语音理解预览"
        }

        switch intent.kind {
        case .selectOption:
            return "选择选项"
        case .submit:
            return "确认发送"
        case .goal:
            return "确认目标"
        case .shortcut:
            return "套用快捷词"
        case .command:
            return "确认语音动作"
        case .editCurrentInput:
            return "更新输入"
        case .clarify:
            return "需要确认"
        case .fillText, .noAction:
            return "语音理解预览"
        }
    }

    private var voiceSemanticPreviewMessage: String {
        guard let intent = pendingVoiceSemanticIntent else {
            return ""
        }

        var lines = [voiceSemanticIntentSummary(intent)]
        if !intent.reason.isEmpty {
            lines.append("原因：\(intent.reason)")
        }
        if intent.needsConfirmation {
            lines.append("此动作需要确认后才会继续。")
        }
        return lines.joined(separator: "\n")
    }

    private func voiceSemanticIntentSummary(_ intent: VoiceIntent) -> String {
        switch intent.kind {
        case .selectOption:
            let labels = intent.selectedOptionLabels.joined(separator: "、")
            return labels.isEmpty ? "选择匹配到的选项" : "选择：\(labels)"
        case .submit:
            return "发送：\(intent.preview)"
        case .goal:
            return "设为目标：\(intent.preview)"
        case .shortcut:
            let shortcut = intent.shortcut ?? ""
            return "快捷词：\(shortcut)\n内容：\(intent.preview)"
        case .command:
            return "动作：\(intent.command ?? "command")\n内容：\(intent.preview)"
        case .editCurrentInput:
            return "更新输入为：\(intent.preview)"
        case .clarify:
            return intent.preview.isEmpty ? "需要进一步确认" : intent.preview
        case .fillText:
            return "文本：\(intent.preview)"
        case .noAction:
            return "没有可执行动作"
        }
    }

    private func voiceSemanticShortcuts() -> [VoiceSemanticShortcut] {
        mergedShortcutSuggestions.map {
            VoiceSemanticShortcut(key: $0.key, description: $0.description)
        }
    }

    private func currentVoiceSemanticTranscript() -> String? {
        let resolved = lastVoiceSemanticResolvedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolved.isEmpty {
            return resolved
        }

        let raw = lastVoiceSemanticRawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    private func voiceSemanticCurrentInput(fallback: String) -> String {
        let beforeRecording = voiceSemanticInputBeforeRecording.trimmingCharacters(in: .whitespacesAndNewlines)
        if !beforeRecording.isEmpty {
            return beforeRecording
        }

        let normalizedFallback = SpeechCorrectionMemoryStore.normalize(fallback)
        let normalizedTranscript = currentVoiceSemanticTranscript().map(SpeechCorrectionMemoryStore.normalize) ?? ""
        if !normalizedTranscript.isEmpty, normalizedFallback == normalizedTranscript {
            return ""
        }

        return fallback
    }

    private func shouldPresentVoiceSemanticPreview(for intent: VoiceIntent) -> Bool {
        switch intent.kind {
        case .selectOption, .submit, .goal, .shortcut, .command, .editCurrentInput, .clarify:
            return true
        case .fillText, .noAction:
            return false
        }
    }

    private func presentVoiceSemanticPreviewIfNeeded(
        source: VoiceSemanticActionSource,
        finalInput: String
    ) -> Bool {
        guard let transcript = currentVoiceSemanticTranscript() else {
            return false
        }

        let normalizedTranscript = SpeechCorrectionMemoryStore.normalize(transcript)
        let normalizedInput = SpeechCorrectionMemoryStore.normalize(userInput)
        guard !normalizedTranscript.isEmpty,
              !normalizedInput.isEmpty,
              normalizedInput.contains(normalizedTranscript) || normalizedTranscript.contains(normalizedInput) else {
            return false
        }

        let context = VoiceSemanticContext(
            rawTranscript: transcript,
            currentRequestMessage: currentRequest?.message,
            predefinedOptions: currentRequest?.predefinedOptions ?? [],
            selectedOptions: orderedSelectedOptions,
            currentInput: voiceSemanticCurrentInput(fallback: finalInput),
            projectPath: currentRequest?.projectPath,
            shortcuts: voiceSemanticShortcuts(),
            constraints: [],
            mode: source == .goal ? .goal : .reply
        )
        let intent = VoiceSemanticResolver().resolve(context)
        guard shouldPresentVoiceSemanticPreview(for: intent) else {
            return false
        }

        pendingVoiceSemanticIntent = intent
        pendingVoiceSemanticSource = source
        showVoiceSemanticPreview = true
        return true
    }

    private func clearPendingVoiceSemanticIntent() {
        pendingVoiceSemanticIntent = nil
        pendingVoiceSemanticSource = nil
        showVoiceSemanticPreview = false
    }

    private func clearVoiceSemanticSpeechState() {
        voiceSemanticInputBeforeRecording = ""
        lastVoiceSemanticRawTranscript = ""
        lastVoiceSemanticResolvedTranscript = ""
    }

    private func restoreInputBeforeVoiceSemanticCommand() {
        let restored = voiceSemanticInputBeforeRecording
        userInput = restored
        textSelection = NSRange(location: (restored as NSString).length, length: 0)
    }

    private func applyPendingVoiceSemanticIntent() {
        guard let intent = pendingVoiceSemanticIntent,
              let source = pendingVoiceSemanticSource else {
            clearPendingVoiceSemanticIntent()
            return
        }

        clearPendingVoiceSemanticIntent()

        switch intent.kind {
        case .selectOption:
            applyVoiceSemanticOptionSelection(intent)
            restoreInputBeforeVoiceSemanticCommand()
            clearVoiceSemanticSpeechState()
        case .shortcut:
            let nextText = intent.preview.trimmingCharacters(in: .whitespacesAndNewlines)
            userInput = nextText
            textSelection = NSRange(location: (nextText as NSString).length, length: 0)
            clearVoiceSemanticSpeechState()
        case .editCurrentInput, .fillText:
            let nextText = intent.text ?? intent.preview
            userInput = nextText
            textSelection = NSRange(location: (nextText as NSString).length, length: 0)
            clearVoiceSemanticSpeechState()
        case .submit:
            if let text = intent.text {
                userInput = text
                textSelection = NSRange(location: (text as NSString).length, length: 0)
            }
            submitCurrentResponse(allowVoiceSemanticPreview: false)
        case .goal:
            if let text = intent.text {
                userInput = text
                textSelection = NSRange(location: (text as NSString).length, length: 0)
            }
            sendCurrentGoal(allowVoiceSemanticPreview: false)
        case .command:
            restoreInputBeforeVoiceSemanticCommand()
            clearVoiceSemanticSpeechState()
            webSocketManager.addMessage("语音动作已确认：\(voiceSemanticIntentSummary(intent))")
        case .clarify:
            webSocketManager.addMessage("语音需要确认：\(voiceSemanticIntentSummary(intent))")
        case .noAction:
            break
        }

        if source == .goal, intent.kind != .goal {
            pushWatchRelayState(reason: "voice_semantic_goal_preview")
        }
    }

    private func applyVoiceSemanticOptionSelection(_ intent: VoiceIntent) {
        let options = currentRequest?.predefinedOptions ?? []
        var labels = intent.selectedOptionLabels

        if labels.isEmpty {
            labels = intent.selectedOptionIndexes.compactMap { index in
                options.indices.contains(index) ? options[index] : nil
            }
        }

        for label in labels where options.contains(label) {
            selectedOptions.insert(label)
        }

        if !labels.isEmpty {
            webSocketManager.addMessage("已按语音选择：\(labels.joined(separator: "、"))")
        }
    }

    private func captureSpeechInputTarget() -> SpeechInputTargetSnapshot {
        let request = currentRequest
        let requestId = normalizedRouteComponent(request?.timelineRouteKey)
            ?? normalizedRouteComponent(request?.requestId)
            ?? normalizedRouteComponent(focusedRequestId)
        let projectPath = normalizedRouteComponent(request?.projectPath)
            ?? normalizedRouteComponent(focusedProjectPath)

        return SpeechInputTargetSnapshot(
            routeIdentity: routeIdentity(
                for: request,
                fallbackRequestId: requestId,
                fallbackProjectPath: projectPath
            ),
            requestId: requestId,
            projectPath: projectPath,
            inputBeforeRecording: userInput,
            selectionBeforeRecording: textSelection
        )
    }

    private func restoreSpeechInputTargetIfNeeded() {
        guard let target = activeSpeechInputTarget,
              currentRouteIdentity != target.routeIdentity else {
            return
        }

        focusedRequestId = target.requestId
        focusedProjectPath = target.projectPath
        focusedRoutePreviewMessage = nil
        isManualRouteSelection = target.requestId != nil || target.projectPath != nil
        if let projectPath = target.projectPath {
            webSocketManager.prepareProjectSwitch(to: projectPath)
        }

        userInput = target.inputBeforeRecording
        textSelection = target.selectionBeforeRecording
        speechDraftSession.begin(at: target.selectionBeforeRecording)
        print(
            "[Speech] restored input target during recording: request_id=\(target.requestId ?? "nil") " +
            "project_path=\(target.projectPath ?? "nil")"
        )
    }

    private func handleCurrentRouteIdentityChange() {
        pushWatchRelayState(reason: "current_message_changed")
        pinFocusedRouteToCurrentMessageIfNeeded()

        if speechManager.isRecording || activeSpeechInputTarget != nil {
            restoreSpeechInputTargetIfNeeded()
            print(
                "[MCP UI] 当前消息刷新时保留语音输入: route=\(currentRouteIdentity), " +
                "speechTarget=\(activeSpeechInputTarget?.routeIdentity ?? "nil")"
            )
        } else {
            resetInputState()
        }

        // 收到新 MCP 消息时自动退出主页面 WebView
        if showMainPage {
            showMainPage = false
        }
        print(
            "[MCP UI] 当前消息切换: focused=\(focusedRequestId ?? "无"), " +
            "project_path=\(focusedProjectPath ?? "无"), " +
            "resolved=\(currentMessage?.payload?.request?.requestId ?? "无"), " +
            "head=\(webSocketManager.mcpMessages.first?.payload?.request?.requestId ?? "无")"
        )
    }

    private var requestStatusText: String {
        if isCurrentRouteWaitingForReply {
            return "已发送，等待回复"
        }
        return currentMessage == nil ? "等待中" : "正在等待指令"
    }

    private func setTimelineRailExpanded(_ expanded: Bool) {
        guard !expanded || !visibleTimelineNodes.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isTimelineRailExpanded = expanded
        }
    }

    private var timelinePreviewReservedRailWidth: CGFloat {
        isTimelineRailExpanded ? 72 : 0
    }

    private func setTimelinePreviewNode(_ node: TimelineNode, toggleIfCurrent: Bool) {
        guard !node.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            if toggleIfCurrent, timelinePreviewNode?.id == node.id {
                timelinePreviewNode = nil
            } else {
                timelinePreviewNode = node
            }
        }
    }

    private func presentTimelinePreview(_ node: TimelineNode) {
        setTimelinePreviewNode(node, toggleIfCurrent: true)
    }

    private func updateTimelinePreviewFromRail(_ node: TimelineNode) {
        guard timelinePreviewNode != nil else { return }
        guard timelinePreviewNode?.id != node.id else { return }
        setTimelinePreviewNode(node, toggleIfCurrent: false)
    }

    private func dismissTimelinePreview() {
        withAnimation(.easeInOut(duration: 0.16)) {
            timelinePreviewNode = nil
        }
    }

    private func insertTimelinePreviewQuote(_ node: TimelineNode) {
        let content = stripAutoPrompt(node.content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        if userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userInput = content
        } else {
            let separator = userInput.hasSuffix("\n") || content.hasPrefix("\n") ? "\n" : "\n\n"
            userInput = "\(userInput)\(separator)\(content)"
        }
        isInputFocused = true
        dismissTimelinePreview()
    }

    private func timelineNodeTypeLabel(_ node: TimelineNode) -> String {
        node.nodeType == "user" ? "用户" : "助手"
    }

    private func timelineNodeAnchors(_ node: TimelineNode) -> [String] {
        [
            node.requestId.map { "req \($0)" },
            node.projectPath?.split(separator: "/").last.map { "src \($0)" },
        ].compactMap { $0 }
    }

    private func timelineTimeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var timelineEdgePanInstaller: some View {
        TimelineEdgePanInstaller(
            isRevealEnabled: !isTimelineRailExpanded && !visibleTimelineNodes.isEmpty,
            isDismissEnabled: isTimelineRailExpanded && !visibleTimelineNodes.isEmpty,
            onReveal: {
                setTimelineRailExpanded(true)
            },
            onDismiss: {
                setTimelineRailExpanded(false)
            }
        )
    }

    private func timelineDotRail(
        availableHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> some View {
        let visibleHeight = max(0, availableHeight - topInset - bottomInset)

        return TimelineDotBar(
            nodes: visibleTimelineNodes,
            currentNodeId: visibleTimelineCurrentNodeId,
            theme: theme,
            showsScrubPreview: timelinePreviewNode == nil,
            formatTime: timelineTimeLabel,
            onDotTap: { node in
                presentTimelinePreview(node)
            },
            onScrubNodeChange: { node in
                updateTimelinePreviewFromRail(node)
            }
        )
        .frame(height: visibleHeight, alignment: .top)
        .padding(.top, topInset)
        .padding(.trailing, 8)
    }

    @ViewBuilder
    private var timelinePreviewOverlay: some View {
        if let node = timelinePreviewNode {
            GeometryReader { geometry in
                let railReserve = timelinePreviewReservedRailWidth
                let horizontalMargin: CGFloat = 14
                let availableWidth = max(220, geometry.size.width - railReserve - horizontalMargin * 2)
                let cardWidth = min(availableWidth, 520)
                let cardTrailing = max(horizontalMargin + cardWidth, geometry.size.width - railReserve - horizontalMargin)
                let cardCenterX = cardTrailing - cardWidth / 2

                ZStack {
                    HStack(spacing: 0) {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                dismissTimelinePreview()
                            }
                            .frame(width: max(0, geometry.size.width - railReserve))

                        Color.clear
                            .frame(width: railReserve)
                            .allowsHitTesting(false)
                    }
                    .ignoresSafeArea()

                    timelinePreviewCard(node: node, geometry: geometry)
                        .frame(width: cardWidth)
                        .frame(maxHeight: min(geometry.size.height * 0.64, 520))
                        .position(x: cardCenterX, y: geometry.size.height / 2)
                        .zIndex(1)
                }
            }
            .transition(.opacity)
            .zIndex(90)
        }
    }

    private func timelinePreviewCard(node: TimelineNode, geometry: GeometryProxy) -> some View {
        let content = stripAutoPrompt(node.content)
        let anchors = timelineNodeAnchors(node)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(timelineNodeTypeLabel(node))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))

                if node.id == visibleTimelineCurrentNodeId {
                    Text("当前锚点")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#bfdbfe"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(hex: "#3b82f6").opacity(0.22))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 8)

                Button {
                    insertTimelinePreviewQuote(node)
                } label: {
                    Text("引用")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Text(timelineTimeLabel(node.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.42))

                Button {
                    dismissTimelinePreview()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.64))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            ScrollView(.vertical, showsIndicators: true) {
                Text(content)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .foregroundColor(.white.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.trailing, 4)
            }
            .frame(maxHeight: min(geometry.size.height * 0.46, 380))

            if !anchors.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(anchors, id: \.self) { anchor in
                        Text(anchor)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.white.opacity(0.74))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(hex: "#1a1a1a"))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.42), radius: 16, x: 0, y: 8)
    }

    private func handleNotificationRoute(_ routeInfo: [String: String], reason: String) {
        showProjectMenu = false
        showFileSelector = false
        showImagePicker = false
        showRelaySettings = false

        let projectPath = routeInfo["project_path"]
        let requestId = routeInfo["request_id"]
        focusedRequestId = requestId
        focusedProjectPath = projectPath
        focusedRoutePreviewMessage = nil
        isManualRouteSelection = requestId != nil || projectPath != nil

        print(
            "[Notification Timing] route consumed: reason=\(reason) request_id=\(requestId ?? "nil") " +
            "project_path=\(projectPath ?? "nil") connected=\(webSocketManager.isConnected) " +
            "connecting=\(webSocketManager.isConnecting) reconnecting=\(webSocketManager.isReconnecting)"
        )

        if let projectPath, !projectPath.isEmpty {
            webSocketManager.prepareProjectSwitch(to: projectPath)
            webSocketManager.recoverAndSync(projectPath: projectPath, requestId: requestId, reason: reason)
        } else {
            webSocketManager.recoverAndSync(projectPath: nil, requestId: requestId, reason: reason)
        }
    }

    @ViewBuilder
    private var appContent: some View {
        if showMainPage {
            InlineWebView(
                serverURL: serverURL,
                onGhostSuggestionSettingsRequested: {
                    showGhostSuggestionSheet = true
                }
            )
            .padding(.top, homeTopPadding)
        } else {
            requestPage
        }
    }

    private var homeTopPadding: CGFloat {
        if #available(iOS 26.0, *) {
            return modernHeaderScrollPadding
        }
        return 0
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            CodexLiveWebRTCView(manager: codexLiveManager)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if shouldShowDesktopCompanionOnboarding {
                DesktopCompanionOnboardingView {
                    showDesktopPairingGuide = true
                }
                .transition(.opacity)
            } else if #available(iOS 26.0, *) {
                appContent
                    .overlay(alignment: .top) {
                        VStack(spacing: 0) {
                            headerBar
                            mobilePairingBanner()
                        }
                    }
            } else {
                VStack(spacing: 0) {
                    headerBar
                    mobilePairingBanner()
                    appContent
                }
            }

            timelinePreviewOverlay

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
        .preferredColorScheme(
            shouldShowDesktopCompanionOnboarding ? nil : (isDarkMode ? .dark : .light)
        )
        .alert(phoneActionAlertTitle, isPresented: $showPhoneActionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(phoneActionAlertMessage)
        }
        .alert(voiceSemanticPreviewTitle, isPresented: $showVoiceSemanticPreview) {
            Button("取消", role: .cancel) {
                clearPendingVoiceSemanticIntent()
            }
            Button("确认") {
                applyPendingVoiceSemanticIntent()
            }
        } message: {
            Text(voiceSemanticPreviewMessage)
        }
        .onAppear {
            hasDeviceAuthorization = DeviceAuthStore.load() != nil
            configureTransportFallbackHandler()
            configureRelayCommandTransport()
            watchRelay.onAction = handleWatchRelayAction
            let startupURL = preferredAuthenticatedStartupURL()
            if startupURL != serverURL {
                serverURL = startupURL
                UserDefaults.standard.set(startupURL, forKey: ServerConfig.storageKey)
                print("[Connection] authenticated startup prefers cached public bridge")
            }
            let connectionURL = webSocketManager.resolvedWebSocketURL(preferredURL: startupURL)
            if !consumePendingPairingURL(), ServerConfig.hasConfiguredWebSocketURL(connectionURL) {
                webSocketManager.connect(to: startupURL)
            }
            pushWatchRelayState(reason: "appear")
            syncNormalPromptItems()
#if DEBUG
            applyDebugSpeechCorrectionSeedsIfNeeded()
#endif
            if !shouldShowDesktopCompanionOnboarding {
#if targetEnvironment(simulator)
                if ProcessInfo.processInfo.environment["ITERATE_SIMULATOR_REQUEST_SPEECH_AUTH"] == "1" {
                    speechManager.requestAuthorization()
                }
#else
                speechManager.requestAuthorization()
#endif
            }
            _ = consumePendingVoiceLaunch(reason: "appear")
            _ = consumePendingPhoneActionURL(reason: "appear")
            if let pendingNotificationRoute = NotificationRouteBridge.consumePendingRoute() {
                handleNotificationRoute(pendingNotificationRoute, reason: "notification_click_cold_start")
            }
            resumePendingPhoneActionIfNeeded(reason: "appear")
            pushSpeechMuscleMemoryToBridgeIfNeeded(reason: "appear")
            syncSpeechCorrectionMemoryFromBridge(reason: "appear")
            syncSpeechVocabularyFromBridge(reason: "appear")
            attemptRelayAutoRecoveryIfNeeded(reason: "appear")
        }
        .onOpenURL { url in
            handleIterateURL(url, reason: "openURL")
        }
        .onChange(of: webSocketManager.isConnected) { connected in
            if connected && !hasRequestedStartupRouteRefresh {
                hasRequestedStartupRouteRefresh = true
                webSocketManager.recoverAndSync(
                    projectPath: syncProjectPathHint,
                    requestId: syncRequestIdHint,
                    reason: "startup_connected_refresh"
                )
            }
            guard connected,
                  mobilePairingPhase == .connecting,
                  let attempt = activeMobilePairingAttempt,
                  mobilePairingCoordinator.finish(attempt: attempt, connected: true) else { return }
            mobilePairingPhase = mobilePairingCoordinator.phase
            activeMobilePairingAttempt = nil
            (UIApplication.shared.delegate as? AppDelegate)?
                .requestNotificationPermission(UIApplication.shared)
        }
        .onChange(of: webSocketManager.preventSleepEnabled) { enabled in
            guard let target = pendingPreventSleepTarget else { return }
            pendingPreventSleepTarget = nil

            if enabled == target {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showPreventSleepFeedback(
                    enabled ? "合盖运行已开启 · 接电时生效" : "合盖运行已关闭",
                    duration: 2.4
                )
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                showPreventSleepFeedback("状态未切换，请稍后重试", duration: 2.6, isWarning: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: PairingURLBridge.notificationName)) { notification in
            if let url = notification.object as? URL {
                applyPairingURL(url)
            } else {
                _ = consumePendingPairingURL()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: VoiceLaunchBridge.notificationName)) { notification in
            if let url = notification.object as? URL {
                handleVoiceLaunchURL(url, reason: "notification")
            } else {
                _ = consumePendingVoiceLaunch(reason: "notification")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: PhoneActionURLBridge.notificationName)) { notification in
            if let url = notification.object as? URL {
                handlePhoneActionURL(url, reason: "notification")
            } else {
                _ = consumePendingPhoneActionURL(reason: "notification")
            }
        }
        .onReceive(webSocketManager.$pendingPhoneAction.compactMap { $0 }) { request in
            handlePhoneActionRequest(request, reason: "websocket")
            webSocketManager.clearPendingPhoneAction(id: request.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: DeviceAuthStore.authClearedNotification)) { notification in
            let reason = (notification.userInfo?["reason"] as? String) ?? "unknown"
            hasDeviceAuthorization = false
            webSocketManager.pauseForDeviceRePairing(reason: reason)
            print("[DeviceAuth] auth cleared notification reason=\(reason)")
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationRouteBridge.notificationName)) { notification in
            NotificationRouteBridge.clearPendingRoute()
            handleNotificationRoute(notification.userInfo as? [String: String] ?? [:], reason: "notification_click")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("APNsMessageReceived"))) { notification in
            let routeInfo = notification.object as? [AnyHashable: Any]
            let projectPath = routeInfo?["project_path"] as? String
            let requestId = routeInfo?["request_id"] as? String
            pinFocusedRouteToCurrentMessageIfNeeded()
            print(
                "[Notification Timing] APNsMessageReceived sync trigger: " +
                "request_id=\(requestId ?? syncRequestIdHint ?? "nil") project_path=\(projectPath ?? syncProjectPathHint ?? "nil") " +
                "connected=\(webSocketManager.isConnected) connecting=\(webSocketManager.isConnecting) " +
                "reconnecting=\(webSocketManager.isReconnecting)"
            )
            if requestId != nil || projectPath != nil {
                print("[APNs] 按推送 route 同步，不切换当前消息页面，等待用户点击系统通知")
                webSocketManager.recoverAndSync(projectPath: projectPath, requestId: requestId, reason: "apns_received")
            } else {
                requestSyncForCurrentRoute()
            }
            print("[APNs] 收到远程推送，触发同步")
        }
        .onChange(of: latestHeadRequestId ?? "") { newHeadRequestId in
            guard !newHeadRequestId.isEmpty else {
                pushWatchRelayState(reason: "head_request_changed")
                return
            }
            if isHoldingDraftInput,
               let currentRequestId = currentRequest?.requestId,
               currentRequestId != newHeadRequestId {
                print(
                    "[MCP UI] 草稿未提交，跳过自动覆盖: current=\(currentRequestId), incoming=\(newHeadRequestId)"
                )
                pushWatchRelayState(reason: "head_request_preserved_draft")
                return
            }
            guard shouldAutoAdoptLatestHeadRequest(newHeadRequestId) else {
                print(
                    "[MCP UI] 保持当前焦点，不自动覆盖: focused=\(focusedRequestId ?? "无"), " +
                    "project_path=\(focusedProjectPath ?? "无"), incoming=\(newHeadRequestId)"
                )
                pushWatchRelayState(reason: "head_request_preserved_focus")
                return
            }
            adoptLatestHeadRequest(newHeadRequestId)
            print(
                "[MCP UI] 自动采用最新消息: focused=\(focusedRequestId ?? newHeadRequestId), " +
                "project_path=\(focusedProjectPath ?? "无")"
            )
            pushWatchRelayState(reason: "head_request_changed")
        }
        .onChange(of: isHoldingDraftInput) { isHolding in
            guard !isHolding,
                  let latestHeadRequestId,
                  !latestHeadRequestId.isEmpty,
                  focusedRequestId != latestHeadRequestId else { return }
            guard shouldAutoAdoptLatestHeadRequest(latestHeadRequestId) else {
                print(
                    "[MCP UI] 输入结束，保留当前焦点: focused=\(focusedRequestId ?? "无"), " +
                    "project_path=\(focusedProjectPath ?? "无"), latest=\(latestHeadRequestId)"
                )
                return
            }
            adoptLatestHeadRequest(latestHeadRequestId)
            print(
                "[MCP UI] 输入结束，自动采用最新消息: focused=\(focusedRequestId ?? latestHeadRequestId), " +
                "project_path=\(focusedProjectPath ?? "无")"
            )
        }
        .onChange(of: currentRouteIdentity) { _ in
            handleCurrentRouteIdentityChange()
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                if !switchToPreferredAuthenticatedPublicRouteOnActivation() {
                    webSocketManager.handleAppDidBecomeActive(
                        projectPath: syncProjectPathHint,
                        requestId: syncRequestIdHint
                    )
                }
                pushWatchRelayState(reason: "active")
                resumePendingPhoneActionIfNeeded(reason: "scene_active")
                pushSpeechMuscleMemoryToBridgeIfNeeded(reason: "scene_active")
                syncSpeechCorrectionMemoryFromBridge(reason: "scene_active")
                syncSpeechVocabularyFromBridge(reason: "scene_active")
                attemptRelayAutoRecoveryIfNeeded(reason: "scene_active")
                BackgroundAudioService.shared.stopBackgroundAudio()
                codexLiveManager.restoreAudioSessionForForeground()
                print("[生命周期] 回到前台，恢复当前音频所有者")
            case .inactive, .background:
                webSocketManager.handleAppWillResignActive()
                pushWatchRelayState(reason: "inactive_or_background")
                if codexLiveManager.isActive {
                    codexLiveManager.preserveAudioSessionForBackground()
                    print("[生命周期] GPT-Live 继续使用后台双向音频")
                } else if PersonalBackgroundKeepAlive.isEnabled {
                    BackgroundAudioService.shared.startBackgroundAudio()
                    print("[生命周期] 进入后台，启动个人版后台音频长连")
                } else {
                    print("[生命周期] 进入后台，个人版后台音频长连未启用")
                }
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
        .onChange(of: connectionStatus) { _ in
            pushWatchRelayState(reason: "connection_status_changed")
        }
        .onChange(of: webSocketManager.isConnected) { _ in
            pushWatchRelayState(reason: "connected_changed")
            if webSocketManager.isConnected {
                pushSpeechMuscleMemoryToBridgeIfNeeded(reason: "connected_changed")
                syncSpeechCorrectionMemoryFromBridge(reason: "connected_changed")
            }
        }
        .onChange(of: webSocketManager.isConnecting) { _ in
            pushWatchRelayState(reason: "connecting_changed")
        }
        .onChange(of: webSocketManager.isReconnecting) { _ in
            pushWatchRelayState(reason: "reconnecting_changed")
        }
        .onChange(of: webSocketManager.isConnectionRecoveryGraceActive) { _ in
            pushWatchRelayState(reason: "recovery_changed")
        }
        .onChange(of: webSocketManager.requiresDeviceRePairing) { _ in
            pushWatchRelayState(reason: "device_auth_pairing_required_changed")
        }
        .onChange(of: relayControlBaseURL) { _ in
            configureRelayCommandTransport()
        }
        .onChange(of: relayMacDeviceID) { _ in
            configureRelayCommandTransport()
        }
        .sheet(isPresented: $showProjectMenu) {
            ProjectMenuView(
                webSocketManager: webSocketManager,
                isPresented: $showProjectMenu,
                focusedRequestId: $focusedRequestId,
                focusedProjectPath: $focusedProjectPath,
                focusedRoutePreviewMessage: $focusedRoutePreviewMessage,
                isManualRouteSelection: $isManualRouteSelection,
                serverURL: serverURL,
                relayControlBaseURL: relayControlBaseURL,
                relayMacDeviceID: relayMacDeviceID
            )
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .sheet(isPresented: $showFileSelector) {
            FileSelectorView(
                preferredProjectPath: codexDefaultProjectPath,
                fallbackProjectPaths: targetProjectPathsForFileSelector(),
                mode: .insertReference,
                isPresented: $showFileSelector,
                userInput: $userInput,
                onSelectDefaultProjectPath: nil
            )
            .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .sheet(isPresented: $showCodexDefaultPathSelector) {
            FileSelectorView(
                preferredProjectPath: codexDefaultProjectPath,
                fallbackProjectPaths: targetProjectPathsForFileSelector(),
                mode: .chooseCodexDefaultProject,
                isPresented: $showCodexDefaultPathSelector,
                userInput: $userInput,
                onSelectDefaultProjectPath: setCodexDefaultProjectPath
            )
            .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(onImagePicked: appendImage)
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .sheet(
            isPresented: $showPromptorLibrary,
            onDismiss: focusInputAfterPromptorSelectionIfNeeded
        ) {
            PromptorLibrarySheet(
                theme: theme,
                serverURL: webSocketManager.resolvedWebSocketURL(preferredURL: serverURL),
                onSelect: { prompt in
                    appendPromptContent(prompt.content)
                    shouldFocusInputAfterPromptorDismiss = true
                }
            )
            .preferredColorScheme(isDarkMode ? .dark : .light)
            .presentationDetents([.fraction(0.78), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showQuotaSheet) {
            quotaSheet
                .preferredColorScheme(isDarkMode ? .dark : .light)
                .presentationDetents(quotaSheetDetents)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGhostSuggestionSheet) {
            GhostSuggestionManagerSheet(
                webSocketManager: webSocketManager,
                isPresented: $showGhostSuggestionSheet
            )
            .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .sheet(isPresented: $showRelaySettings) {
            RelaySettingsView(
                relayControlBaseURL: $relayControlBaseURL,
                relayMacDeviceID: $relayMacDeviceID,
                relayAutoRecoverOnActivation: $relayAutoRecoverOnActivation,
                onComplete: {
                    configureRelayCommandTransport()
                    webSocketManager.addMessage("Relay 备用设置已保存")
                },
                onConnectBackup: {
                    connectUsingRelayBackup(reason: "relay_settings_manual_backup")
                }
            )
            .preferredColorScheme(isDarkMode ? .dark : .light)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "解除这台 iPhone 的配对？",
            isPresented: $showUnpairConfirmation,
            titleVisibility: .visible
        ) {
            Button("解除配对", role: .destructive) {
                unpairThisIPhone()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除本机的 Bridge 与 Relay 连接凭据。桌面端其他已配对设备不会受影响。")
        }
        .sheet(isPresented: $showDesktopPairingGuide) {
            DesktopPairingGuideSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func handleIterateURL(_ url: URL, reason: String) {
        switch IterateURLRouter.routeName(from: url) {
        case "pairing":
            applyPairingURL(url)
        case "voice":
            handleVoiceLaunchURL(url, reason: reason)
        case "phone-action", "phone_action":
            handlePhoneActionURL(url, reason: reason)
        default:
            print(MobilePairingDiagnostics.unsupportedURLMessage)
        }
    }

    private func handleVoiceLaunchURL(_ url: URL, reason: String) {
        guard IterateURLRouter.routeName(from: url) == "voice" else {
            return
        }

        UserDefaults.standard.removeObject(forKey: VoiceLaunchBridge.pendingURLKey)
        pendingVoiceLaunchStart?.cancel()
        pendingSpeechRestart?.cancel()
        pendingSpeechRestart = nil
        shouldAutoResumeRecording = false

        showMainPage = false
        showProjectMenu = false
        showFileSelector = false
        showImagePicker = false
        showQuotaSheet = false
        showGhostSuggestionSheet = false
        showRelaySettings = false

        let connectionURL = webSocketManager.resolvedWebSocketURL(preferredURL: serverURL)
        if !webSocketManager.isConnected
            && !webSocketManager.isConnecting
            && ServerConfig.hasConfiguredWebSocketURL(connectionURL) {
            webSocketManager.connect(to: serverURL)
        }
        webSocketManager.addMessage("已启动语音入口")
        requestSyncForCurrentRoute()
        scheduleVoiceLaunchStart(reason: reason, attempt: 0)
    }

    private func scheduleVoiceLaunchStart(reason: String, attempt: Int) {
        pendingVoiceLaunchStart?.cancel()

        let delay: TimeInterval = attempt == 0 ? 0.25 : 0.6
        let workItem = DispatchWorkItem {
            pendingVoiceLaunchStart = nil
            startVoiceLaunchIfReady(reason: reason, attempt: attempt)
        }

        pendingVoiceLaunchStart = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func startVoiceLaunchIfReady(reason: String, attempt: Int) {
        guard !speechManager.isRecording else { return }

        if currentMessage == nil {
            requestSyncForCurrentRoute()
            if attempt < 1 {
                scheduleVoiceLaunchStart(reason: reason, attempt: attempt + 1)
                return
            }
            webSocketManager.addMessage("未找到等待回复的 AI，先启动语音输入")
        }

        guard speechManager.isAuthorized else {
            speechManager.requestAuthorization()
            if attempt < 8 {
                scheduleVoiceLaunchStart(reason: reason, attempt: attempt + 1)
            }
            return
        }

        isInputFocused = true
        print("[VoiceLaunch] start speech recording reason=\(reason)")
        startSpeechRecording()
    }

    private func handlePhoneActionURL(_ url: URL, reason: String) {
        guard let routeName = IterateURLRouter.routeName(from: url),
              routeName == "phone-action" || routeName == "phone_action" else {
            return
        }

        UserDefaults.standard.removeObject(forKey: PhoneActionURLBridge.pendingURLKey)
        guard let request = PhoneActionRequest(url: url) else {
            webSocketManager.addMessage("手机动作链接无效")
            return
        }
        handlePhoneActionRequest(request, reason: reason)
    }

    private func handlePhoneActionRequest(_ request: PhoneActionRequest, reason: String) {
        if !phoneActionTargetsCurrentDevice(request) {
            let targetDeviceId = request.targetDeviceId ?? "nil"
            let localDeviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown-ios-device"
            print("[PhoneAction] ignored before execution target_device_id=\(targetDeviceId) local_device_id=\(localDeviceId)")
            return
        }

        let action = request.normalizedAction
        let safeImmediateActions: Set<String> = [
            "set_input",
            "append_input",
            "set_clipboard",
            "show_message",
            "start_voice",
            "open_browser",
            "share_text"
        ]

        if request.requiresConfirmation && !safeImmediateActions.contains(action) {
            finishPhoneAction(request, status: "needs_confirmation", message: "动作需要确认，MVP 尚未实现确认卡片")
            return
        }

        if request.needsJobPayloadFetch {
            fetchPhoneActionJobPayload(for: request, reason: reason)
            return
        }

        switch action {
        case "set_input":
            let text = request.text ?? ""
            userInput = text
            isInputFocused = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            webSocketManager.addMessage("手机动作已执行: 设置输入框")
            finishPhoneAction(request, status: "success", message: "input updated via \(reason)")

        case "append_input":
            let text = request.text ?? ""
            appendPromptContent(text)
            isInputFocused = true
            webSocketManager.addMessage("手机动作已执行: 追加输入")
            finishPhoneAction(request, status: "success", message: "input appended via \(reason)")

        case "set_clipboard":
            let text = request.text ?? ""
            UIPasteboard.general.string = text
            webSocketManager.addMessage("手机动作已执行: 写入剪贴板")
            finishPhoneAction(request, status: "success", message: "clipboard updated via \(reason)")

        case "show_message":
            let message = request.text ?? request.title ?? "收到手机动作"
            phoneActionAlertTitle = request.title ?? "手机动作消息"
            phoneActionAlertMessage = message
            showPhoneActionAlert = true
            webSocketManager.addMessage("手机动作消息: \(message)")
            finishPhoneAction(request, status: "success", message: "message displayed via \(reason)")

        case "start_voice":
            handleVoiceLaunchURL(VoiceLaunchBridge.defaultURL, reason: "phone_action:\(request.id)")
            finishPhoneAction(request, status: "success", message: "voice launch requested via \(reason)")

        case "open_url":
            guard let rawURL = request.url,
                  let targetURL = URL(string: rawURL),
                  let scheme = targetURL.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" || scheme == "iterate" else {
                finishPhoneAction(request, status: "failed", message: "missing or invalid url")
                return
            }
            UIApplication.shared.open(targetURL, options: [:]) { accepted in
                finishPhoneAction(
                    request,
                    status: accepted ? "success" : "failed",
                    message: accepted ? "url opened via \(reason)" : "system rejected url"
                )
            }

        case "open_browser":
            openPhoneActionBrowserURL(request, reason: reason)

        case "share_text":
            presentPhoneActionShareSheet(request, reason: reason)

        case "run_shortcut":
            runPhoneActionShortcut(request, reason: reason)

        default:
            webSocketManager.addMessage("未知手机动作: \(request.action)")
            finishPhoneAction(request, status: "unsupported", message: "unsupported action: \(request.action)")
        }
    }

    private func fetchPhoneActionJobPayload(for request: PhoneActionRequest, reason: String) {
        guard let jobId = request.jobId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !jobId.isEmpty else {
            finishPhoneAction(request, status: "failed", message: "missing phone action job id")
            return
        }
        let encodedJobId = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
        let httpBase = ServerConfig.httpBaseURL(fromWebSocketURL: serverURL)
        guard let url = URL(string: "\(httpBase)/api/phone-action-jobs/\(encodedJobId)") else {
            finishPhoneAction(request, status: "failed", message: "invalid phone action job url")
            return
        }

        webSocketManager.addMessage("正在获取手机动作内容: \(request.normalizedAction)")
        let urlRequest = DeviceAuthStore.authorizedRequest(url: url)
        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "phone_action_job") {
                DispatchQueue.main.async {
                    finishPhoneAction(request, status: "failed", message: "phone action job auth failed")
                }
                return
            }
            if let error {
                DispatchQueue.main.async {
                    finishPhoneAction(request, status: "failed", message: "phone action job fetch failed: \(error.localizedDescription)")
                }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    finishPhoneAction(request, status: "failed", message: "phone action job missing response")
                }
                return
            }
            guard (200..<300).contains(http.statusCode), let data else {
                DispatchQueue.main.async {
                    finishPhoneAction(request, status: "failed", message: "phone action job fetch rejected: HTTP \(http.statusCode)")
                }
                return
            }
            do {
                let response = try JSONDecoder().decode(PhoneActionJobResponse.self, from: data)
                guard response.job.actionId == request.id,
                      response.job.action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == request.normalizedAction else {
                    DispatchQueue.main.async {
                        finishPhoneAction(request, status: "failed", message: "phone action job mismatch")
                    }
                    return
                }
                let hydrated = request.hydrated(with: response.job.payload)
                DispatchQueue.main.async {
                    webSocketManager.addMessage("手机动作内容已获取: \(response.job.payloadSizeBytes) bytes")
                    handlePhoneActionRequest(hydrated, reason: "job_fetch:\(reason)")
                }
            } catch {
                DispatchQueue.main.async {
                    finishPhoneAction(request, status: "failed", message: "phone action job decode failed")
                }
            }
        }.resume()
    }

    private func phoneActionTargetsCurrentDevice(_ request: PhoneActionRequest) -> Bool {
        guard let targetDeviceId = request.targetDeviceId else {
            return true
        }

        let localDeviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown-ios-device"
        return targetDeviceId == localDeviceId
    }

    private func finishPhoneAction(_ request: PhoneActionRequest, status: String, message: String) {
        if isTerminalPhoneActionStatus(status) {
            PendingPhoneActionStore.clear(actionId: request.id)
        }
        webSocketManager.sendPhoneActionResult(actionId: request.id, status: status, message: message)
        print("[PhoneAction] id=\(request.id) action=\(request.action) status=\(status) message=\(message)")
    }

    private func isTerminalPhoneActionStatus(_ status: String) -> Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !["waiting_for_foreground", "pending"].contains(normalized)
    }

    private func openPhoneActionBrowserURL(_ request: PhoneActionRequest, reason: String) {
        guard let rawURL = request.url,
              let targetURL = URL(string: rawURL),
              let scheme = targetURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            finishPhoneAction(request, status: "failed", message: "missing or invalid http url")
            return
        }

        let browser = request.browser?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "default"
        switch browser {
        case "chrome":
            if let chromeURL = chromeBrowserURL(for: targetURL),
               UIApplication.shared.canOpenURL(chromeURL) {
                openPhoneActionURL(
                    chromeURL,
                    fallbackURL: targetURL,
                    request: request,
                    successMessage: "url opened in chrome via \(reason)",
                    fallbackMessage: "url opened in default browser via \(reason)"
                )
            } else {
                openPhoneActionURL(
                    targetURL,
                    request: request,
                    successMessage: "chrome unavailable, url opened in default browser via \(reason)"
                )
            }
        case "google":
            guard let googleURL = googleSearchURL(for: request.text ?? rawURL) else {
                finishPhoneAction(request, status: "failed", message: "invalid google search query")
                return
            }
            openPhoneActionURL(
                googleURL,
                request: request,
                successMessage: "google search opened via \(reason)"
            )
        case "default", "safari":
            openPhoneActionURL(
                targetURL,
                request: request,
                successMessage: "url opened in default browser via \(reason)"
            )
        default:
            finishPhoneAction(request, status: "failed", message: "unsupported browser: \(browser)")
        }
    }

    private func openPhoneActionURL(
        _ url: URL,
        fallbackURL: URL? = nil,
        request: PhoneActionRequest,
        successMessage: String,
        fallbackMessage: String? = nil
    ) {
        UIApplication.shared.open(url, options: [:]) { accepted in
            if accepted {
                finishPhoneAction(request, status: "success", message: successMessage)
                return
            }

            guard let fallbackURL else {
                finishPhoneAction(request, status: "failed", message: "system rejected url")
                return
            }

            UIApplication.shared.open(fallbackURL, options: [:]) { fallbackAccepted in
                finishPhoneAction(
                    request,
                    status: fallbackAccepted ? "success" : "failed",
                    message: fallbackAccepted ? (fallbackMessage ?? successMessage) : "system rejected url"
                )
            }
        }
    }

    private func chromeBrowserURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else {
            return nil
        }
        switch scheme {
        case "http":
            components.scheme = "googlechrome"
        case "https":
            components.scheme = "googlechromes"
        default:
            return nil
        }
        return components.url
    }

    private func googleSearchURL(for query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        return components.url
    }

    private func presentPhoneActionShareSheet(_ request: PhoneActionRequest, reason: String) {
        var items: [Any] = []
        if let text = phoneActionNonEmptyValue(request.text) {
            items.append(text)
        }
        if let rawURL = phoneActionNonEmptyValue(request.url) {
            guard let url = URL(string: rawURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                finishPhoneAction(request, status: "failed", message: "share_text url must be http/https")
                return
            }
            items.append(url)
        }

        guard !items.isEmpty else {
            finishPhoneAction(request, status: "failed", message: "share_text needs text or url")
            return
        }
        guard let presenter = topViewController() else {
            if shouldQueuePhoneActionForForeground(request, reason: reason) {
                queuePhoneActionForForeground(request, reason: reason)
                return
            }
            finishPhoneAction(request, status: "failed", message: "no foreground presenter for share sheet")
            return
        }

        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        activity.completionWithItemsHandler = { _, completed, _, error in
            let status = error == nil ? (completed ? "success" : "cancelled") : "failed"
            let message = error == nil
                ? (completed ? "share sheet completed via \(reason)" : "share sheet cancelled via \(reason)")
                : "share sheet failed via \(reason): \(error?.localizedDescription ?? "unknown")"
            DispatchQueue.main.async {
                finishPhoneAction(request, status: status, message: message)
            }
        }
        presenter.present(activity, animated: true)
        webSocketManager.addMessage("手机动作已执行: 打开分享面板")
    }

    private func runPhoneActionShortcut(_ request: PhoneActionRequest, reason: String) {
        guard let shortcutName = phoneActionNonEmptyValue(request.shortcutName) else {
            finishPhoneAction(request, status: "failed", message: "run_shortcut needs shortcut_name")
            return
        }
        guard shortcutName.lowercased().hasPrefix("iterate") else {
            finishPhoneAction(request, status: "failed", message: "shortcut name must start with iterate")
            return
        }
        guard let shortcutURL = shortcutRunURL(name: shortcutName, input: request.text ?? request.url) else {
            finishPhoneAction(request, status: "failed", message: "invalid shortcut url")
            return
        }

        UIApplication.shared.open(shortcutURL, options: [:]) { accepted in
            if !accepted,
               shouldQueuePhoneActionForForeground(request, reason: reason) {
                queuePhoneActionForForeground(request, reason: reason)
                return
            }

            finishPhoneAction(
                request,
                status: accepted ? "success" : "failed",
                message: accepted ? "shortcut requested via \(reason)" : "system rejected shortcut url"
            )
        }
    }

    private func shouldQueuePhoneActionForForeground(_ request: PhoneActionRequest, reason: String) -> Bool {
        let foregroundRequiredActions: Set<String> = [
            "run_shortcut",
            "share_text"
        ]
        guard foregroundRequiredActions.contains(request.normalizedAction) else {
            return false
        }
        guard !reason.hasPrefix("foreground_resume") else {
            return false
        }
        guard UIApplication.shared.applicationState != .active || topViewController() == nil else {
            return false
        }
        if let envelope = PendingPhoneActionStore.load(),
           envelope.request.id == request.id,
           envelope.retryCount > 0 {
            return false
        }
        return true
    }

    private func queuePhoneActionForForeground(_ request: PhoneActionRequest, reason: String) {
        let envelope = PendingPhoneActionEnvelope(
            request: request,
            createdAt: Date(),
            retryCount: 0,
            reason: reason
        )
        PendingPhoneActionStore.save(envelope)
        webSocketManager.addMessage("手机动作等待前台: \(request.action)")
        finishPhoneAction(
            request,
            status: "waiting_for_foreground",
            message: "waiting for IterateNotify foreground to run \(request.normalizedAction)"
        )
        sendPendingPhoneActionNotification(for: request)
    }

    private func sendPendingPhoneActionNotification(for request: PhoneActionRequest) {
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(PendingPhoneActionStore.ttl))
        NotificationManager.shared.sendNotification(
            title: "继续电脑动作",
            body: pendingPhoneActionNotificationBody(for: request),
            identifier: "iterate-phone-action-\(request.id)",
            userInfo: [
                "source": "iterate_phone_action",
                "phone_action_id": request.id,
                "request_id": request.id,
                "action": request.normalizedAction,
                "expires_at": expiresAt
            ]
        )
    }

    private func pendingPhoneActionNotificationBody(for request: PhoneActionRequest) -> String {
        switch request.normalizedAction {
        case "run_shortcut":
            let shortcutName = phoneActionNonEmptyValue(request.shortcutName) ?? "iterate"
            return "点开后运行快捷指令 \(shortcutName)"
        case "share_text":
            return "点开后继续打开分享面板"
        default:
            return "点开后继续执行 \(request.action)"
        }
    }

    private func resumePendingPhoneActionIfNeeded(reason: String) {
        guard let envelope = PendingPhoneActionStore.load() else {
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            return
        }

        if envelope.isExpired {
            finishPhoneAction(
                envelope.request,
                status: "expired",
                message: "pending phone action expired before foreground resume"
            )
            return
        }

        guard envelope.retryCount == 0 else {
            return
        }

        let retryEnvelope = envelope.incrementingRetry(reason: "foreground_resume:\(reason)")
        PendingPhoneActionStore.save(retryEnvelope)
        webSocketManager.addMessage("继续执行电脑动作: \(retryEnvelope.request.action)")
        handlePhoneActionRequest(retryEnvelope.request, reason: retryEnvelope.reason)
    }

    private func shortcutRunURL(name: String, input: String?) -> URL? {
        var items = [URLQueryItem(name: "name", value: name)]
        if let input = phoneActionNonEmptyValue(input) {
            items.append(URLQueryItem(name: "input", value: "text"))
            items.append(URLQueryItem(name: "text", value: input))
        }

        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = items
        return components.url
    }

    private func phoneActionNonEmptyValue(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func topViewController() -> UIViewController? {
        let foregroundScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let window = foregroundScenes
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private func applyPairingURL(_ url: URL) {
        PairingURLBridge.clearPendingURL(matching: url)
        guard IterateURLRouter.routeName(from: url) == "pairing" else {
            presentPairingFailure(.invalidRoute)
            return
        }

        let payload: CompanionPairingPayload
        switch decodePairingPayload(from: url) {
        case .success(let decodedPayload): payload = decodedPayload
        case .failure(let error):
            presentPairingFailure(error)
            return
        }

        let fingerprint = pairingFingerprint(payload.pairingTokenValue)
        guard let attempt = mobilePairingCoordinator.beginAttempt(fingerprint: fingerprint) else { return }
        activeMobilePairingAttempt = attempt
        mobilePairingPhase = mobilePairingCoordinator.phase
        guard mobilePairingCoordinator.setPhase(.probing, for: attempt) else { return }
        mobilePairingPhase = mobilePairingCoordinator.phase

        let selectedPayload = selectedPairingPayload(from: payload)
        let nextServerURL = selectedPayload.wsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextServerURL.isEmpty else {
            finishMobilePairingAttempt(attempt, failure: .invalidURL)
            return
        }

        if selectedPayload.wsURL.trimmingCharacters(in: .whitespacesAndNewlines)
            != payload.wsURL.trimmingCharacters(in: .whitespacesAndNewlines) {
            webSocketManager.addMessage("已优先选择公网配对通道，Relay 保留为备用")
            print("[Pairing] selected public candidate from pairing payload")
        }

        guard mobilePairingCoordinator.setPhase(.authorizing, for: attempt) else { return }
        mobilePairingPhase = mobilePairingCoordinator.phase
        let claimBaseURLs = pairingClaimCandidateBaseURLs(from: selectedPayload)
        let selectedRouteIsRelay = isRelayRoute(
            transportMode: selectedPayload.transportMode,
            wsURL: selectedPayload.wsURL
        )
        let initialStep = MobilePairingAuthorizationPolicy.initialStep(
            hasBridgeClaimCandidates: !claimBaseURLs.isEmpty,
            selectedRouteIsRelay: selectedRouteIsRelay
        )
        switch initialStep {
        case .claimBridge:
            claimBridgePairingIfNeeded(
                payload: selectedPayload,
                nextServerURL: nextServerURL,
                attempt: attempt
            )
        case .claimRelay:
            claimRelayPairingIfNeeded(
                payload: selectedPayload,
                nextServerURL: nextServerURL,
                attempt: attempt
            ) { relayAuthorization in
                guard self.mobilePairingCoordinator.isCurrent(attempt) else { return }
                let nextStep = MobilePairingAuthorizationPolicy.nextStep(
                    hasBridgeClaimCandidates: false,
                    selectedRouteIsRelay: selectedRouteIsRelay,
                    relayAuthorization: relayAuthorization
                )
                switch nextStep {
                case .activateSelectedRelay:
                    guard self.mobilePairingCoordinator.setPhase(.connecting, for: attempt) else { return }
                    self.mobilePairingPhase = self.mobilePairingCoordinator.phase
                    self.activatePairingRoute(nextServerURL, payload: selectedPayload)
                case .claimBridge, .failNoClaimRoute:
                    self.finishMobilePairingAttempt(attempt, failure: .noClaimRoute)
                }
            }
        case .failNoClaimRoute:
            finishMobilePairingAttempt(attempt, failure: .noClaimRoute)
        }
    }

    private func finishMobilePairingAttempt(_ attempt: MobilePairingAttempt, failure: MobilePairingFailure) {
        guard mobilePairingCoordinator.finish(attempt: attempt, failure: failure) else { return }
        mobilePairingPhase = mobilePairingCoordinator.phase
        if activeMobilePairingAttempt == attempt { activeMobilePairingAttempt = nil }
        webSocketManager.addMessage(failure.statusText)
    }

    private func pairingFingerprint(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func selectedPairingPayload(from payload: CompanionPairingPayload) -> CompanionPairingPayload {
        payload
    }

    private func pairingPayload(
        from candidate: CompanionTransportCandidate,
        source payload: CompanionPairingPayload
    ) -> CompanionPairingPayload {
        CompanionPairingPayload(
            transportMode: candidate.transportMode,
            baseURL: candidate.baseURL,
            wsURL: candidate.wsURL,
            relayDeviceID: candidate.relayDeviceID,
            relayPairingToken: candidate.relayPairingToken,
            health: candidate.health,
            disabled: candidate.disabled,
            candidates: payload.candidates,
            pairingToken: payload.pairingToken,
            warning: candidate.warning ?? payload.warning
        )
    }

    private func claimRelayPairingIfNeeded(
        payload: CompanionPairingPayload,
        nextServerURL: String,
        attempt: MobilePairingAttempt,
        completion: @escaping (MobilePairingRelayAuthorization) -> Void
    ) {
        let relayPairingToken = payload.relayPairingToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !relayPairingToken.isEmpty,
              isRelayRoute(transportMode: payload.transportMode, wsURL: nextServerURL) else {
            completion(.notAvailable)
            return
        }

        guard let relayBaseURL = normalizedRelayBaseURL(baseURL: payload.baseURL, wsURL: nextServerURL) else {
            webSocketManager.addMessage("Relay 授权失败：Relay base URL 无效")
            completion(.failed)
            return
        }
        let payloadRelayDeviceID = payload.relayDeviceID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let relayDeviceID = payloadRelayDeviceID.isEmpty
            ? (relayDeviceID(fromStreamURL: nextServerURL) ?? "")
            : payloadRelayDeviceID
        guard !relayDeviceID.isEmpty else {
            webSocketManager.addMessage("Relay 授权失败：缺少 Mac device id")
            completion(.failed)
            return
        }

        webSocketManager.addMessage("正在完成 Relay 授权...")
        RelayAuthStore.claimPairingToken(
            relayPairingToken,
            relayBaseURL: relayBaseURL,
            relayDeviceID: relayDeviceID
        ) { result in
            DispatchQueue.main.async {
                guard self.mobilePairingCoordinator.isCurrent(attempt) else { return }
                switch result {
                case .success(let auth):
                    do {
                        let committed = try self.mobilePairingCoordinator.performIfCurrent(attempt) {
                            try RelayAuthStore.save(auth)
                        }
                        guard committed else { return }
                        self.webSocketManager.addMessage("Relay 授权完成: \(auth.scopes.joined(separator: ", "))")
                        completion(.authorized)
                    } catch {
                        self.webSocketManager.addMessage("Relay 授权保存失败，请重新扫码配对")
                        completion(.failed)
                    }
                case .failure(let error):
                    if RelayAuthStore.load(relayBaseURL: relayBaseURL, relayDeviceID: relayDeviceID) != nil {
                        self.webSocketManager.addMessage("Relay 授权失败，已保留现有授权：\(error.localizedDescription)")
                        completion(.authorized)
                    } else {
                        self.webSocketManager.addMessage("Relay 授权失败，请重新扫码配对：\(error.localizedDescription)")
                        print("[Pairing] relay claim failed without existing relay auth: \(error.localizedDescription)")
                        completion(.failed)
                    }
                }
            }
        }
    }

    private func claimBridgePairingIfNeeded(
        payload: CompanionPairingPayload,
        nextServerURL: String,
        attempt: MobilePairingAttempt
    ) {
        let pairingToken = payload.pairingToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pairingToken.isEmpty else {
            finishMobilePairingAttempt(attempt, failure: .missingPairingToken)
            return
        }

        let claimBaseURLs = pairingClaimCandidateBaseURLs(from: payload)
        guard !claimBaseURLs.isEmpty else {
            finishMobilePairingAttempt(attempt, failure: .noClaimRoute)
            return
        }
        webSocketManager.addMessage("正在完成设备授权...")
        DeviceAuthStore.claimPairingToken(pairingToken, candidateHTTPBaseURLs: claimBaseURLs) { result in
            DispatchQueue.main.async {
                guard self.mobilePairingCoordinator.isCurrent(attempt) else { return }
                switch result {
                case .success(let claim):
                    guard let candidate = try? selectClaimedCandidate(
                        payload: payload,
                        claimedBaseURL: claim.claimedBaseURL
                    ) else {
                        self.finishMobilePairingAttempt(attempt, failure: .claimRouteMismatch)
                        return
                    }
                    let selectedPayload = self.pairingPayload(from: candidate, source: payload)
                    do {
                        let committed = try self.mobilePairingCoordinator.performIfCurrent(attempt) {
                            try DeviceAuthStore.save(claim.auth)
                            self.hasDeviceAuthorization = true
                            self.webSocketManager.addMessage(
                                "设备授权完成: \(claim.auth.scopes.joined(separator: ", "))"
                            )
                            _ = self.mobilePairingCoordinator.setPhase(.connecting, for: attempt)
                            self.mobilePairingPhase = self.mobilePairingCoordinator.phase
                            self.activatePairingRoute(selectedPayload.wsURL, payload: selectedPayload)
                        }
                        guard committed else { return }
                    } catch {
                        self.finishMobilePairingAttempt(attempt, failure: .claimRejected)
                    }
                case .failure(let error):
                    if DeviceAuthStore.load() != nil {
                        self.webSocketManager.addMessage("设备授权失败，已保留现有授权：\(error.localizedDescription)")
                        print("[Pairing] claim failed; preserved existing device auth: \(error.localizedDescription)")
                    } else {
                        self.webSocketManager.addMessage("设备授权失败，请重新扫码配对：\(error.localizedDescription)")
                        print("[Pairing] claim failed without existing device auth: \(error.localizedDescription)")
                    }
                    self.finishMobilePairingAttempt(attempt, failure: .claimRejected)
                }
            }
        }
    }

    private func pairingClaimCandidateBaseURLs(from payload: CompanionPairingPayload) -> [String] {
        // Probe transport reachability before consuming the single-use pairing token.
        let primaryBaseURL = payload.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPrimaryBaseURL = primaryBaseURL.isEmpty
            ? ServerConfig.httpBaseURL(fromWebSocketURL: payload.wsURL)
            : primaryBaseURL
        var candidateBaseURLs: [String] = []
        if !isRelayRoute(transportMode: payload.transportMode, wsURL: payload.wsURL) {
            candidateBaseURLs.append(resolvedPrimaryBaseURL)
        }
        var seen = Set<String>()
        return candidateBaseURLs.filter { baseURL in
            let normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
        }
    }

    private func isRelayRoute(transportMode: String, wsURL: String) -> Bool {
        if transportMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "relay" {
            return true
        }
        guard let components = URLComponents(string: wsURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        let path = components.percentEncodedPath.lowercased()
        return path.contains("/api/devices/") && path.hasSuffix("/stream")
    }

    private func relayDeviceID(fromStreamURL wsURL: String) -> String? {
        guard let components = URLComponents(string: wsURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let parts = components.percentEncodedPath.split(separator: "/").map(String.init)
        guard let devicesIndex = parts.firstIndex(of: "devices"),
              parts.indices.contains(devicesIndex + 1) else {
            return nil
        }
        let encoded = parts[devicesIndex + 1]
        return encoded.removingPercentEncoding ?? encoded
    }

    private func normalizedRelayBaseURL(baseURL: String, wsURL: String) -> String? {
        var candidate = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty {
            candidate = ServerConfig.httpBaseURL(fromWebSocketURL: wsURL)
        }
        candidate = candidate
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")

        if var components = URLComponents(string: candidate),
           components.percentEncodedPath.lowercased().contains("/api/devices/") {
            components.percentEncodedPath = ""
            components.query = nil
            components.fragment = nil
            candidate = components.string ?? candidate
        }

        while candidate.hasSuffix("/") {
            candidate.removeLast()
        }
        return candidate.isEmpty ? nil : candidate
    }

    @discardableResult
    private func configureRelayRouteIfNeeded(
        transportMode: String,
        baseURL: String,
        wsURL: String,
        relayDeviceID: String?,
        relayPairingToken: String?,
        source: String
    ) -> Bool {
        guard isRelayRoute(transportMode: transportMode, wsURL: wsURL),
              let relayBaseURL = normalizedRelayBaseURL(baseURL: baseURL, wsURL: wsURL) else {
            return false
        }

        let configuredDeviceID = relayDeviceID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedDeviceID = configuredDeviceID.isEmpty
            ? (self.relayDeviceID(fromStreamURL: wsURL) ?? "local-mac")
            : configuredDeviceID
        relayControlBaseURL = relayBaseURL
        relayMacDeviceID = resolvedDeviceID
        configureRelayCommandTransport()

        let relayPairingToken = relayPairingToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if relayPairingToken.isEmpty,
           RelayAuthStore.load(relayBaseURL: relayBaseURL, relayDeviceID: resolvedDeviceID) == nil {
            webSocketManager.addMessage("Relay route 已导入，但 scoped Relay 授权尚未保存；请重新扫码授权")
        }

        print(
            "[Pairing] relay route configured source=\(source) base_url=\(relayBaseURL) device_id=\(resolvedDeviceID)"
        )
        return true
    }

    private func activatePairingRoute(_ nextServerURL: String, payload: CompanionPairingPayload) {
        let configuredRelay = configureRelayRouteIfNeeded(
            transportMode: payload.transportMode,
            baseURL: payload.baseURL,
            wsURL: nextServerURL,
            relayDeviceID: payload.relayDeviceID,
            relayPairingToken: payload.relayPairingToken,
            source: "pairing_payload"
        )
        serverURL = nextServerURL
        UserDefaults.standard.set(nextServerURL, forKey: ServerConfig.storageKey)
        storeTransportCandidates(from: payload)
        webSocketManager.addMessage("已导入配对: \(payload.transportMode) · \(payload.baseURL)")
        if configuredRelay {
            webSocketManager.addMessage("已导入 Relay 连接信息: \(relayMacDeviceID)")
        }
        if let warning = payload.warning, !warning.isEmpty {
            webSocketManager.addMessage(warning)
        }
        print("[Pairing] imported ws_url=\(nextServerURL)")
        webSocketManager.beginRouteSwitch(reason: "pairing_route_import")
        webSocketManager.disconnect(silent: true)
        webSocketManager.connect(to: nextServerURL)
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["ITERATE_SIMULATOR_REQUEST_SPEECH_AUTH"] == "1" {
            speechManager.requestAuthorization()
        }
#else
        speechManager.requestAuthorization()
#endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            requestSyncForCurrentRoute()
        }
    }

    @discardableResult
    private func consumePendingPairingURL() -> Bool {
        guard let url = PairingURLBridge.takePendingURL() else {
            return false
        }

        applyPairingURL(url)
        return true
    }

    @discardableResult
    private func consumePendingVoiceLaunch(reason: String) -> Bool {
        guard let rawURL = UserDefaults.standard.string(forKey: VoiceLaunchBridge.pendingURLKey),
              let url = URL(string: rawURL) else {
            return false
        }

        UserDefaults.standard.removeObject(forKey: VoiceLaunchBridge.pendingURLKey)
        handleVoiceLaunchURL(url, reason: reason)
        return true
    }

    @discardableResult
    private func consumePendingPhoneActionURL(reason: String) -> Bool {
        guard let rawURL = UserDefaults.standard.string(forKey: PhoneActionURLBridge.pendingURLKey),
              let url = URL(string: rawURL) else {
            return false
        }

        UserDefaults.standard.removeObject(forKey: PhoneActionURLBridge.pendingURLKey)
        handlePhoneActionURL(url, reason: reason)
        return true
    }

    private func decodePairingPayload(
        from url: URL
    ) -> Result<CompanionPairingPayload, MobilePairingError> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?.first(where: {
                  $0.name == "payload" || $0.name == "pairing"
              })?.value,
              let data = decodeBase64URL(encoded) else {
            return .failure(.malformedPayload)
        }

        return MobilePairingEnvelope.decode(
            data: data,
            routeName: IterateURLRouter.routeName(from: url) ?? ""
        ).map(\.payload)
    }

    private func presentPairingFailure(_ error: MobilePairingError) {
        let failure: MobilePairingFailure
        switch error {
        case .invalidRoute: failure = .invalidRoute
        case .malformedPayload: failure = .malformedPayload
        case .oversizedPayload: failure = .oversizedPayload
        case .unsupportedVersion: failure = .unsupportedVersion
        case .invalidTimestamp: failure = .invalidTimestamp
        case .expired: failure = .expired
        case .missingPairingToken: failure = .missingPairingToken
        case .invalidURL: failure = .invalidURL
        case .noMatchingCandidate: failure = .claimRouteMismatch
        }
        mobilePairingCoordinator.fail(failure)
        mobilePairingPhase = mobilePairingCoordinator.phase
        webSocketManager.addMessage(failure.statusText)
        print("[Pairing] rejected code=\(error.errorDescription ?? "pairing_invalid_payload")")
    }

    private func storeTransportCandidates(from payload: CompanionPairingPayload) {
        let primary = CompanionTransportCandidate(
            transportMode: payload.transportMode,
            baseURL: payload.baseURL,
            wsURL: payload.wsURL,
            relayDeviceID: payload.relayDeviceID,
            relayPairingToken: payload.relayPairingToken,
            health: payload.health,
            disabled: payload.disabled,
            warning: payload.warning
        )
        let merged = (payload.candidates ?? []) + [primary]
        var seen = Set<String>()
        let uniqueCandidates = merged.filter { candidate in
            let key = candidate.wsURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }

        let persistentCandidates = uniqueCandidates.map(\.sanitizedForPersistence)
        guard let data = try? JSONEncoder().encode(persistentCandidates) else {
            print("[Pairing] failed to encode transport candidates")
            return
        }

        UserDefaults.standard.set(data, forKey: Self.transportCandidatesStorageKey)
        print(
            "[Pairing] stored transport candidates: " +
            uniqueCandidates.map {
                "\($0.transportMode)=\($0.wsURL) health=\($0.normalizedHealth) disabled=\($0.isDisabled)"
            }.joined(separator: ", ")
        )
    }

    private func cachedTransportCandidates() -> [CompanionTransportCandidate] {
        guard let data = UserDefaults.standard.data(forKey: Self.transportCandidatesStorageKey),
              let candidates = try? JSONDecoder().decode([CompanionTransportCandidate].self, from: data) else {
            return []
        }
        return candidates
    }

    private func cachedTailscaleCandidate(excluding urlString: String? = nil) -> CompanionTransportCandidate? {
        let excludedURL = urlString?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return cachedTransportCandidates().first(where: { candidate in
            guard candidate.transportMode == "tailscale" else { return false }
            guard !candidate.isDisabled else { return false }
            let wsURL = candidate.wsURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wsURL.isEmpty else { return false }
            guard let excludedURL else { return true }
            return wsURL.lowercased() != excludedURL
        })
    }

    private func isUsablePublicTunnelCandidate(
        _ candidate: CompanionTransportCandidate,
        excluding urlString: String? = nil
    ) -> Bool {
        let excludedURL = urlString?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard candidate.transportMode == "public_tunnel" else { return false }
        guard !candidate.isDisabled else { return false }
        guard !["degraded", "unhealthy", "down"].contains(candidate.normalizedHealth) else {
            return false
        }
        let wsURL = candidate.wsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wsURL.lowercased().hasPrefix("wss://") else { return false }
        guard let excludedURL else { return true }
        return wsURL.lowercased() != excludedURL
    }

    private func cachedPublicTunnelCandidate(excluding urlString: String? = nil) -> CompanionTransportCandidate? {
        cachedTransportCandidates().first {
            isUsablePublicTunnelCandidate($0, excluding: urlString)
        }
    }

    private func preferredAuthenticatedStartupURL() -> String {
        let currentURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentTransportMode = recoveryTransportMode(for: currentURL)
        guard DeviceAuthStore.load() != nil,
              ["relay", "tailscale"].contains(currentTransportMode),
              let publicCandidate = cachedPublicTunnelCandidate(excluding: currentURL) else {
            return currentURL
        }

        let publicURL = publicCandidate.wsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return publicURL.isEmpty ? currentURL : publicURL
    }

    @discardableResult
    private func switchToPreferredAuthenticatedPublicRouteOnActivation() -> Bool {
        let currentURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredURL = preferredAuthenticatedStartupURL()
        guard !preferredURL.isEmpty, preferredURL != currentURL else {
            return false
        }

        webSocketManager.addMessage("回到前台，自动切换到公网通道")
        print("[Connection] foreground activation prefers cached public bridge")
        serverURL = preferredURL
        UserDefaults.standard.set(preferredURL, forKey: ServerConfig.storageKey)
        webSocketManager.beginRouteSwitch(reason: "scene_active_authenticated_preference")
        webSocketManager.reconnectAndSync(
            to: preferredURL,
            projectPath: syncProjectPathHint,
            requestId: syncRequestIdHint
        )
        return true
    }

    private func isUsableRelayCandidate(
        _ candidate: CompanionTransportCandidate,
        excluding urlString: String? = nil
    ) -> Bool {
        let excludedURL = urlString?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard isRelayRoute(transportMode: candidate.transportMode, wsURL: candidate.wsURL) else {
            return false
        }
        guard !candidate.isDisabled else { return false }
        guard !["degraded", "unhealthy", "down"].contains(candidate.normalizedHealth) else {
            return false
        }
        let wsURL = candidate.wsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWSURL = wsURL.lowercased()
        guard normalizedWSURL.hasPrefix("wss://") || normalizedWSURL.hasPrefix("ws://") else {
            return false
        }
        guard let excludedURL else { return true }
        return normalizedWSURL != excludedURL
    }

    private func cachedRelayCandidate(excluding urlString: String? = nil) -> CompanionTransportCandidate? {
        cachedTransportCandidates().first {
            isUsableRelayCandidate($0, excluding: urlString)
        }
    }

    private func recoveryRoute(from candidate: CompanionTransportCandidate) -> RecoveryRoute? {
        let wsURL = candidate.wsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wsURL.isEmpty else { return nil }

        let baseURL = candidate.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return RecoveryRoute(
            transportMode: candidate.transportMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            baseURL: baseURL.isEmpty ? ServerConfig.httpBaseURL(fromWebSocketURL: wsURL) : baseURL,
            wsURL: wsURL,
            relayDeviceID: candidate.relayDeviceID ?? relayDeviceID(fromStreamURL: wsURL)
        )
    }

    private func recoveryTransportMode(for webSocketURL: String) -> String {
        let normalized = webSocketURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: normalized) else {
            return "unknown"
        }

        let scheme = components.scheme?.lowercased()
        let host = components.host?.lowercased() ?? ""
        let path = components.percentEncodedPath.lowercased()
        if path.contains("/api/devices/") && path.hasSuffix("/stream") {
            return "relay"
        }
        if scheme == "wss" || scheme == "https" {
            if host == "iterate.tobooks.xin" {
                return "public_tunnel"
            }
            return "cloudflare_tunnel"
        }
        if isTailscaleRecoveryHost(host) {
            return "tailscale"
        }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return "loopback_fallback"
        }
        if host.hasSuffix(".local") || isPrivateRecoveryIPv4(host) {
            return "lan_fallback"
        }
        return "unknown"
    }

    private func recoveryIPv4Octets(from host: String) -> [Int]? {
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return nil
        }
        return octets
    }

    private func isTailscaleRecoveryHost(_ host: String) -> Bool {
        guard let octets = recoveryIPv4Octets(from: host), octets[0] == 100 else {
            return false
        }
        return (64...127).contains(octets[1])
    }

    private func isPrivateRecoveryIPv4(_ host: String) -> Bool {
        guard let octets = recoveryIPv4Octets(from: host) else {
            return false
        }
        return octets[0] == 10
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
    }

    private func recoveryRoute(for webSocketURL: String?) -> RecoveryRoute? {
        let currentWSURL = webSocketURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !currentWSURL.isEmpty else { return nil }

        let normalized = currentWSURL.lowercased()
        if let matched = cachedTransportCandidates().first(where: {
            $0.wsURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }), let route = recoveryRoute(from: matched) {
            return route
        }

        return RecoveryRoute(
            transportMode: recoveryTransportMode(for: currentWSURL),
            baseURL: ServerConfig.httpBaseURL(fromWebSocketURL: currentWSURL),
            wsURL: currentWSURL,
            relayDeviceID: relayDeviceID(fromStreamURL: currentWSURL)
        )
    }

    private func currentRecoveryRoute() -> RecoveryRoute {
        recoveryRoute(for: serverURL) ?? RecoveryRoute(
            transportMode: "unknown",
            baseURL: "",
            wsURL: "",
            relayDeviceID: nil
        )
    }

    private func fallbackRecoveryRoutes(after current: RecoveryRoute) -> [RecoveryRoute] {
        var routes: [RecoveryRoute] = []
        var seen = Set<String>()
        if !current.normalizedWSURL.isEmpty {
            seen.insert(current.normalizedWSURL)
        }

        let candidates = cachedTransportCandidates()
            .filter { !$0.isDisabled }
            .compactMap { recoveryRoute(from: $0) }

        func appendRoutes(transportMode: String) {
            for route in candidates where route.transportMode == transportMode {
                guard !route.normalizedWSURL.isEmpty, !seen.contains(route.normalizedWSURL) else {
                    continue
                }
                routes.append(route)
                seen.insert(route.normalizedWSURL)
            }
        }

        appendRoutes(transportMode: "tailscale")
        appendRoutes(transportMode: "relay")
        appendRoutes(transportMode: "public_tunnel")
        return routes
    }

    private func tryReconnectUsingCachedTailscale(reason: String) -> Bool {
        let currentURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let candidate = cachedTailscaleCandidate(excluding: currentURL) else {
            return false
        }

        connectToTailscaleCandidate(candidate, reason: reason, scheduleRefreshOnFailure: true)
        return true
    }

    @discardableResult
    private func tryReconnectUsingCachedPublicTunnel(
        reason: String,
        failedURL: String? = nil,
        refreshIfMissing: Bool = false
    ) -> Bool {
        let currentURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let candidate = cachedPublicTunnelCandidate(excluding: currentURL) else {
            webSocketManager.addMessage("公网通道不可用，继续保留当前通道")
            print("[HeaderAction] public_tunnel_candidate_missing reason=\(reason) failed=\(failedURL ?? "nil")")
            if refreshIfMissing {
                refreshPublicTunnelCandidateForAutomaticFallback(reason: reason, failedURL: failedURL)
            }
            return false
        }

        connectToPublicTunnelCandidate(candidate, reason: reason)
        return true
    }

    @discardableResult
    private func tryReconnectUsingCachedRelay(reason: String, failedURL: String? = nil) -> Bool {
        guard let candidate = cachedRelayCandidate(excluding: failedURL),
              let route = recoveryRoute(from: candidate) else {
            webSocketManager.addMessage("Relay 备用不可用，继续重试公网")
            print("[HeaderAction] relay_candidate_missing reason=\(reason) failed=\(failedURL ?? "nil")")
            return false
        }

        guard configureRelayRouteIfNeeded(
            transportMode: candidate.transportMode,
            baseURL: candidate.baseURL,
            wsURL: candidate.wsURL,
            relayDeviceID: candidate.relayDeviceID,
            relayPairingToken: candidate.relayPairingToken,
            source: "authenticated_transport_fallback"
        ) else {
            webSocketManager.addMessage("Relay 备用配置无效，继续重试公网")
            print("[HeaderAction] relay_candidate_invalid reason=\(reason) ws_url=\(candidate.wsURL)")
            return false
        }

        webSocketManager.addMessage("公网通道不稳定，切换到 Relay 备用: \(route.baseURL)")
        print("[HeaderAction] switch_to_relay_backup reason=\(reason) failed=\(failedURL ?? "nil") ws_url=\(route.wsURL)")
        reconnectAndSync(route: route)
        return true
    }

    private func connectToTailscaleCandidate(
        _ candidate: CompanionTransportCandidate,
        reason: String,
        scheduleRefreshOnFailure: Bool
    ) {
        let nextServerURL = candidate.wsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        webSocketManager.addMessage("切换到 Tailscale 通道: \(candidate.baseURL)")
        print("[HeaderAction] switch_to_tailscale reason=\(reason) ws_url=\(nextServerURL)")

        serverURL = nextServerURL
        UserDefaults.standard.set(nextServerURL, forKey: ServerConfig.storageKey)
        webSocketManager.beginRouteSwitch(reason: "switch_to_tailscale")
        webSocketManager.disconnect(silent: true)
        webSocketManager.reconnectAndSync(
            to: nextServerURL,
            projectPath: syncProjectPathHint,
            requestId: syncRequestIdHint
        )
        if scheduleRefreshOnFailure {
            scheduleTailscaleCandidateRefreshIfNeeded(attemptedURL: nextServerURL)
        }
    }

    private func connectToPublicTunnelCandidate(
        _ candidate: CompanionTransportCandidate,
        reason: String
    ) {
        let nextServerURL = candidate.wsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextServerURL.isEmpty else {
            webSocketManager.addMessage("公网通道缺少 WebSocket 地址")
            return
        }

        webSocketManager.addMessage("切换到公网通道: \(candidate.baseURL)")
        print("[HeaderAction] switch_to_public_tunnel reason=\(reason) ws_url=\(nextServerURL)")

        serverURL = nextServerURL
        UserDefaults.standard.set(nextServerURL, forKey: ServerConfig.storageKey)
        webSocketManager.beginRouteSwitch(reason: "switch_to_public_tunnel")
        webSocketManager.disconnect(silent: true)
        webSocketManager.reconnectAndSync(
            to: nextServerURL,
            projectPath: syncProjectPathHint,
            requestId: syncRequestIdHint
        )
    }

    private func refreshPublicTunnelCandidateForAutomaticFallback(reason: String, failedURL: String?) {
        guard !publicTunnelCandidateRefreshInFlight else {
            print("[HeaderAction] public_tunnel_refresh_skip_inflight reason=\(reason)")
            return
        }

        publicTunnelCandidateRefreshInFlight = true
        let normalizedFailedURL = failedURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let routeAtStart = normalizedFailedURL?.isEmpty == false
            ? normalizedFailedURL
            : serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        webSocketManager.addMessage("公网候选不可用，刷新配对...")
        print("[HeaderAction] public_tunnel_refresh_begin reason=\(reason) failed=\(failedURL ?? "nil")")

        fetchLatestPairingViaPublicTunnel { payload in
            DispatchQueue.main.async {
                self.publicTunnelCandidateRefreshInFlight = false

                guard let payload else {
                    self.webSocketManager.addMessage("刷新公网配对失败，继续重试当前通道")
                    print("[HeaderAction] public_tunnel_refresh_failed reason=\(reason)")
                    return
                }

                self.storeTransportCandidates(from: payload)
                let currentRoute = self.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if let routeAtStart,
                   !routeAtStart.isEmpty,
                   currentRoute != routeAtStart {
                    print("[HeaderAction] public_tunnel_refresh_skip_route_changed reason=\(reason) current=\(currentRoute) start=\(routeAtStart)")
                    return
                }

                if self.webSocketManager.isConnected {
                    print("[HeaderAction] public_tunnel_refresh_skip_recovered reason=\(reason) route=\(currentRoute)")
                    return
                }

                guard let candidate = self.publicTunnelCandidate(from: payload, excluding: routeAtStart) else {
                    self.webSocketManager.addMessage("刷新后仍没有可用公网通道")
                    print("[HeaderAction] public_tunnel_refresh_missing_candidate reason=\(reason)")
                    return
                }

                self.connectToPublicTunnelCandidate(candidate, reason: "\(reason)_refreshed")
            }
        }
    }

    private func scheduleTailscaleCandidateRefreshIfNeeded(attemptedURL: String) {
        guard !tailscaleCandidateRefreshInFlight else { return }
        tailscaleCandidateRefreshInFlight = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            self.refreshTailscaleCandidateAfterFallbackIfNeeded(attemptedURL: attemptedURL)
        }
    }

    private func refreshTailscaleCandidateAfterFallbackIfNeeded(attemptedURL: String) {
        let normalizedAttempt = attemptedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard currentURL == normalizedAttempt else {
            tailscaleCandidateRefreshInFlight = false
            print(
                "[HeaderAction] tailscale_refresh_skip_route_changed " +
                "current=\(currentURL) attempted=\(normalizedAttempt)"
            )
            return
        }

        if webSocketManager.isConnected && currentURL == normalizedAttempt {
            tailscaleCandidateRefreshInFlight = false
            print("[HeaderAction] tailscale_refresh_skip_connected ws_url=\(normalizedAttempt)")
            return
        }

        fetchLatestPairingViaPublicTunnel { payload in
            DispatchQueue.main.async {
                self.tailscaleCandidateRefreshInFlight = false

                let activeURL = self.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard activeURL == normalizedAttempt else {
                    print(
                        "[HeaderAction] tailscale_refresh_skip_route_changed_after_fetch " +
                        "current=\(activeURL) attempted=\(normalizedAttempt)"
                    )
                    return
                }

                guard let payload else {
                    self.keepTailscaleFallbackAfterRefreshFailure(
                        reason: "Tailscale 备用通道暂未连上，刷新配对失败",
                        attemptedURL: normalizedAttempt
                    )
                    return
                }

                self.storeTransportCandidates(from: payload)
                guard let refreshedCandidate = self.tailscaleCandidate(from: payload) else {
                    self.keepTailscaleFallbackAfterRefreshFailure(
                        reason: "Tailscale 备用通道暂未连上，刷新后没有新的 Tailscale 候选",
                        attemptedURL: normalizedAttempt
                    )
                    return
                }

                let refreshedURL = refreshedCandidate.wsURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !refreshedURL.isEmpty, refreshedURL != normalizedAttempt else {
                    self.keepTailscaleFallbackAfterRefreshFailure(
                        reason: "Tailscale 备用通道暂未连上，刷新后地址未变化",
                        attemptedURL: normalizedAttempt
                    )
                    return
                }

                self.webSocketManager.addMessage("已刷新配对，重试新的 Tailscale 通道: \(refreshedCandidate.baseURL)")
                print("[HeaderAction] tailscale_candidate_refreshed old=\(normalizedAttempt) new=\(refreshedURL)")
                self.connectToTailscaleCandidate(
                    refreshedCandidate,
                    reason: "refreshed_pairing_after_failure",
                    scheduleRefreshOnFailure: false
                )
            }
        }
    }

    private func keepTailscaleFallbackAfterRefreshFailure(reason: String, attemptedURL: String) {
        let nextURL = attemptedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextURL.isEmpty else { return }

        webSocketManager.addMessage("\(reason)，继续保留 Tailscale 通道")
        print("[HeaderAction] tailscale_fallback_keep_route reason=\(reason) ws_url=\(nextURL)")

        serverURL = nextURL
        UserDefaults.standard.set(nextURL, forKey: ServerConfig.storageKey)
        webSocketManager.beginRouteSwitch(reason: "keep_tailscale_fallback")
        webSocketManager.disconnect(silent: true)
        webSocketManager.reconnectAndSync(
            to: nextURL,
            projectPath: syncProjectPathHint,
            requestId: syncRequestIdHint
        )
    }

    private func fetchLatestPairingViaPublicTunnel(completion: @escaping (CompanionPairingPayload?) -> Void) {
        let publicWebSocketURL = publicTunnelWebSocketURL()
        guard ServerConfig.hasConfiguredWebSocketURL(publicWebSocketURL) else {
            print("[HeaderAction] pairing refresh skipped: missing public tunnel URL")
            completion(nil)
            return
        }
        let httpBase = ServerConfig.httpBaseURL(fromWebSocketURL: publicWebSocketURL)
        guard !httpBase.isEmpty, let url = URL(string: httpBase + "/api/mobile/pairing") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        DeviceAuthStore.applyAuthHeaders(to: &request)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                print("[HeaderAction] pairing refresh failed: \(error.localizedDescription)")
                completion(nil)
                return
            }

            if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "pairing_refresh") {
                completion(nil)
                return
            }

            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), let data else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[HeaderAction] pairing refresh http status=\(status)")
                completion(nil)
                return
            }

            let pairing = try? JSONDecoder().decode(CompanionPairingResponse.self, from: data).pairing
            completion(pairing)
        }.resume()
    }

    private func tailscaleCandidate(from payload: CompanionPairingPayload) -> CompanionTransportCandidate? {
        if let candidate = payload.candidates?.first(where: {
            $0.transportMode == "tailscale"
                && !$0.isDisabled
                && !$0.wsURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            return candidate
        }

        if payload.transportMode == "tailscale" {
            return CompanionTransportCandidate(
                transportMode: payload.transportMode,
                baseURL: payload.baseURL,
                wsURL: payload.wsURL,
                relayDeviceID: payload.relayDeviceID,
                relayPairingToken: payload.relayPairingToken,
                health: payload.health,
                disabled: payload.disabled,
                warning: payload.warning
            )
        }

        return nil
    }

    private func publicTunnelCandidate(
        from payload: CompanionPairingPayload,
        excluding urlString: String? = nil
    ) -> CompanionTransportCandidate? {
        if let candidate = payload.candidates?.first(where: {
            isUsablePublicTunnelCandidate($0, excluding: urlString)
        }) {
            return candidate
        }

        let primary = CompanionTransportCandidate(
            transportMode: payload.transportMode,
            baseURL: payload.baseURL,
            wsURL: payload.wsURL,
            relayDeviceID: payload.relayDeviceID,
            relayPairingToken: payload.relayPairingToken,
            health: payload.health,
            disabled: payload.disabled,
            warning: payload.warning
        )
        return isUsablePublicTunnelCandidate(primary, excluding: urlString) ? primary : nil
    }

    private func publicTunnelWebSocketURL() -> String {
        cachedTransportCandidates().first {
            isUsablePublicTunnelCandidate($0)
        }?.wsURL.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    private func reconnectAndSyncCurrentRoute(after delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.webSocketManager.reconnectAndSync(
                to: self.serverURL,
                projectPath: self.syncProjectPathHint,
                requestId: self.syncRequestIdHint
            )
            print("[HeaderAction] reconnectAndSyncCurrentRoute")
        }
    }

    private func reconnectAndSync(route: RecoveryRoute, after delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let nextURL = route.wsURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nextURL.isEmpty else {
                self.reconnectAndSyncCurrentRoute()
                return
            }

            self.configureRelayRouteIfNeeded(
                transportMode: route.transportMode,
                baseURL: route.baseURL,
                wsURL: nextURL,
                relayDeviceID: route.relayDeviceID,
                relayPairingToken: nil,
                source: "recovery_route"
            )
            self.serverURL = nextURL
            UserDefaults.standard.set(nextURL, forKey: ServerConfig.storageKey)
            self.webSocketManager.reconnectAndSync(
                to: nextURL,
                projectPath: self.syncProjectPathHint,
                requestId: self.syncRequestIdHint
            )
            print("[HeaderAction] reconnectAndSyncRoute transport=\(route.transportMode) ws_url=\(nextURL)")
        }
    }

    private func configureTransportFallbackHandler() {
        webSocketManager.onDirectBridgeFallbackRequested = { reason, failedURL in
            tryReconnectUsingCachedPublicTunnel(
                reason: "\(reason)_direct_to_public",
                failedURL: failedURL,
                refreshIfMissing: true
            )
        }
        webSocketManager.onTailscaleFallbackRequested = { reason, failedURL in
            tryReconnectUsingCachedPublicTunnel(reason: reason, failedURL: failedURL, refreshIfMissing: true)
        }
        webSocketManager.onAuthenticatedTransportFallbackRequested = { reason, failedURL in
            if recoveryTransportMode(for: failedURL ?? "") == "relay",
               tryReconnectUsingCachedPublicTunnel(
                   reason: "\(reason)_relay_to_public",
                   failedURL: failedURL,
                   refreshIfMissing: true
               ) {
                return true
            }
            if tryRelayAutoRecoveryForAuthenticatedFailure(reason: reason, failedURL: failedURL) {
                return true
            }
            return tryReconnectUsingCachedRelay(reason: reason, failedURL: failedURL)
        }
    }

    private func isCurrentRouteTailscale() -> Bool {
        webSocketManager.currentTransportMode == "tailscale"
    }

    private func handleConnectionStatusTap() {
        if connectionPresentationState == .needsPairing {
            if DeviceAuthStore.load() != nil {
                webSocketManager.retryStoredDeviceAuthAndSync(
                    to: serverURL,
                    projectPath: syncProjectPathHint,
                    requestId: syncRequestIdHint,
                    reason: "status_button_stored_device_auth"
                )
            } else {
                webSocketManager.addMessage("设备授权尚未保存，请扫描桌面端配对二维码")
            }
            return
        }

        if isCurrentRouteTailscale(),
           !webSocketManager.isConnected,
           tryReconnectUsingCachedPublicTunnel(reason: "status_button_tailscale_unavailable") {
            return
        }

        restartTunnel()
    }

    private func unpairThisIPhone() {
        webSocketManager.disconnect(silent: true)
        PairingURLBridge.clearPendingURL()
        DeviceAuthStore.clear(reason: "manual_unpair")
        RelayAuthStore.clear(reason: "manual_unpair")

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.transportCandidatesStorageKey)
        defaults.removeObject(forKey: ServerConfig.storageKey)
        defaults.removeObject(forKey: ServerConfig.relayControlBaseURLKey)
        defaults.removeObject(forKey: ServerConfig.relayMacDeviceIDKey)
        defaults.removeObject(forKey: ServerConfig.relayAutoRecoverOnActivationKey)
        defaults.removeObject(forKey: ServerConfig.relayLastAutoRecoverAtKey)
        ServerConfig.removeLegacyRelayControlTokens()

        serverURL = ServerConfig.defaultWebSocketURL
        relayControlBaseURL = ""
        relayMacDeviceID = "local-mac"
        relayAutoRecoverOnActivation = false
        relayLastAutoRecoverAt = 0
        hasDeviceAuthorization = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func switchToPublicTunnelFromMenu() {
        if !tryReconnectUsingCachedPublicTunnel(reason: "manual_status_menu") {
            fetchLatestPairingViaPublicTunnel { payload in
                DispatchQueue.main.async {
                    guard let payload else {
                        webSocketManager.addMessage("刷新配对失败，无法切到公网")
                        return
                    }

                    storeTransportCandidates(from: payload)
                    if !tryReconnectUsingCachedPublicTunnel(reason: "manual_status_menu_refreshed") {
                        webSocketManager.addMessage("公网通道当前不可用")
                    }
                }
            }
        }
    }

    private func restartTunnel() {
        let route = currentRecoveryRoute()
        runConnectionDiagnostics(route: route, fallbackRoutes: fallbackRecoveryRoutes(after: route))
    }

    private func applyRecoveryHeaders(to request: inout URLRequest, route: RecoveryRoute) {
        request.setValue("ios", forHTTPHeaderField: "X-Iterate-Client-Kind")
        request.setValue(route.transportMode, forHTTPHeaderField: "X-Iterate-Recovery-Transport")
        DeviceAuthStore.applyAuthHeaders(to: &request)
    }

    private func normalizedRelayControlBaseURL() -> String? {
        var baseURL = relayControlBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")

        while baseURL.hasSuffix("/") {
            baseURL.removeLast()
        }

        return baseURL.isEmpty ? nil : baseURL
    }

    private func relayPathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func applyRelayHeaders(to request: inout URLRequest) {
        request.setValue("ios", forHTTPHeaderField: "X-Iterate-Client-Kind")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let configuredMacDeviceID = relayMacDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        RelayAuthStore.applyAuthHeaders(
            to: &request,
            relayBaseURL: relayControlBaseURL,
            relayDeviceID: configuredMacDeviceID.isEmpty ? "local-mac" : configuredMacDeviceID
        )
    }

    private func configureRelayCommandTransport() {
        let configuredMacDeviceID = relayMacDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let macDeviceID = configuredMacDeviceID.isEmpty ? "local-mac" : configuredMacDeviceID
        let scopedRelayToken = RelayAuthStore.load(
            relayBaseURL: relayControlBaseURL,
            relayDeviceID: macDeviceID
        )?.deviceToken ?? ""
        webSocketManager.configureRelayCommandTransport(
            baseURL: relayControlBaseURL,
            token: scopedRelayToken,
            deviceID: macDeviceID
        )
    }

    private func connectUsingConfiguredTransport(reason: String) {
        configureRelayCommandTransport()
        let connectionURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ServerConfig.hasConfiguredWebSocketURL(connectionURL) else {
            webSocketManager.addMessage("连接地址未配置")
            return
        }
        webSocketManager.addMessage("正在连接: \(reason)")
        if webSocketManager.isConnected || webSocketManager.isConnecting {
            webSocketManager.beginRouteSwitch(reason: "connect_configured_transport")
            webSocketManager.disconnect(silent: true)
        }
        webSocketManager.connect(to: serverURL)
    }

    private func connectUsingRelayBackup(reason: String) {
        configureRelayCommandTransport()
        guard let relayURL = webSocketManager.relayBackupWebSocketURL(),
              ServerConfig.hasConfiguredWebSocketURL(relayURL) else {
            webSocketManager.addMessage("Relay 备用未配置")
            return
        }
        webSocketManager.addMessage("正在连接 Relay 备用: \(reason)")
        if webSocketManager.isConnected || webSocketManager.isConnecting {
            webSocketManager.beginRouteSwitch(reason: "connect_relay_backup")
            webSocketManager.disconnect(silent: true)
        }
        serverURL = relayURL
        UserDefaults.standard.set(relayURL, forKey: ServerConfig.storageKey)
        webSocketManager.connect(to: relayURL)
    }

    private func relayAutoRecoveryConfigured() -> Bool {
        normalizedRelayControlBaseURL() != nil
            && !relayMacDeviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func attemptRelayAutoRecoveryIfNeeded(reason: String) {
        let now = Date().timeIntervalSince1970
        let decision = RelayAutoRecoveryPolicy.decision(
            isEnabled: relayAutoRecoverOnActivation,
            isConfigured: relayAutoRecoveryConfigured(),
            isConnected: webSocketManager.isConnected,
            isConnecting: webSocketManager.isConnecting,
            isInFlight: relayAutoRecoveryInFlight,
            lastAttemptAt: relayLastAutoRecoverAt,
            now: now,
            currentTransportMode: webSocketManager.currentTransportMode,
            failedTransportMode: nil
        )
        guard decision == .attempt else {
            let remaining = RelayAutoRecoveryPolicy.cooldownRemaining(
                lastAttemptAt: relayLastAutoRecoverAt,
                now: now
            )
            print(
                "[RelayRecovery] auto_skip reason=\(reason) " +
                "decision=\(decision.logReason) remaining=\(max(0, Int(remaining)))"
            )
            return
        }

        startRelayPublicTunnelRecovery(
            reason: reason,
            reconnectRouteAfterSuccess: currentRecoveryRoute(),
            fallbackToRelayOnFailure: false
        )
    }

    @discardableResult
    private func tryRelayAutoRecoveryForAuthenticatedFailure(reason: String, failedURL: String?) -> Bool {
        let failedRoute = recoveryRoute(for: failedURL)
        let now = Date().timeIntervalSince1970
        let decision = RelayAutoRecoveryPolicy.decision(
            isEnabled: relayAutoRecoverOnActivation,
            isConfigured: relayAutoRecoveryConfigured(),
            isConnected: webSocketManager.isConnected,
            isConnecting: webSocketManager.isConnecting,
            isInFlight: relayAutoRecoveryInFlight,
            lastAttemptAt: relayLastAutoRecoverAt,
            now: now,
            currentTransportMode: webSocketManager.currentTransportMode,
            failedTransportMode: failedRoute?.transportMode
        )

        guard decision == .attempt else {
            print(
                "[RelayRecovery] auth_failure_skip reason=\(reason) " +
                "failed=\(failedURL ?? "nil") decision=\(decision.logReason)"
            )
            return false
        }

        startRelayPublicTunnelRecovery(
            reason: "auth_failure:\(reason)",
            reconnectRouteAfterSuccess: failedRoute ?? currentRecoveryRoute(),
            fallbackToRelayOnFailure: true
        )
        return true
    }

    private func startRelayPublicTunnelRecovery(
        reason: String,
        reconnectRouteAfterSuccess: RecoveryRoute?,
        fallbackToRelayOnFailure: Bool
    ) {
        relayAutoRecoveryInFlight = true
        webSocketManager.addMessage("公网连接未恢复，正在通过 Relay 请求 Mac 自愈公网通道...")
        print(
            "[RelayRecovery] auto_recover_start reason=\(reason) " +
            "transport=\(webSocketManager.currentTransportMode)"
        )
        requestPublicTunnelRecoveryViaRelay(
            markAutoCooldownOnSuccess: true,
            reconnectRouteAfterSuccess: reconnectRouteAfterSuccess,
            fallbackToRelayOnFailure: fallbackToRelayOnFailure
        )
    }

    private func finishRelayAutoRecoveryAttempt(markAutoCooldownOnSuccess: Bool, succeeded: Bool) {
        guard markAutoCooldownOnSuccess else { return }
        relayAutoRecoveryInFlight = false
        if succeeded {
            relayLastAutoRecoverAt = Date().timeIntervalSince1970
        }
    }

    private func fallbackToRelayBackupAfterRecoveryFailure(
        shouldFallback: Bool,
        reason: String,
        failedURL: String?
    ) {
        guard shouldFallback else { return }
        if !tryReconnectUsingCachedRelay(reason: reason, failedURL: failedURL) {
            reconnectAndSyncCurrentRoute(after: 3)
        }
    }

    private func requestPublicTunnelRecoveryViaRelay(
        markAutoCooldownOnSuccess: Bool = false,
        reconnectRouteAfterSuccess: RecoveryRoute? = nil,
        fallbackToRelayOnFailure: Bool = false
    ) {
        guard let relayBaseURL = normalizedRelayControlBaseURL() else {
            webSocketManager.addMessage("Relay 控制面未配置：请先设置 \(ServerConfig.relayControlBaseURLKey)")
            finishRelayAutoRecoveryAttempt(markAutoCooldownOnSuccess: markAutoCooldownOnSuccess, succeeded: false)
            fallbackToRelayBackupAfterRecoveryFailure(
                shouldFallback: fallbackToRelayOnFailure,
                reason: "relay_recovery_missing_control_base",
                failedURL: reconnectRouteAfterSuccess?.wsURL
            )
            return
        }

        let configuredMacDeviceID = relayMacDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let macDeviceID = configuredMacDeviceID.isEmpty ? "local-mac" : configuredMacDeviceID
        let encodedDeviceID = relayPathComponent(macDeviceID)
        guard let url = URL(string: "\(relayBaseURL)/api/devices/\(encodedDeviceID)/commands") else {
            webSocketManager.addMessage("Relay 控制面地址无效")
            finishRelayAutoRecoveryAttempt(markAutoCooldownOnSuccess: markAutoCooldownOnSuccess, succeeded: false)
            fallbackToRelayBackupAfterRecoveryFailure(
                shouldFallback: fallbackToRelayOnFailure,
                reason: "relay_recovery_invalid_control_url",
                failedURL: reconnectRouteAfterSuccess?.wsURL
            )
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        applyRelayHeaders(to: &request)
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "type": "recover_public_tunnel"
        ])

        webSocketManager.addMessage("正在通过 Relay 请求 Mac 修复公网通道...")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                var commandCreated = false
                defer {
                    self.finishRelayAutoRecoveryAttempt(
                        markAutoCooldownOnSuccess: markAutoCooldownOnSuccess,
                        succeeded: commandCreated
                    )
                }

                if let error {
                    self.webSocketManager.addMessage("Relay 修复请求未送达：\(error.localizedDescription)")
                    print("[RelayRecovery] create command failed: \(error.localizedDescription)")
                    self.fallbackToRelayBackupAfterRecoveryFailure(
                        shouldFallback: fallbackToRelayOnFailure,
                        reason: "relay_recovery_create_failed",
                        failedURL: reconnectRouteAfterSuccess?.wsURL
                    )
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    self.webSocketManager.addMessage("Relay 修复响应无效")
                    return
                }

                let json = self.jsonValue(data)
                guard (200...299).contains(http.statusCode) else {
                    let errorCode = json?["error"] as? String ?? "unknown"
                    self.webSocketManager.addMessage("Relay 修复请求失败：HTTP \(http.statusCode) \(errorCode)")
                    print("[RelayRecovery] create command http=\(http.statusCode) error=\(errorCode)")
                    self.fallbackToRelayBackupAfterRecoveryFailure(
                        shouldFallback: fallbackToRelayOnFailure,
                        reason: "relay_recovery_create_http_failed",
                        failedURL: reconnectRouteAfterSuccess?.wsURL
                    )
                    return
                }

                guard let command = json?["command"] as? [String: Any],
                      let commandID = command["command_id"] as? String,
                      !commandID.isEmpty else {
                    self.webSocketManager.addMessage("Relay 已响应，但缺少 command_id")
                    self.fallbackToRelayBackupAfterRecoveryFailure(
                        shouldFallback: fallbackToRelayOnFailure,
                        reason: "relay_recovery_missing_command_id",
                        failedURL: reconnectRouteAfterSuccess?.wsURL
                    )
                    return
                }

                commandCreated = true
                self.webSocketManager.addMessage("Relay 已下发恢复命令，等待 Mac 执行...")
                print("[RelayRecovery] command_created id=\(commandID)")
                self.pollRelayCommandResult(
                    relayBaseURL: relayBaseURL,
                    commandID: commandID,
                    attemptsRemaining: 10,
                    reconnectRouteAfterSuccess: reconnectRouteAfterSuccess,
                    fallbackToRelayOnFailure: fallbackToRelayOnFailure
                )
            }
        }.resume()
    }

    private func pollRelayCommandResult(
        relayBaseURL: String,
        commandID: String,
        attemptsRemaining: Int,
        reconnectRouteAfterSuccess: RecoveryRoute? = nil,
        fallbackToRelayOnFailure: Bool = false
    ) {
        guard attemptsRemaining > 0 else {
            webSocketManager.addMessage("Relay 已接收命令，但等待 Mac 回传结果超时")
            print("[RelayRecovery] command_result_timeout id=\(commandID)")
            fallbackToRelayBackupAfterRecoveryFailure(
                shouldFallback: fallbackToRelayOnFailure,
                reason: "relay_recovery_result_timeout",
                failedURL: reconnectRouteAfterSuccess?.wsURL
            )
            return
        }

        guard let url = URL(string: "\(relayBaseURL)/api/commands/\(relayPathComponent(commandID))") else {
            webSocketManager.addMessage("Relay 命令查询地址无效")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        applyRelayHeaders(to: &request)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    self.webSocketManager.addMessage("Relay 命令结果查询失败：\(error.localizedDescription)")
                    print("[RelayRecovery] command poll failed: \(error.localizedDescription)")
                    self.fallbackToRelayBackupAfterRecoveryFailure(
                        shouldFallback: fallbackToRelayOnFailure,
                        reason: "relay_recovery_poll_failed",
                        failedURL: reconnectRouteAfterSuccess?.wsURL
                    )
                    return
                }

                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    self.webSocketManager.addMessage("Relay 命令结果查询失败：HTTP \(status)")
                    self.fallbackToRelayBackupAfterRecoveryFailure(
                        shouldFallback: fallbackToRelayOnFailure,
                        reason: "relay_recovery_poll_http_failed",
                        failedURL: reconnectRouteAfterSuccess?.wsURL
                    )
                    return
                }

                let json = self.jsonValue(data)
                let command = json?["command"] as? [String: Any]
                let status = command?["status"] as? String ?? "unknown"
                if ["pending", "delivered", "running"].contains(status) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.pollRelayCommandResult(
                            relayBaseURL: relayBaseURL,
                            commandID: commandID,
                            attemptsRemaining: attemptsRemaining - 1,
                            reconnectRouteAfterSuccess: reconnectRouteAfterSuccess,
                            fallbackToRelayOnFailure: fallbackToRelayOnFailure
                        )
                    }
                    return
                }

                let shouldReconnect = self.handleRelayCommandResult(command: command, status: status)
                if shouldReconnect, let reconnectRouteAfterSuccess {
                    self.webSocketManager.addMessage("公网恢复后重新连接...")
                    self.reconnectAndSync(route: reconnectRouteAfterSuccess, after: 2)
                } else if fallbackToRelayOnFailure {
                    self.fallbackToRelayBackupAfterRecoveryFailure(
                        shouldFallback: true,
                        reason: "relay_recovery_result_not_success",
                        failedURL: reconnectRouteAfterSuccess?.wsURL
                    )
                }
            }
        }.resume()
    }

    @discardableResult
    private func handleRelayCommandResult(command: [String: Any]?, status: String) -> Bool {
        let result = command?["result"] as? [String: Any]
        let simulated = result?["simulated"] as? Bool ?? false
        let summary = result?["summary"] as? [String: Any]
        let rootHealth = summary?["root_tunnel_health_class"] as? String
        let publicTunnel = summary?["public_tunnel"] as? String
        let note = result?["note"] as? String

        switch status {
        case "succeeded" where simulated:
            webSocketManager.addMessage("Relay 已送达 Mac；当前 Mac client 是模拟模式，未执行真实公网恢复")
        case "succeeded":
            let detail = [publicTunnel.map { "public=\($0)" }, rootHealth.map { "root=\($0)" }]
                .compactMap { $0 }
                .joined(separator: " ")
            webSocketManager.addMessage(detail.isEmpty ? "Relay 公网恢复命令已执行" : "Relay 公网恢复命令已执行：\(detail)")
        case "cooldown_blocked":
            webSocketManager.addMessage("Relay 恢复命令处于冷却中，请稍后再试")
        case "expired":
            webSocketManager.addMessage("Relay 恢复命令已过期，Mac 未及时接收")
        default:
            webSocketManager.addMessage("Relay 恢复命令结束：\(status)")
        }

        if let note, !note.isEmpty {
            print("[RelayRecovery] note=\(note)")
        }
        print("[RelayRecovery] command_result status=\(status) simulated=\(simulated)")
        return status == "succeeded" && !simulated
    }

    @discardableResult
    private func tryNextRecoveryRoute(
        _ fallbackRoutes: [RecoveryRoute],
        after route: RecoveryRoute,
        reason: String
    ) -> Bool {
        guard let nextRoute = fallbackRoutes.first else {
            return false
        }
        let remainingRoutes = Array(fallbackRoutes.dropFirst())
        webSocketManager.addMessage("\(route.label)不可达，尝试通过\(nextRoute.label)恢复...")
        print(
            "[HeaderAction] recovery_fallback reason=\(reason) " +
            "from=\(route.transportMode) to=\(nextRoute.transportMode)"
        )
        runConnectionDiagnostics(route: nextRoute, fallbackRoutes: remainingRoutes)
        return true
    }

    private func runConnectionDiagnostics(route: RecoveryRoute, fallbackRoutes: [RecoveryRoute]) {
        if route.transportMode == "relay" {
            webSocketManager.addMessage("正在通过 Relay 连接当前 Mac...")
            reconnectAndSync(route: route)
            return
        }

        guard let diagnosticsURL = URL(string: route.baseURL + "/api/diagnostics") else { return }
        var diagnosticsRequest = URLRequest(url: diagnosticsURL)
        diagnosticsRequest.httpMethod = "GET"
        diagnosticsRequest.timeoutInterval = 15
        applyRecoveryHeaders(to: &diagnosticsRequest, route: route)

        webSocketManager.addMessage("正在通过\(route.label)检查连接状态...")

        URLSession.shared.dataTask(with: diagnosticsRequest) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    if self.tryNextRecoveryRoute(
                        fallbackRoutes,
                        after: route,
                        reason: "diagnostics_error:\(error.localizedDescription)"
                    ) {
                        return
                    }
                    self.webSocketManager.addMessage("连接诊断不可达，保留当前内容并重连：\(error.localizedDescription)")
                    print("[HeaderAction] diagnostics failed: \(error.localizedDescription)")
                    self.reconnectAndSync(route: route)
                    return
                }

                if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "connection_diagnostics") {
                    return
                }

                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    self.webSocketManager.addMessage("\(route.label)连接诊断失败: HTTP \(http.statusCode)")
                    print("[HeaderAction] diagnostics http status=\(http.statusCode) transport=\(route.transportMode)")
                    self.sendTunnelRecoveryRequest(route: route, fallbackRoutes: fallbackRoutes)
                    return
                }

                let json = self.jsonValue(data)
                let localHealthy = self.diagnosticsBool(
                    json,
                    flatKey: "local_healthy",
                    path: ["local_origin", "healthy"]
                )
                let localWS = self.diagnosticsBool(
                    json,
                    flatKey: "local_ws",
                    path: ["local_origin", "websocket", "upgrade_ok"]
                )
                let publicHealthy = self.diagnosticsBool(
                    json,
                    flatKey: "public_healthy",
                    path: ["public_tunnel", "healthy"]
                )
                let publicWS = self.diagnosticsBool(
                    json,
                    flatKey: "public_ws",
                    path: ["public_tunnel", "websocket", "upgrade_ok"]
                )
                let ha = self.diagnosticsString(
                    json,
                    flatKey: "ha",
                    path: ["root_tunnel", "metrics", "ha_connections"]
                ) ?? "?"
                let diagnosis = json?["diagnosis"] as? [String: Any]
                let diagnosisCode = diagnosis?["code"] as? String ?? "unknown"

                print(
                    "[HeaderAction] diagnostics ok local=\(localHealthy) local_ws=\(localWS) " +
                    "public=\(publicHealthy) public_ws=\(publicWS) ha=\(ha) code=\(diagnosisCode) " +
                    "transport=\(route.transportMode)"
                )

                if (localHealthy && localWS && publicHealthy && publicWS) || diagnosisCode == "ok" {
                    self.webSocketManager.addMessage("\(route.label)连接诊断正常，跳过重启，直接刷新当前对话")
                    self.reconnectAndSync(route: route)
                    return
                }

                self.webSocketManager.addMessage(
                    "\(route.label)连接异常：local=\(localHealthy ? "ok" : "fail") ws=\(localWS ? "ok" : "fail") " +
                    "public=\(publicHealthy ? "ok" : "fail") public_ws=\(publicWS ? "ok" : "fail")"
                )
                self.sendTunnelRecoveryRequest(route: route, fallbackRoutes: fallbackRoutes)
            }
        }.resume()
    }

    private func sendTunnelRecoveryRequest(route: RecoveryRoute, fallbackRoutes: [RecoveryRoute]) {
        guard let url = URL(string: route.baseURL + "/api/restart-tunnel") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        applyRecoveryHeaders(to: &request, route: route)
        
        webSocketManager.addMessage("正在通过\(route.label)请求桌面端恢复 tunnel...")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    if self.tryNextRecoveryRoute(
                        fallbackRoutes,
                        after: route,
                        reason: "restart_tunnel_error:\(error.localizedDescription)"
                    ) {
                        return
                    }
                    self.webSocketManager.addMessage("恢复请求未送达，保留当前内容并重连：\(error.localizedDescription)")
                    print("[HeaderAction] restartTunnel request failed: \(error.localizedDescription)")
                    self.reconnectAndSync(route: route)
                } else {
                    if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "restart_tunnel") {
                        return
                    }

                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        if self.tryNextRecoveryRoute(
                            fallbackRoutes,
                            after: route,
                            reason: "restart_tunnel_http_\(http.statusCode)"
                        ) {
                            return
                        }
                        self.webSocketManager.addMessage("恢复连接失败: HTTP \(http.statusCode)")
                        print("[HeaderAction] restartTunnel http status=\(http.statusCode)")
                        return
                    }

                    let json = self.jsonValue(data)
                    let result = json?["result"] as? [String: Any]
                    let action = json?["action"] as? String ?? result?["action"] as? String ?? "unknown"
                    let message = json?["message"] as? String ?? result?["message"] as? String
                    if let message, !message.isEmpty {
                        self.webSocketManager.addMessage(message)
                    } else {
                        self.webSocketManager.addMessage("恢复请求已处理: \(action)")
                    }

                    let reconnectDelay: TimeInterval = action == "requested_root_recovery" ? 5 : 1
                    print(
                        "[HeaderAction] restartTunnel accepted action=\(action) " +
                        "transport=\(route.transportMode) reconnectDelay=\(reconnectDelay)"
                    )
                    self.reconnectAndSync(route: route, after: reconnectDelay)
                }
            }
        }.resume()
    }

    private func openDesktopCodexNewChat() {
        var httpBase = serverURL
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")
        if httpBase.hasSuffix("/ws") {
            httpBase = String(httpBase.dropLast(3))
        }

        guard let url = URL(string: httpBase + "/api/open-codex-chat") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        DeviceAuthStore.applyAuthHeaders(to: &request)

        let projectPath = targetProjectPathForCodexZhi()
        let body: [String: Any?] = [
            "project_path": projectPath
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body.compactMapValues { $0 })

        webSocketManager.addMessage("正在打开桌面 Codex...")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.webSocketManager.addMessage("打开桌面 Codex 失败：\(error.localizedDescription)")
                    print("[HeaderAction] openDesktopCodexNewChat failed: \(error.localizedDescription)")
                    return
                }

                if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "open_codex_chat") {
                    return
                }

                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    self.webSocketManager.addMessage("打开桌面 Codex 失败: HTTP \(http.statusCode)")
                    print("[HeaderAction] openDesktopCodexNewChat http status=\(http.statusCode)")
                    return
                }

                if
                    let data,
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let ok = json["ok"] as? Bool,
                    !ok
                {
                    let message = (json["error"] as? String) ?? "未知错误"
                    self.webSocketManager.addMessage("打开桌面 Codex 失败：\(message)")
                    print("[HeaderAction] openDesktopCodexNewChat api error=\(message)")
                    return
                }

                let sent = (jsonValue(data)?["sent"] as? Bool) ?? false
                let responseMessage = (jsonValue(data)?["message"] as? String)
                    ?? (sent ? "已打开桌面 Codex 并自动发送 zhi" : "已打开桌面 Codex，但未自动发送，请手动回车")
                self.webSocketManager.addMessage(responseMessage)
                print("[HeaderAction] openDesktopCodexNewChat accepted: sent=\(sent)")
            }
        }.resume()
    }

    private var codexDefaultProjectPath: String? {
        _ = codexDefaultPathVersion
        return CodexDefaultProjectPathStore.path(for: activeSessionsCacheKey)
    }

    private func setCodexDefaultProjectPath(_ projectPath: String) {
        guard let normalizedPath = CodexProjectPathResolver.normalized(projectPath) else {
            webSocketManager.addMessage("默认路径无效，请选择 Mac 上的绝对路径")
            return
        }
        CodexDefaultProjectPathStore.setPath(normalizedPath, for: activeSessionsCacheKey)
        codexDefaultPathVersion += 1
        webSocketManager.addMessage("已设置 Codex 默认路径：\(normalizedPath)")
    }

    private func normalizedCodexProjectPath(_ projectPath: String?) -> String? {
        CodexProjectPathResolver.normalized(projectPath)
    }

    private func targetProjectPathCandidates() -> [String?] {
        let activeProjectPath = ActiveProjectCache.projectsByBaseURL[activeSessionsCacheKey]?
            .first(where: { $0.isCurrent })?
            .projectPath
        let cachedProjectPath = ActiveProjectCache.projectsByBaseURL[activeSessionsCacheKey]?
            .first?
            .projectPath
        let messageProjectPath = webSocketManager.mcpMessages
            .compactMap { normalizedCodexProjectPath($0.payload?.request?.projectPath) }
            .first

        return [
            currentRequest?.projectPath,
            focusedProjectPath,
            activeProjectPath,
            messageProjectPath,
            cachedProjectPath
        ]
    }

    private func targetProjectPathForCodexZhi() -> String? {
        CodexProjectPathResolver.resolvePreferringDefault(
            candidates: targetProjectPathCandidates(),
            defaultPath: codexDefaultProjectPath
        )
    }

    private func targetProjectPathsForFileSelector() -> [String] {
        var paths: [String] = []
        for candidate in targetProjectPathCandidates() {
            guard let path = normalizedCodexProjectPath(candidate),
                  !paths.contains(path) else {
                continue
            }
            paths.append(path)
        }
        return paths
    }

    private func jsonValue(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func diagnosticsValue(_ json: [String: Any]?, path: [String]) -> Any? {
        var current: Any? = json
        for key in path {
            guard let dict = current as? [String: Any] else {
                return nil
            }
            current = dict[key]
        }
        return current
    }

    private func diagnosticsBool(_ json: [String: Any]?, flatKey: String, path: [String]) -> Bool {
        if let value = diagnosticsValue(json, path: path) as? Bool {
            return value
        }
        return json?[flatKey] as? Bool ?? false
    }

    private func diagnosticsString(_ json: [String: Any]?, flatKey: String, path: [String]) -> String? {
        if let value = diagnosticsValue(json, path: path) as? String {
            return value
        }
        if let value = diagnosticsValue(json, path: path) as? CustomStringConvertible {
            return value.description
        }
        if let value = json?[flatKey] as? String {
            return value
        }
        if let value = json?[flatKey] as? CustomStringConvertible {
            return value.description
        }
        return nil
    }

    private func toggleNotificationsFromUser() {
        webSocketManager.toggleNotifications()
        guard webSocketManager.notificationsEnabled else { return }
        (UIApplication.shared.delegate as? AppDelegate)?
            .requestNotificationPermission(
                UIApplication.shared,
                openSettingsIfDenied: true
            )
    }

    private func handlePreventSleepToggle() {
        guard pendingPreventSleepTarget == nil else { return }
        guard webSocketManager.isConnected else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            showPreventSleepFeedback("当前未连接，暂时无法切换", duration: 2.6, isWarning: true)
            return
        }

        let target = !webSocketManager.preventSleepEnabled
        pendingPreventSleepTarget = target
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showPreventSleepFeedback(
            target ? "正在开启合盖运行…" : "正在关闭合盖运行…",
            duration: 3.2
        )
        webSocketManager.togglePreventSleep()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard pendingPreventSleepTarget == target else { return }
            pendingPreventSleepTarget = nil
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            showPreventSleepFeedback("切换超时，请检查连接", duration: 2.8, isWarning: true)
        }
    }

    private func showPreventSleepFeedback(
        _ text: String,
        duration: TimeInterval,
        isWarning: Bool = false
    ) {
        preventSleepFeedbackGeneration += 1
        let generation = preventSleepFeedbackGeneration
        preventSleepFeedbackIsWarning = isWarning
        withAnimation(.easeOut(duration: 0.16)) {
            preventSleepFeedbackText = text
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard preventSleepFeedbackGeneration == generation else { return }
            withAnimation(.easeIn(duration: 0.16)) {
                preventSleepFeedbackText = nil
            }
        }
    }

    @ViewBuilder
    private var headerBar: some View {
        if #available(iOS 26.0, *) {
            headerBarContent
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background {
                    Color.clear
                        .glassEffect(.clear, in: Rectangle())
                        .opacity(0.72)
                        .allowsHitTesting(false)
                        .ignoresSafeArea(.container, edges: .top)
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: HeaderHeightPreferenceKey.self, value: proxy.size.height)
                    }
                }
                .onPreferenceChange(HeaderHeightPreferenceKey.self) { height in
                    guard height > 0, abs(height - modernHeaderHeight) > 0.5 else { return }
                    modernHeaderHeight = height
                }
                .overlay(alignment: .bottom) {
                    preventSleepFeedbackOverlay
                        .offset(y: 32)
                }
        } else {
            headerBarContent
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(theme.background)
                .overlay(
                    Rectangle()
                        .fill(theme.border)
                        .frame(height: 2),
                    alignment: .bottom
                )
                .overlay(alignment: .bottom) {
                    preventSleepFeedbackOverlay
                        .offset(y: 32)
                }
        }
    }

    @ViewBuilder
    private var preventSleepFeedbackOverlay: some View {
        if let preventSleepFeedbackText {
            HStack(spacing: 7) {
                if pendingPreventSleepTarget != nil {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: preventSleepFeedbackIsWarning
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle.fill")
                        .foregroundColor(preventSleepFeedbackIsWarning ? .orange : .green)
                }

                Text(preventSleepFeedbackText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: Color.black.opacity(0.14), radius: 8, y: 3)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .allowsHitTesting(false)
        }
    }

    private var headerBarContent: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("∞")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(theme.logo)
                    .frame(minWidth: 30, minHeight: 34, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showProjectMenu = true
                    }
                    .onLongPressGesture(minimumDuration: 0.45) {
                        guard !webSocketManager.quotaProviders.isEmpty else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        showQuotaSheet = true
                    }

                Button(action: { showProjectMenu = true }) {
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
                .buttonStyle(.plain)
            }
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
                    systemName: webSocketManager.notificationsEnabled ? "bell.fill" : "bell.slash",
                    theme: theme,
                    action: { toggleNotificationsFromUser() }
                )

                CircleIconButton(
                    systemName: webSocketManager.preventSleepEnabled
                        ? "cup.and.saucer.fill"
                        : "cup.and.saucer",
                    theme: theme,
                    action: { handlePreventSleepToggle() }
                )
                .accessibilityLabel(
                    webSocketManager.preventSleepEnabled
                        ? "合盖运行已开启，点按关闭"
                        : "合盖运行已关闭，点按开启"
                )

                CircleIconButton(
                    systemName: isDarkMode ? "sun.max.fill" : "moon.fill",
                    theme: theme,
                    action: { isDarkMode.toggle() }
                )

                CircleIconButton(
                    systemName: "plus",
                    theme: theme,
                    action: { openDesktopCodexNewChat() },
                    longPressMenuTitle: "选择默认路径",
                    longPressSystemImage: "folder",
                    longPressAction: { showCodexDefaultPathSelector = true }
                )

                Button(action: { handleConnectionStatusTap() }) {
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
                .contextMenu {
                    Button("恢复连接") {
                        restartTunnel()
                    }
                    Button("切到 Tailscale") {
                        if !tryReconnectUsingCachedTailscale(reason: "manual_status_menu") {
                            webSocketManager.addMessage("没有可用的 Tailscale 通道")
                        }
                    }
                    Button("切到公网") {
                        switchToPublicTunnelFromMenu()
                    }
                    Button("Relay 设置") {
                        showRelaySettings = true
                    }
                    Button("解除配对", role: .destructive) {
                        showUnpairConfirmation = true
                    }
                }
            }
            .layoutPriority(1)
        }
    }

    private var quotaSheet: some View {
        ScrollView {
            quotaSection
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
        }
        .background(theme.background.ignoresSafeArea())
    }

    private var quotaSheetDetents: Set<PresentationDetent> {
        [.height(quotaSheetPreferredHeight), .medium]
    }

    private var quotaSheetPreferredHeight: CGFloat {
        let providerCount = max(webSocketManager.quotaProviders.count, 1)
        let contentHeight = 132 + CGFloat(providerCount) * 120
        return min(max(contentHeight, 252), 520)
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("额度")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(theme.text)

                Spacer()

                Text(webSocketManager.quotaStatusLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(theme.background)
                    .cornerRadius(999)
                    .overlay(
                        Capsule()
                            .stroke(theme.border, lineWidth: 1)
                    )
            }

            ForEach(webSocketManager.quotaProviders) { provider in
                quotaProviderRow(provider)
            }
        }
        .padding(12)
        .background(theme.card)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func quotaProviderRow(_ provider: UsageQuotaProvider) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                quotaProviderIcon(provider)

                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(theme.text)
                    if !provider.summary.isEmpty {
                        Text(provider.summary)
                            .font(.system(size: 11))
                            .foregroundColor(theme.textSecondary)
                    }
                }

                Spacer()

                if let updatedAt = provider.updatedAt {
                    Text(updatedAt)
                        .font(.system(size: 11))
                        .foregroundColor(theme.textSecondary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(provider.metrics) { metric in
                    quotaMetricView(metric)
                }
            }
        }
        .padding(10)
        .background(theme.backgroundSecondary)
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func quotaProviderIcon(_ provider: UsageQuotaProvider) -> some View {
        if isCodexQuotaProvider(provider) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(theme.border, lineWidth: 1)
                    )

                Image("AIProviderCodex")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 19, height: 19)
            }
            .frame(width: 30, height: 30)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(theme.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(theme.border, lineWidth: 1)
                    )
                Text(String(provider.name.prefix(1)))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.text)
            }
            .frame(width: 30, height: 30)
        }
    }

    private func isCodexQuotaProvider(_ provider: UsageQuotaProvider) -> Bool {
        let searchableText = [
            provider.id,
            provider.name,
            provider.iconUrl ?? "",
            provider.summary
        ]
            .joined(separator: " ")
            .lowercased()

        return searchableText.contains("codex")
            || searchableText.contains("openai")
            || searchableText.contains("gpt")
    }

    private func quotaMetricView(_ metric: UsageQuotaMetric) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(metric.label)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(metric.remaining)%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(theme.text)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.border.opacity(0.55))
                    Capsule()
                        .fill(theme.text.opacity(0.86))
                        .frame(width: max(4, proxy.size.width * CGFloat(metric.remaining) / 100))
                }
            }
            .frame(height: 5)

            if let resetLabel = metric.resetLabel {
                Text(resetLabel)
                    .font(.system(size: 10))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func messageCard(messageText: String, browserAiResponse: String?) -> some View {
        let quoteContent = browserAiResponse?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? browserAiResponse!
            : messageText

        return VStack(alignment: .leading, spacing: 12) {
            MarkdownView(
                text: messageText,
                theme: theme,
                cacheKey: "request:\(currentRequest?.requestId ?? "no-request"):message",
                themeKey: isDarkMode ? "dark" : "light",
                onImageTap: { url in
                    zoomedImageURL = url
                },
                onQuoteSelection: { selectedText in
                    appendSelectedQuote(selectedText)
                },
                onSearchSelection: { selectedText in
                    searchSelectedText(selectedText)
                }
            )
            .equatable()

            if let browserAiResponse,
               !browserAiResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                    .background(theme.border)

                MarkdownView(
                    text: browserAiResponse,
                    theme: theme,
                    cacheKey: "request:\(currentRequest?.requestId ?? "no-request"):browser-response",
                    themeKey: isDarkMode ? "dark" : "light",
                    onImageTap: { url in
                        zoomedImageURL = url
                    },
                    onQuoteSelection: { selectedText in
                        appendSelectedQuote(selectedText)
                    },
                    onSearchSelection: { selectedText in
                        searchSelectedText(selectedText)
                    }
                )
                .equatable()
            }

            if isFocusedRouteLoadFailure && focusedRouteMessage == nil {
                routeRecoveryActions
            }

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
                        title: "路径",
                        systemImage: "folder.badge.plus",
                        theme: theme,
                        action: { showFileSelector = true }
                    )

                    BridgeActionButton(
                        title: "复制原文",
                        systemImage: "doc.on.doc",
                        theme: theme,
                        action: { UIPasteboard.general.string = preprocessQuoteContent(quoteContent) }
                    )

                    BridgeActionButton(
                        title: "引用原文",
                        systemImage: "text.quote",
                        theme: theme,
                        action: { appendSelectedQuote(preprocessQuoteContent(quoteContent)) }
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
            Button(action: { requestSyncForCurrentRoute() }) {
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

            if let suggestion = activeShortcutSuggestion {
                Button(action: { acceptShortcutSuggestion(suggestion) }) {
                    HStack(spacing: 8) {
                        Text("补全")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(theme.textSecondary)
                        Text(suggestion.key)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(theme.accent)
                        Text(suggestion.description)
                            .font(.system(size: 12))
                            .foregroundColor(theme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(theme.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(theme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            BridgeTextEditor(
                text: $userInput,
                selection: $textSelection,
                isFocused: $isInputFocused,
                isDropTargeted: $isInputDropTargeted,
                placeholder: inputPlaceholder,
                ghostText: activeShortcutGhostText,
                theme: theme,
                onPasteImage: appendImage,
                onAcceptGhostSuggestion: {
                    guard activeShortcutGhostText != nil,
                          let suggestion = activeShortcutSuggestion else {
                        return false
                    }
                    acceptShortcutSuggestion(suggestion)
                    return true
                },
                onDrop: handleImageDrop
            )
            .onChange(of: speechManager.transcript) { newValue in
                if speechManager.isRecording, !newValue.isEmpty {
                    applySpeechTranscript(newValue, shouldTrain: false)
                }
            }
            .onChange(of: speechManager.finalTranscriptToken) { _ in
                if speechManager.isRecording
                    && !suppressPendingSpeechFinalCommit
                    && speechManager.finalTranscript.isEmpty {
                    return
                }
                if suppressPendingSpeechFinalCommit {
                    clearSpeechDraftState()
                    suppressPendingSpeechFinalCommit = false
                    return
                }
                let finalTranscript = speechManager.finalTranscript
                if !finalTranscript.isEmpty {
                    applySpeechTranscript(finalTranscript, shouldTrain: speechManager.finalTranscriptShouldTrain)
                }
                clearSpeechDraftState(resetSuppression: false)
            }
            .onChange(of: speechManager.isRecording) { isRecording in
                lastAutoTrainedPhrase = ""
                if isRecording {
                    suppressPendingSpeechFinalCommit = false
                    speechDraftSession.begin(at: textSelection)
                }
            }
            .onChange(of: textSelection) { newSelection in
                guard !isApplyingSpeechUpdate else { return }

                if speechManager.isRecording {
                    guard newSelection != speechDraftSession.recordingSelectionAnchor else { return }
                    shouldAutoResumeRecording = true
                    suppressPendingSpeechFinalCommit = true
                    speechManager.stopRecording(discardPendingResult: true)
                    scheduleSpeechRestart()
                } else if shouldAutoResumeRecording {
                    scheduleSpeechRestart()
                }
            }

            if let speechStatusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                    Text(speechStatusMessage)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(theme.error)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.error.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.error.opacity(0.25), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if codexLiveManager.shouldShowStatus {
                HStack(spacing: 8) {
                    Image(systemName: codexLiveManager.isActive ? "waveform.circle.fill" : "exclamationmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                    Text(codexLiveManager.statusText)
                        .font(.system(size: 12))
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundColor(codexLiveManager.isActive ? theme.accent : theme.error)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((codexLiveManager.isActive ? theme.accent : theme.error).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke((codexLiveManager.isActive ? theme.accent : theme.error).opacity(0.25), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let candidate = pendingSpeechCorrectionCandidate, !candidate.isExpired {
                speechCorrectionConfirmationBar(candidate)
            }

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
                                ZStack {
                                    PromptChip(
                                        title: prompt.name,
                                        theme: theme,
                                        isDragging: promptReorderSession.sourceID == prompt.id,
                                        action: {
                                            guard promptReorderSession.suppressedTapID != prompt.id,
                                                  !promptReorderSession.isActive else {
                                                return
                                            }
                                            appendPromptContent(prompt.content)
                                        }
                                    )
                                    .overlay {
                                        quickPromptInsertionIndicator(for: prompt.id)
                                    }
                                    .offset(quickPromptReorderOffset(for: prompt.id))
                                    .zIndex(promptReorderSession.sourceID == prompt.id ? 10 : 0)
                                    .animation(
                                        .interactiveSpring(response: 0.24, dampingFraction: 0.82),
                                        value: promptReorderSession.targetID
                                    )
                                }
                                .reportStableReorderFrame(id: prompt.id)
                                .zIndex(promptReorderSession.sourceID == prompt.id ? 10 : 0)
                            }
                        }
                        .padding(.vertical, 4)
                        .background(
                            LongPressReorderGestureBridge(
                                isEnabled: !normalPromptItems.isEmpty,
                                onBegan: beginQuickPromptReorder,
                                onChanged: updateQuickPromptReorder,
                                onEnded: finishQuickPromptReorder
                            )
                        )
                    }
                    .scrollDisabled(promptReorderSession.isActive)
                    .onPreferenceChange(StableReorderItemFramesPreferenceKey.self) { frames in
                        promptReorderFrames = frames
                    }
                }

                if enableContextAppend && !conditionalPrompts.isEmpty {
                    SectionTitle(text: "上下文追加", theme: theme)

                    VStack(spacing: 8) {
                        ForEach(conditionalPrompts) { prompt in
                            ConditionalToggleRow(
                                prompt: prompt,
                                webSocketManager: webSocketManager,
                                projectPath: currentRequest?.projectPath,
                                requestId: currentRequest?.requestId,
                                theme: theme
                            )
                        }
                    }
                }
            }
        }
    }

    private func speechCorrectionConfirmationBar(_ candidate: SpeechCorrectionLearningCandidate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("记住语音纠错？")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.text)
                    Text("\(candidate.observedText) -> \(candidate.intendedText)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                Button(action: { dismissSpeechCorrectionCandidate() }) {
                    Label("忽略", systemImage: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(theme.textSecondary)

                Spacer(minLength: 8)

                Button(action: { confirmSpeechCorrectionCandidate(candidate) }) {
                    Label("记住", systemImage: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(theme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.accent.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private var speechStatusMessage: String? {
        if let error = speechManager.inputState.userVisibleError, !error.isEmpty {
            return visibleSpeechStatusMessage(error)
        }

        switch speechManager.inputState.phase {
        case .requestingPermission:
            return "正在请求语音和麦克风权限"
        case .starting:
            return "正在启动语音输入"
        case .failed(let message):
            return visibleSpeechStatusMessage(message)
        default:
            return nil
        }
    }

    private func visibleSpeechStatusMessage(_ message: String) -> String? {
        if message.hasPrefix("语音识别失败") {
            return nil
        }
        return message
    }

    private func applySpeechTranscript(_ transcript: String, shouldTrain: Bool) {
        restoreSpeechInputTargetIfNeeded()

        let observedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedTranscript = transcript
        if shouldTrain {
            if let correctionMatch = SpeechCorrectionMemoryStore.correctionMatch(
                transcript: resolvedTranscript,
                in: speechCorrectionMemoryStore,
                contextTerms: speechCorrectionContextTerms()
            ) {
                speechCorrectionMemoryStore = SpeechCorrectionMemoryStore.recordHit(
                    for: correctionMatch.entry.id,
                    in: speechCorrectionMemoryStore
                )
                markSpeechCorrectionMemoryNeedsSync(reason: "correction_hit")
                resolvedTranscript = correctionMatch.correctedText
            }

            if let matchedEntry = SpeechMuscleMemoryStore.candidate(
                transcript: resolvedTranscript,
                in: speechMuscleMemoryStore
            ) {
                let normalizedPhrase = SpeechMuscleMemoryStore.normalize(matchedEntry.spokenPhrase)
                if !normalizedPhrase.isEmpty, lastAutoTrainedPhrase != normalizedPhrase {
                    let updatedStore = SpeechMuscleMemoryStore.bumpTraining(
                        for: matchedEntry.id,
                        in: speechMuscleMemoryStore
                    )
                    if updatedStore != speechMuscleMemoryStore {
                        speechMuscleMemoryStore = updatedStore
                        markSpeechMuscleMemoryNeedsSync(reason: "native_auto_training")
                    }
                    lastAutoTrainedPhrase = normalizedPhrase
                }
            }

            if let subEntry = SpeechMuscleMemoryStore.substitutionCandidate(
                transcript: resolvedTranscript,
                in: speechMuscleMemoryStore
               ),
               let refreshedEntry = SpeechMuscleMemoryStore.entry(
                id: subEntry.id,
                from: speechMuscleMemoryStore
               ),
               refreshedEntry.trainingCount >= SpeechMuscleMemoryStore.activationThreshold {
                resolvedTranscript = refreshedEntry.outputText
            }
        }
        resolvedTranscript = VoiceSemanticResolver().refineDictationText(
            resolvedTranscript,
            context: VoiceSemanticContext(
                rawTranscript: resolvedTranscript,
                currentRequestMessage: currentRequest?.message,
                predefinedOptions: currentRequest?.predefinedOptions ?? [],
                selectedOptions: orderedSelectedOptions,
                currentInput: userInput,
                projectPath: currentRequest?.projectPath,
                mode: .reply
            )
        )
        let currentText = userInput as NSString
        let draftUpdate = speechDraftSession.apply(
            transcript: resolvedTranscript,
            shouldTrain: shouldTrain,
            currentText: currentText,
            selection: textSelection
        )

        isApplyingSpeechUpdate = true
        userInput = draftUpdate.updatedText
        textSelection = draftUpdate.selection
        if shouldTrain {
            rememberSpeechCorrectionObservation(observed: observedTranscript, resolved: resolvedTranscript)
            rememberSpeechVocabulary(from: resolvedTranscript)
#if DEBUG
            print("[SpeechLatency] input-applied t_ms=\(String(format: "%.1f", CACurrentMediaTime() * 1_000))")
#endif
        }
        lastVoiceSemanticRawTranscript = observedTranscript
        lastVoiceSemanticResolvedTranscript = resolvedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        DispatchQueue.main.async {
            isApplyingSpeechUpdate = false
        }
    }

    private func rememberSpeechCorrectionObservation(observed: String, resolved: String) {
        let trimmedObserved = observed.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedResolved = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedObserved.isEmpty, !trimmedResolved.isEmpty else {
            lastSpeechCorrectionObservation = nil
            return
        }

        lastSpeechCorrectionObservation = SpeechCorrectionObservation(
            observedText: trimmedObserved,
            resolvedText: trimmedResolved,
            createdAt: Date()
        )
    }

    private func learnSpeechCorrectionIfNeeded(finalText: String, reason: String) {
        guard let observation = lastSpeechCorrectionObservation else { return }
        defer { lastSpeechCorrectionObservation = nil }

        guard Date().timeIntervalSince(observation.createdAt) <= 10 * 60 else { return }
        guard let candidate = SpeechCorrectionMemoryStore.learningCandidate(
            observedText: observation.observedText,
            resolvedText: observation.resolvedText,
            intendedText: finalText,
            contextTerms: speechCorrectionContextTerms(),
            source: "ios_\(reason)_manual_edit"
        ) else {
            return
        }

        pendingSpeechCorrectionCandidate = candidate
        print("[SpeechCorrection] pending observed=\(candidate.observedText) intended=\(candidate.intendedText) reason=\(reason)")
    }

    private func confirmSpeechCorrectionCandidate(_ candidate: SpeechCorrectionLearningCandidate) {
        guard pendingSpeechCorrectionCandidate?.id == candidate.id else { return }
        guard !candidate.isExpired else {
            pendingSpeechCorrectionCandidate = nil
            return
        }

        let updatedStore = SpeechCorrectionMemoryStore.upsertCorrection(
            observedText: candidate.observedText,
            intendedText: candidate.intendedText,
            contextTerms: candidate.contextTerms,
            source: "\(candidate.source)_confirmed",
            in: speechCorrectionMemoryStore
        )
        if updatedStore != speechCorrectionMemoryStore {
            speechCorrectionMemoryStore = updatedStore
            markSpeechCorrectionMemoryNeedsSync(reason: "correction_confirmed")
            print("[SpeechCorrection] confirmed observed=\(candidate.observedText) intended=\(candidate.intendedText)")
        }
        pendingSpeechCorrectionCandidate = nil
    }

    private func dismissSpeechCorrectionCandidate() {
        guard let candidate = pendingSpeechCorrectionCandidate else { return }
        defer { pendingSpeechCorrectionCandidate = nil }
        guard !candidate.isExpired else { return }

        let updatedStore = SpeechCorrectionMemoryStore.recordRejection(
            observedText: candidate.observedText,
            intendedText: candidate.intendedText,
            contextTerms: candidate.contextTerms,
            source: "\(candidate.source)_rejected",
            in: speechCorrectionMemoryStore
        )
        if updatedStore != speechCorrectionMemoryStore {
            speechCorrectionMemoryStore = updatedStore
            markSpeechCorrectionMemoryNeedsSync(reason: "correction_rejected")
            print("[SpeechCorrection] rejected observed=\(candidate.observedText) intended=\(candidate.intendedText)")
        }
    }

#if DEBUG
    private func applyDebugSpeechCorrectionSeedsIfNeeded() {
        guard let rawSeeds = ProcessInfo.processInfo.environment["ITERATE_DEBUG_SPEECH_CORRECTION_SEEDS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawSeeds.isEmpty else {
            return
        }

        let updatedStore = SpeechCorrectionMemoryStore.applyingDebugSeeds(
            from: rawSeeds,
            in: speechCorrectionMemoryStore
        )
        guard updatedStore != speechCorrectionMemoryStore else {
            print("[SpeechCorrection] debug seed skipped or already current")
            return
        }

        speechCorrectionMemoryStore = updatedStore
        markSpeechCorrectionMemoryNeedsSync(reason: "debug_seed")
        print("[SpeechCorrection] applied debug seed")
    }
#endif

    private func clearSpeechDraftState(resetSuppression: Bool = true) {
        speechDraftSession.reset()
        activeSpeechInputTarget = nil
        if resetSuppression {
            suppressPendingSpeechFinalCommit = false
        }
    }

    private func prepareManualSpeechInteraction() {
        pendingSpeechRestart?.cancel()
        pendingSpeechRestart = nil
        shouldAutoResumeRecording = false
    }

    private func handleVoiceInputAction() {
        prepareManualSpeechInteraction()
        if speechManager.isRecording {
            speechManager.stopRecording()
        } else {
            startSpeechRecording()
        }
    }

    private func handleVoiceDockTap() {
        if codexLiveManager.isActive {
            codexLiveManager.toggleMicrophoneMuted()
        } else {
            handleVoiceInputAction()
        }
    }

    private func handleCodexLiveLongPress() {
        prepareManualSpeechInteraction()
        if speechManager.isRecording {
            speechManager.stopRecording()
        }
        if codexLiveManager.isActive {
            codexLiveManager.stop()
        } else {
            guard let projectPath = targetProjectPathForCodexZhi() else {
                webSocketManager.addMessage("请先选择 GPT-Live 要操作的 Mac 项目")
                return
            }
            codexLiveManager.start(serverURL: serverURL, projectPath: projectPath)
        }
    }

    private func scheduleSpeechRestart() {
        pendingSpeechRestart?.cancel()

        let workItem = DispatchWorkItem {
            guard shouldAutoResumeRecording else { return }
            guard !speechManager.isRecording, speechManager.isAuthorized else { return }
            pendingSpeechRestart = nil
            startSpeechRecording()
        }

        pendingSpeechRestart = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func startSpeechRecording() {
        voiceSemanticInputBeforeRecording = userInput
        lastVoiceSemanticRawTranscript = ""
        lastVoiceSemanticResolvedTranscript = ""
        activeSpeechInputTarget = captureSpeechInputTarget()
        let contextualStrings = speechContextHints()
#if DEBUG
        print("[Speech] contextualStrings=\(contextualStrings)")
#endif
        speechManager.startRecording(contextualStrings: contextualStrings)
    }

    private func markSpeechMuscleMemoryNeedsSync(reason: String) {
        speechMuscleMemoryPendingSync = true
        pushSpeechMuscleMemoryToBridgeIfNeeded(reason: reason)
    }

    private func pushSpeechMuscleMemoryToBridgeIfNeeded(reason: String) {
        guard !speechMuscleMemoryPushInFlight else { return }

        let currentHash = SpeechMuscleMemoryStore.fingerprint(speechMuscleMemoryStore)
        guard speechMuscleMemoryPendingSync || currentHash != speechMuscleMemoryLastPushedHash else {
            return
        }

        let localEntries = SpeechMuscleMemoryStore.decode(speechMuscleMemoryStore)
        let deletedEntryIDs = SpeechMuscleMemoryStore.decodeDeletedEntryIDs(speechMuscleMemoryDeletedEntryIDs)
        guard !localEntries.isEmpty || !deletedEntryIDs.isEmpty else {
            return
        }

        speechMuscleMemoryPushInFlight = true
        SpeechMuscleMemoryBridgeSync.mergeAndPush(
            localEntries: localEntries,
            deletedEntryIDs: deletedEntryIDs,
            reason: reason
        ) { didSucceed, mergedEntries in
            speechMuscleMemoryPushInFlight = false
            guard didSucceed else {
                speechMuscleMemoryPendingSync = true
                return
            }

            let mergedRaw = SpeechMuscleMemoryStore.encode(mergedEntries)
            speechMuscleMemoryStore = mergedRaw
            speechMuscleMemoryLastPushedHash = SpeechMuscleMemoryStore.fingerprint(mergedRaw)
            speechMuscleMemoryDeletedEntryIDs = "[]"
            speechMuscleMemoryPendingSync = false
        }
    }

    private func markSpeechCorrectionMemoryNeedsSync(reason: String) {
        speechCorrectionMemoryPendingSync = true
        pushSpeechCorrectionMemoryToBridgeIfNeeded(reason: reason)
    }

    private func syncSpeechCorrectionMemoryFromBridge(reason: String) {
        guard !speechCorrectionMemoryPushInFlight else { return }

        SpeechCorrectionMemoryBridgeSync.fetchRemoteEntriesWithStatus(reason: reason) { didFetch, remoteEntries in
            guard didFetch else { return }

            let localEntries = SpeechCorrectionMemoryStore.decode(speechCorrectionMemoryStore)
            let mergedEntries = SpeechCorrectionMemoryStore.merge(
                local: localEntries,
                remote: remoteEntries
            )
            let mergedRaw = SpeechCorrectionMemoryStore.encode(mergedEntries)
            let remoteRaw = SpeechCorrectionMemoryStore.encode(remoteEntries)

            if mergedRaw != speechCorrectionMemoryStore {
                speechCorrectionMemoryStore = mergedRaw
            }
            speechCorrectionMemoryLastPushedHash = SpeechCorrectionMemoryStore.fingerprint(mergedRaw)

            if speechCorrectionMemoryPendingSync || (!localEntries.isEmpty && mergedRaw != remoteRaw) {
                speechCorrectionMemoryPendingSync = true
                pushSpeechCorrectionMemoryToBridgeIfNeeded(reason: "\(reason)_merged")
            }
        }
    }

    private func pushSpeechCorrectionMemoryToBridgeIfNeeded(reason: String) {
        guard !speechCorrectionMemoryPushInFlight else { return }

        let currentHash = SpeechCorrectionMemoryStore.fingerprint(speechCorrectionMemoryStore)
        guard speechCorrectionMemoryPendingSync || currentHash != speechCorrectionMemoryLastPushedHash else {
            return
        }

        let localEntries = SpeechCorrectionMemoryStore.decode(speechCorrectionMemoryStore)
        guard !localEntries.isEmpty else {
            return
        }

        speechCorrectionMemoryPushInFlight = true
        SpeechCorrectionMemoryBridgeSync.mergeAndPush(
            localEntries: localEntries,
            reason: reason
        ) { didSucceed, mergedEntries in
            speechCorrectionMemoryPushInFlight = false
            guard didSucceed else {
                speechCorrectionMemoryPendingSync = true
                return
            }

            let mergedRaw = SpeechCorrectionMemoryStore.encode(mergedEntries)
            speechCorrectionMemoryStore = mergedRaw
            speechCorrectionMemoryLastPushedHash = SpeechCorrectionMemoryStore.fingerprint(mergedRaw)
            speechCorrectionMemoryPendingSync = false
        }
    }

    private func speechContextHints() -> [String] {
        SpeechContextProvider.hints(
            requestMessage: currentRequest?.message ?? "",
            userInput: userInput,
            muscleMemoryRawValue: speechMuscleMemoryStore,
            rememberedVocabularyRawValue: speechVocabularyStore,
            correctionTerms: SpeechCorrectionMemoryStore.contextualTerms(from: speechCorrectionMemoryStore),
            shortcutTerms: mergedShortcutSuggestions.map(\.key),
            requestTerms: speechRequestTerms()
        )
    }

    private func speechRequestTerms() -> [String] {
        let requestId = currentRequest?.requestId
        let message = currentRequest?.message ?? ""
        if cachedSpeechRequestId == requestId,
           cachedSpeechRequestMessage == message {
            return cachedSpeechRequestTerms
        }

        let startedAt = CACurrentMediaTime()
        let terms = SpeechContextProvider.extractTerms(from: message)
        cachedSpeechRequestId = requestId
        cachedSpeechRequestMessage = message
        cachedSpeechRequestTerms = terms
#if DEBUG
        print(
            "[SpeechPerf] request-terms request_id=\(requestId ?? "none") chars=\(message.count) " +
            "terms=\(terms.count) elapsed_ms=\(String(format: "%.1f", (CACurrentMediaTime() - startedAt) * 1000))"
        )
#endif
        return terms
    }

    private func speechCorrectionContextTerms() -> [String] {
        mergedSpeechTerms(
            SpeechMuscleMemoryStore.contextualTerms(from: speechMuscleMemoryStore)
                + speechVocabularyTerms()
                + SpeechContextProvider.extractTerms(from: currentRequest?.message ?? "")
                + SpeechContextProvider.extractTerms(from: userInput)
                + mergedShortcutSuggestions.map(\.key),
            limit: 80
        )
    }

    private func speechVocabularyTerms() -> [String] {
        speechVocabularyStore
            .split(separator: "\n")
            .map(String.init)
    }

    private func mergedSpeechTerms(_ terms: [String], limit: Int = SpeechRecognitionConfig.standard.contextualStringsLimit) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []

        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 48 else { continue }
            let normalized = SpeechCorrectionMemoryStore.normalize(trimmed)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            merged.append(trimmed)
            if merged.count >= limit {
                break
            }
        }

        return merged
    }

    private func rememberSpeechVocabulary(from text: String) {
        let terms = SpeechContextProvider.safeVocabularyTerms(from: text)
        guard !terms.isEmpty else { return }
        applySpeechVocabularyTerms(terms)
        SpeechVocabularyBridgeSync.record(terms: terms, reason: "final_transcript") { didSucceed, remoteTerms in
            guard didSucceed else { return }
            replaceSpeechVocabularyTerms(remoteTerms)
        }
    }

    private func syncSpeechVocabularyFromBridge(reason: String) {
        // Mac is authoritative; legacy iOS cache terms must never be uploaded on startup.
        SpeechVocabularyBridgeSync.merge(localTerms: [], reason: reason) {
            didSucceed,
            remoteTerms in
            guard didSucceed else { return }
            replaceSpeechVocabularyTerms(remoteTerms)
        }
    }

    private func applySpeechVocabularyTerms(_ terms: [String]) {
        speechVocabularyStore = mergedSpeechTerms(
            terms + speechVocabularyTerms(),
            limit: 60
        ).joined(separator: "\n")
    }

    private func replaceSpeechVocabularyTerms(_ terms: [String]) {
        speechVocabularyStore = mergedSpeechTerms(terms, limit: 60).joined(separator: "\n")
    }

    @ViewBuilder
    private var requestPage: some View {
        if #available(iOS 26.0, *) {
            if currentMessage != nil {
                requestWorkspace(
                    bottomContentPadding: modernFooterScrollPadding,
                    topContentPadding: modernHeaderScrollPadding,
                    timelineTopInset: modernHeaderScrollPadding,
                    timelineBottomInset: modernFooterScrollPadding
                )
                    .overlay(alignment: .bottom) {
                        modernVoiceFooter
                    }
            } else {
                requestWorkspace(
                    bottomContentPadding: 16,
                    topContentPadding: modernHeaderScrollPadding,
                    timelineTopInset: modernHeaderScrollPadding
                )
            }
        } else {
            if currentMessage != nil {
                VStack(spacing: 0) {
                    requestWorkspace(bottomContentPadding: VoiceHalfCircleDockMetrics.outerHeight + 16)
                    footerBar
                }
            } else {
                requestWorkspace(bottomContentPadding: 16)
            }
        }
    }

    private func requestWorkspace(
        bottomContentPadding: CGFloat,
        topContentPadding: CGFloat = 16,
        timelineTopInset: CGFloat = 0,
        timelineBottomInset: CGFloat = 0
    ) -> some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 8) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let messageText = renderableRequestMessage(currentRequest) {
                            messageCard(
                                messageText: messageText,
                                browserAiResponse: currentRequest?.browserAiResponse
                            )
                            .id(
                                "request-card:\(currentRequest?.requestId ?? "no-request"):\(manualRouteRefreshGeneration)"
                            )
                        } else {
                            emptyState
                        }
                        // 无 MCP 消息时也保留输入框 + 语音，便于肌肉记忆（如「派发」→ pai）随时可用
                        inputSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, topContentPadding)
                    .padding(.bottom, currentMessage == nil ? 16 : bottomContentPadding)
                }
                .refreshable {
                    await refreshCurrentRouteManually()
                }
                .scrollDismissesKeyboard(.immediately)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if !visibleTimelineNodes.isEmpty, isTimelineRailExpanded {
                    timelineDotRail(
                        availableHeight: geo.size.height,
                        topInset: timelineTopInset,
                        bottomInset: timelineBottomInset
                    )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background(timelineEdgePanInstaller)
            .animation(.easeInOut(duration: 0.2), value: isTimelineRailExpanded)
            .onChange(of: visibleTimelineNodes.isEmpty) { isEmpty in
                if isEmpty {
                    isTimelineRailExpanded = false
                    timelinePreviewNode = nil
                }
            }
        }
    }

    private var modernFooterScrollPadding: CGFloat {
        max(modernVoiceFooterHeight, VoiceFooterBarLayout.modernFooterFallbackHeight) + 16
    }

    private var modernHeaderScrollPadding: CGFloat {
        max(modernHeaderHeight, 58) + 16
    }

    @available(iOS 26.0, *)
    private var modernVoiceFooter: some View {
        VStack(spacing: 0) {
            VoiceHalfCircleDock(
                isRecording: speechManager.isRecording,
                isLiveActive: codexLiveManager.isActive,
                isLiveConnected: codexLiveManager.isConnected,
                isLiveMuted: codexLiveManager.isMicrophoneMuted,
                meter: speechManager.meter,
                theme: theme,
                iterateAppearanceIsLight: !isDarkMode,
                usesIntegratedFooterGlass: true,
                onLongPress: handleCodexLiveLongPress,
                action: handleVoiceDockTap
            )
            footerActionRow
        }
        .frame(maxWidth: .infinity)
        .background {
            Color.clear
                .glassEffect(.clear, in: VoiceFooterGlassShape())
                .opacity(0.72)
                .allowsHitTesting(false)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: VoiceFooterHeightPreferenceKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(VoiceFooterHeightPreferenceKey.self) { height in
            guard height > 0, abs(height - modernVoiceFooterHeight) > 0.5 else { return }
            modernVoiceFooterHeight = height
        }
    }

    private var footerBar: some View {
        let layout = VoiceFooterBarLayout.self
        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: layout.dividerTopFromFooterTop)
                Color.clear
                    .frame(height: layout.dividerHeight)
                    .frame(maxWidth: .infinity)
                footerActionRow
            }
            .frame(maxWidth: .infinity)
            .background(theme.backgroundSecondary)

            HStack {
                Spacer()
                VoiceHalfCircleDock(
                    isRecording: speechManager.isRecording,
                    isLiveActive: codexLiveManager.isActive,
                    isLiveConnected: codexLiveManager.isConnected,
                    isLiveMuted: codexLiveManager.isMicrophoneMuted,
                    meter: speechManager.meter,
                    theme: theme,
                    iterateAppearanceIsLight: !isDarkMode,
                    onLongPress: handleCodexLiveLongPress,
                    action: handleVoiceDockTap
                )
                .offset(y: layout.dockVerticalOffset)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .background(theme.backgroundSecondary)
    }

    private var footerActionRow: some View {
        HStack(spacing: 12) {
            BridgeSecondaryButton(title: "∞", theme: theme, action: handleGoal)
            BridgePrimaryButton(
                title: "确认",
                theme: theme,
                action: handleSubmit
            )
        }
        .padding(16)
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
        guard !promptReorderSession.isActive else { return }
        let prompts = webSocketManager.customPrompts?.prompts ?? []
        normalPromptItems = prompts.filter { $0.type == nil || $0.type == "normal" }
    }

    private func quickPromptReorderOffset(for promptID: String) -> CGSize {
        stableReorderOffset(
            for: promptID,
            orderedIDs: normalPromptItems.map(\.id),
            frames: promptReorderFrames,
            session: promptReorderSession,
            axis: .horizontal,
            spacing: 10
        )
    }

    @ViewBuilder
    private func quickPromptInsertionIndicator(for promptID: String) -> some View {
        let ids = normalPromptItems.map(\.id)
        if promptReorderSession.hasCrossedMovementThreshold,
           let sourceID = promptReorderSession.sourceID,
           let targetID = promptReorderSession.targetID,
           sourceID != targetID,
           targetID == promptID,
           let sourceIndex = ids.firstIndex(of: sourceID),
           let targetIndex = ids.firstIndex(of: targetID) {
            HStack(spacing: 0) {
                if sourceIndex > targetIndex {
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 3, height: 24)
                        .shadow(color: theme.accent.opacity(0.35), radius: 3)
                        .offset(x: -5)
                }
                Spacer(minLength: 0)
                if sourceIndex < targetIndex {
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 3, height: 24)
                        .shadow(color: theme.accent.opacity(0.35), radius: 3)
                        .offset(x: 5)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func beginQuickPromptReorder(at location: CGPoint) {
        guard !promptReorderSession.isActive,
              let promptID = normalPromptItems.first(where: { prompt in
                  promptReorderFrames[prompt.id]?.contains(location) == true
              })?.id else {
            return
        }

        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.prepare()
        feedback.impactOccurred(intensity: 0.85)
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.82)) {
            promptReorderSession.begin(id: promptID, at: location)
        }
    }

    private func updateQuickPromptReorder(at location: CGPoint) {
        guard promptReorderSession.isActive else { return }
        let didBeginMoving = promptReorderSession.update(to: location, movementThreshold: 6)
        if didBeginMoving {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        guard promptReorderSession.hasCrossedMovementThreshold else { return }

        let targetID = stableReorderTargetID(
            at: location,
            orderedIDs: normalPromptItems.map(\.id),
            frames: promptReorderFrames,
            axis: .horizontal,
            fallback: promptReorderSession.targetID
        )
        guard let targetID, targetID != promptReorderSession.targetID else { return }

        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.82)) {
            promptReorderSession.targetID = targetID
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func finishQuickPromptReorder(cancelled: Bool) {
        guard let sourceID = promptReorderSession.sourceID else { return }
        let targetID = promptReorderSession.targetID ?? sourceID
        let shouldCommit = !cancelled
            && promptReorderSession.hasCrossedMovementThreshold
            && sourceID != targetID

        withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.84)) {
            if shouldCommit,
               let fromIndex = normalPromptItems.firstIndex(where: { $0.id == sourceID }),
               let toIndex = normalPromptItems.firstIndex(where: { $0.id == targetID }) {
                normalPromptItems.move(
                    fromOffsets: IndexSet(integer: fromIndex),
                    toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                )
            }
            promptReorderSession.reset(keepTapSuppression: true)
        }

        if shouldCommit {
            persistPromptOrderIfNeeded()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        clearQuickPromptTapSuppression(for: sourceID)
    }

    private func clearQuickPromptTapSuppression(for promptID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard !promptReorderSession.isActive,
                  promptReorderSession.suppressedTapID == promptID else {
                return
            }
            promptReorderSession.suppressedTapID = nil
        }
    }

    private func persistPromptOrderIfNeeded() {
        let newPromptIds = normalPromptItems.map { $0.id }
        guard !newPromptIds.isEmpty else { return }

        let currentPromptIds = (webSocketManager.customPrompts?.prompts ?? [])
            .filter { $0.type == nil || $0.type == "normal" }
            .map { $0.id }

        guard newPromptIds != currentPromptIds else { return }

        webSocketManager.updateCustomPromptOrder(promptIds: newPromptIds)
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

    private func handleGoal() {
        sendCurrentGoal(allowVoiceSemanticPreview: true)
    }

    private func buildGoalSelectedOptionsContext(goalText: String, selectedOptions: [String]) -> String {
        let missingOptions = selectedOptions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !goalText.contains($0) }

        guard !missingOptions.isEmpty else { return "" }

        return "选中的选项：\n" + missingOptions
            .map { "- \($0)" }
            .joined(separator: "\n")
    }

    private func buildGoalText(goalInput: String, selectedOptions: [String]) -> String {
        let normalizedOptions = selectedOptions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let optionsText = normalizedOptions
            .joined(separator: "\n")
        let primaryText = goalInput.isEmpty ? optionsText : goalInput
        let optionsContext = buildGoalSelectedOptionsContext(
            goalText: primaryText,
            selectedOptions: normalizedOptions
        )

        return [primaryText, optionsContext]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func sendCurrentGoal(allowVoiceSemanticPreview: Bool) {
        speechManager.stopRecording()
        guard currentMessage != nil else {
            webSocketManager.addMessage("当前没有待处理 MCP 请求，目标需要在 zhi 请求中使用")
            return
        }
        let projectPath = currentRequest?.projectPath
        let goalInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goalInput.isEmpty || !orderedSelectedOptions.isEmpty || !selectedImages.isEmpty else {
            webSocketManager.addMessage("请先输入目标、选择选项或上传图片")
            return
        }
        let goalText = buildGoalText(
            goalInput: goalInput,
            selectedOptions: orderedSelectedOptions
        )

        if allowVoiceSemanticPreview,
           presentVoiceSemanticPreviewIfNeeded(source: .goal, finalInput: goalText) {
            return
        }

        learnSpeechCorrectionIfNeeded(finalText: goalText, reason: "goal")
        recordSubmittedGhostSuggestionLearning(from: goalInput)

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
                webSocketManager.requestSync(projectPath: nil, requestId: syncRequestIdHint, reason: "main_page_return")
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
            "goal",
            userInput: goalText,
            selectedOptions: orderedSelectedOptions,
            images: selectedImages,
            projectPath: projectPath,
            requestId: currentRequest?.requestId,
            timelineRouteId: currentRequest?.timelineRouteKey
        )
        resetInputState()
        pushWatchRelayState(reason: "goal")
    }

    private func handleSubmit() {
        if codexLiveManager.isActive {
            codexLiveManager.confirmExecution()
            return
        }
        submitCurrentResponse(allowVoiceSemanticPreview: true)
    }

    private func submitCurrentResponse(allowVoiceSemanticPreview: Bool) {
        suppressPendingSpeechFinalCommit = speechManager.isRecording
        speechManager.stopRecording(discardPendingResult: speechManager.isRecording)
        guard let lastMessage = currentMessage else { return }
        let finalInput = userInput + (enableContextAppend ? generateConditionalContent() : "")
        let hasUserInput = !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasUserInput || !orderedSelectedOptions.isEmpty || !selectedImages.isEmpty else {
            webSocketManager.addMessage("请先输入文字、选择选项或上传图片后再确认")
            return
        }
        if allowVoiceSemanticPreview,
           presentVoiceSemanticPreviewIfNeeded(source: .submit, finalInput: finalInput) {
            return
        }
        learnSpeechCorrectionIfNeeded(finalText: finalInput, reason: "submit")
        recordSubmittedGhostSuggestionLearning(from: userInput)
        webSocketManager.sendResponse(
            text: finalInput,
            images: selectedImages,
            selectedOptions: orderedSelectedOptions,
            forMessage: lastMessage
        )
        resetInputState()
        pushWatchRelayState(reason: "submit")
    }

    private func handleWatchRelayAction(
        action: String,
        userInput: String,
        selectedOptions: [String],
        projectPath: String?,
        requestId: String?
    ) {
        let resolvedProjectPath = projectPath?.isEmpty == false ? projectPath : currentRequest?.projectPath
        let resolvedRequestId = requestId?.isEmpty == false ? requestId : currentRequest?.requestId

        if action == "request_state" {
            pushWatchRelayState(reason: "watch_request_state")
            return
        }
        if action == "request_projects" {
            fetchWatchRelayProjects(reason: "watch_request_projects")
            return
        }
        if action == "switch_project", let targetProjectPath = resolvedProjectPath, !targetProjectPath.isEmpty {
            focusedRequestId = resolvedRequestId
            focusedProjectPath = targetProjectPath
            focusedRoutePreviewMessage = nil
            isManualRouteSelection = true
            webSocketManager.switchProject(to: targetProjectPath, requestId: resolvedRequestId)
            pushWatchRelayState(reason: "watch_switch_project")
            return
        }
        if action == "open_notification" {
            focusedRequestId = resolvedRequestId
            focusedProjectPath = resolvedProjectPath
            focusedRoutePreviewMessage = nil
            isManualRouteSelection = resolvedRequestId != nil || resolvedProjectPath != nil
            if let targetProjectPath = resolvedProjectPath, !targetProjectPath.isEmpty {
                webSocketManager.prepareProjectSwitch(to: targetProjectPath)
            }
            webSocketManager.recoverAndSync(
                projectPath: resolvedProjectPath,
                requestId: resolvedRequestId,
                reason: "watch_notification_click"
            )
            pushWatchRelayState(reason: "watch_notification_click")
            return
        }

        webSocketManager.addMessage("Watch 发送: \(action)")
        webSocketManager.sendAction(
            action,
            userInput: userInput,
            selectedOptions: selectedOptions,
            projectPath: resolvedProjectPath,
            requestId: resolvedRequestId
        )
        pushWatchRelayState(reason: "watch_action_\(action)")
    }

    private func pushWatchRelayState(reason: String) {
        let request = currentRequest
        let projectPath = request?.projectPath ?? focusedProjectPath
        let isWaiting = isCurrentRouteWaitingForReply
        let projectName = projectPath
            .flatMap { URL(fileURLWithPath: $0).lastPathComponent.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent }
            ?? webSocketManager.currentProject
            ?? "iterate"

        watchRelay.updateState(
            status: connectionStatus,
            projectName: projectName,
            message: isWaiting ? "" : (request?.message ?? ""),
            projectPath: projectPath,
            requestId: request?.requestId ?? focusedRequestId,
            options: isWaiting ? [] : (request?.predefinedOptions ?? []),
            isConnected: webSocketManager.isConnected,
            isWaiting: isWaiting,
            reason: reason
        )
    }

    private func fetchWatchRelayProjects(reason: String) {
        guard let request = activeSessionsRequest() else {
            pushWatchRelayPreservedProjects(reason: reason)
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "watch_active_sessions") {
                    self.pushWatchRelayPreservedProjects(reason: reason)
                    return
                }

                guard error == nil,
                      let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let sessions = json["sessions"] as? [[String: Any]] else {
                    self.pushWatchRelayPreservedProjects(reason: reason)
                    return
                }

                let currentRequestId = self.currentRequest?.requestId ?? self.focusedRequestId
                let fetchedProjects = sessions.map(activeProjectInfo(from:))
                let resolvedProjects = mergeActiveProjectFlags(
                    into: fetchedProjects,
                    currentRequestId: currentRequestId,
                    webSocketManager: self.webSocketManager
                )
                ActiveProjectCache.projectsByBaseURL[self.activeSessionsCacheKey] = resolvedProjects
                self.watchRelay.sendProjects(watchRelayProjectPayload(from: resolvedProjects), reason: reason)
            }
        }.resume()
    }

    private func pushWatchRelayPreservedProjects(reason: String) {
        if let cached = ActiveProjectCache.projectsByBaseURL[activeSessionsCacheKey], !cached.isEmpty {
            let currentRequestId = currentRequest?.requestId ?? focusedRequestId
            let resolvedProjects = mergeActiveProjectFlags(
                into: cached,
                currentRequestId: currentRequestId,
                webSocketManager: webSocketManager
            )
            watchRelay.sendProjects(watchRelayProjectPayload(from: resolvedProjects), reason: reason)
            return
        }

        pushWatchRelayFallbackProjects(reason: reason)
    }

    private func pushWatchRelayFallbackProjects(reason: String) {
        guard let request = currentRequest else {
            watchRelay.sendProjects([], reason: reason)
            return
        }

        let projectPath = request.projectPath ?? focusedProjectPath ?? "Unknown"
        let projectName = projectPath.components(separatedBy: "/").last ?? projectPath
        watchRelay.sendProjects([
            [
                "request_id": request.requestId ?? projectPath,
                "project_path": projectPath,
                "name": projectName,
                "title": request.message ?? "",
                "is_current": true,
                "is_waiting": webSocketManager.waitingStatus(projectPath: projectPath, requestId: request.requestId)
            ]
        ], reason: reason)
    }

    private func resetInputState() {
        userInput = ""
        selectedImages = []
        selectedOptions = []
        lastSpeechCorrectionObservation = nil
        clearVoiceSemanticSpeechState()
        clearSpeechDraftState()
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

private struct GhostSuggestionEditDraft: Identifiable {
    let id: String
    let key: String
    let description: String
    let enabled: Bool
}

struct GhostSuggestionManagerSheet: View {
    @ObservedObject var webSocketManager: WebSocketManager
    @Binding var isPresented: Bool
    @State private var newKey = ""
    @State private var newDescription = ""
    @State private var newEnabled = true
    @State private var editDraft: GhostSuggestionEditDraft?
    @State private var isWorking = false
    @State private var errorMessage = ""

    private var orderedSuggestions: [GhostSuggestionItem] {
        (webSocketManager.ghostSuggestionStore?.suggestions ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("新增") {
                    TextField("触发词", text: $newKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("描述", text: $newDescription)
                    Toggle("启用", isOn: $newEnabled)
                    Button(action: addSuggestion) {
                        Label("添加", systemImage: "plus")
                    }
                    .disabled(isWorking || normalizedNewKey.isEmpty)
                }

                Section("词表") {
                    if orderedSuggestions.isEmpty {
                        Text("暂无词条")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(orderedSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                            suggestionRow(suggestion, index: index)
                        }
                    }
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("幽灵补全词表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { isPresented = false }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    }
                    Button(action: {
                        errorMessage = ""
                        webSocketManager.refreshGhostSuggestions()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isWorking)
                }
            }
        }
        .onAppear {
            webSocketManager.refreshGhostSuggestions()
        }
        .sheet(item: $editDraft) { draft in
            GhostSuggestionEditSheet(draft: draft) { key, description, enabled in
                updateSuggestion(draft.id, key: key, description: description, enabled: enabled)
            }
        }
    }

    private var normalizedNewKey: String {
        newKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: GhostSuggestionItem, index: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.key)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if !suggestion.description.isEmpty {
                    Text(suggestion.description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { suggestion.enabled },
                set: { enabled in
                    updateSuggestion(
                        suggestion.id,
                        key: suggestion.key,
                        description: suggestion.description,
                        enabled: enabled
                    )
                }
            ))
            .labelsHidden()
            .disabled(isWorking)

            Button(action: {
                editDraft = GhostSuggestionEditDraft(
                    id: suggestion.id,
                    key: suggestion.key,
                    description: suggestion.description,
                    enabled: suggestion.enabled
                )
            }) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .disabled(isWorking)

            VStack(spacing: 6) {
                Button(action: { moveSuggestion(at: index, offset: -1) }) {
                    Image(systemName: "chevron.up")
                }
                .disabled(isWorking || index == 0)

                Button(action: { moveSuggestion(at: index, offset: 1) }) {
                    Image(systemName: "chevron.down")
                }
                .disabled(isWorking || index == orderedSuggestions.count - 1)
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: {
                deleteSuggestion(suggestion.id)
            }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }
        .padding(.vertical, 2)
    }

    private func addSuggestion() {
        let key = normalizedNewKey
        guard !key.isEmpty else { return }

        runWrite(successMessage: "已添加幽灵补全词") { completion in
            webSocketManager.addGhostSuggestion(
                key: key,
                description: newDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                enabled: newEnabled,
                completion: completion
            )
        } onSuccess: {
            newKey = ""
            newDescription = ""
            newEnabled = true
        }
    }

    private func updateSuggestion(_ id: String, key: String, description: String, enabled: Bool) {
        runWrite(successMessage: "已更新幽灵补全词") { completion in
            webSocketManager.updateGhostSuggestion(
                id: id,
                key: key.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                enabled: enabled,
                completion: completion
            )
        }
    }

    private func deleteSuggestion(_ id: String) {
        runWrite(successMessage: "已删除幽灵补全词") { completion in
            webSocketManager.deleteGhostSuggestion(id: id, completion: completion)
        }
    }

    private func moveSuggestion(at index: Int, offset: Int) {
        let destination = index + offset
        guard orderedSuggestions.indices.contains(index),
              orderedSuggestions.indices.contains(destination) else {
            return
        }

        var ids = orderedSuggestions.map(\.id)
        ids.swapAt(index, destination)
        runWrite(successMessage: "已更新幽灵补全顺序") { completion in
            webSocketManager.reorderGhostSuggestions(ids: ids, completion: completion)
        }
    }

    private func runWrite(
        successMessage: String,
        operation: (@escaping (Result<GhostSuggestionStore, Error>) -> Void) -> Void,
        onSuccess: (() -> Void)? = nil
    ) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = ""
        operation { result in
            isWorking = false
            switch result {
            case .success:
                onSuccess?()
                webSocketManager.addMessage(successMessage)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct GhostSuggestionEditSheet: View {
    let draft: GhostSuggestionEditDraft
    let onSave: (String, String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key: String
    @State private var description: String
    @State private var enabled: Bool

    init(
        draft: GhostSuggestionEditDraft,
        onSave: @escaping (String, String, Bool) -> Void
    ) {
        self.draft = draft
        self.onSave = onSave
        _key = State(initialValue: draft.key)
        _description = State(initialValue: draft.description)
        _enabled = State(initialValue: draft.enabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("触发词", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("描述", text: $description)
                Toggle("启用", isOn: $enabled)
            }
            .navigationTitle("编辑词条")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(key, description, enabled)
                        dismiss()
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct RelaySettingsView: View {
    @Binding var relayControlBaseURL: String
    @Binding var relayMacDeviceID: String
    @Binding var relayAutoRecoverOnActivation: Bool
    let onComplete: () -> Void
    let onConnectBackup: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("控制面") {
                    TextField("https://relay.example.com", text: $relayControlBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Mac") {
                    TextField("local-mac", text: $relayMacDeviceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("自动恢复") {
                    Toggle("前台断连时通过 Relay 修复公网", isOn: $relayAutoRecoverOnActivation)
                    Text("只在已配置 Relay 且当前未连接时触发，并有本机 5 分钟冷却。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("备用入口") {
                    Button {
                        relayControlBaseURL = relayControlBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        let configuredMacDeviceID = relayMacDeviceID
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        relayMacDeviceID = configuredMacDeviceID.isEmpty ? "local-mac" : configuredMacDeviceID
                        dismiss()
                        onConnectBackup()
                    } label: {
                        Label("连接 Relay 备用", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .disabled(relayControlBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Text("默认连接仍使用当前 Companion 配对地址；只有点击这里才切到 Relay。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Relay 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        relayControlBaseURL = relayControlBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        let configuredMacDeviceID = relayMacDeviceID
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        relayMacDeviceID = configuredMacDeviceID.isEmpty ? "local-mac" : configuredMacDeviceID
                        dismiss()
                        onComplete()
                    }
                }
            }
        }
    }
}

struct CircleIconButton: View {
    let systemName: String
    let theme: IterateTheme
    let action: () -> Void
    let longPressMenuTitle: String?
    let longPressSystemImage: String?
    let longPressAction: (() -> Void)?

    init(
        systemName: String,
        theme: IterateTheme,
        action: @escaping () -> Void,
        longPressMenuTitle: String? = nil,
        longPressSystemImage: String? = nil,
        longPressAction: (() -> Void)? = nil
    ) {
        self.systemName = systemName
        self.theme = theme
        self.action = action
        self.longPressMenuTitle = longPressMenuTitle
        self.longPressSystemImage = longPressSystemImage
        self.longPressAction = longPressAction
    }

    @ViewBuilder
    var body: some View {
        if let longPressAction {
            button
                .contextMenu {
                    Button(action: longPressAction) {
                        Label(
                            longPressMenuTitle ?? "选择路径",
                            systemImage: longPressSystemImage ?? "folder"
                        )
                    }
                }
        } else {
            button
        }
    }

    @ViewBuilder
    private var button: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                buttonLabel
            }
            .buttonStyle(.plain)
            .background {
                Color.clear
                    .glassEffect(.clear, in: Circle())
                    .allowsHitTesting(false)
            }
        } else {
            Button(action: action) {
                buttonLabel
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

    private var buttonLabel: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(theme.text)
            .frame(width: 36, height: 36)
            .contentShape(Circle())
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

/// Typeless 麦克风检测里那种 **单条横向电平**（非波形图、非折线）。
private struct TypelessStyleMicLevelBar: View {
    let level: CGFloat
    let trackColor: Color
    let fillColor: Color
    let barWidth: CGFloat

    private var effectiveLevel: CGFloat {
        let v = min(1, max(0, level))
        return v < 0.022 ? 0 : v
    }

    var body: some View {
        let w = barWidth
        let e = effectiveLevel
        let fillW = e > 0 ? max(10, w * e) : 0
        ZStack(alignment: .leading) {
            Capsule()
                .fill(trackColor.opacity(0.38))
                .frame(width: w, height: 6)
            if fillW > 0 {
                Capsule()
                    .fill(fillColor)
                    .frame(width: min(w, fillW), height: 6)
            }
        }
        .frame(width: w, height: 6)
        .animation(.easeOut(duration: 0.07), value: level)
    }
}

private struct RecordingWaveformIcon: View {
    let level: CGFloat
    let foregroundColor: Color

    private let weights: [CGFloat] = [0.32, 0.48, 0.68, 0.86, 1, 0.86, 0.68, 0.48, 0.32]
    private let minimumHeight: CGFloat = 5
    private let maximumHeight: CGFloat = 34

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18.0, paused: level <= 0.001)) { context in
            HStack(spacing: 3) {
                ForEach(0..<9, id: \.self) { index in
                    Capsule()
                        .fill(foregroundColor)
                        .frame(width: 3, height: barHeight(at: index, date: context.date))
                }
            }
            .frame(height: maximumHeight)
            .animation(.easeOut(duration: 0.07), value: level)
        }
    }

    private func barHeight(at index: Int, date: Date) -> CGFloat {
        let normalizedLevel = min(1, max(0, level))
        guard normalizedLevel > 0.025 else { return minimumHeight }
        let phase = date.timeIntervalSinceReferenceDate * 11 + Double(index) * 0.82
        let flutter = CGFloat(0.9 + 0.1 * sin(phase))
        let amplitude = normalizedLevel * weights[index] * flutter
        return minimumHeight + (maximumHeight - minimumHeight) * amplitude
    }
}

struct VoiceHalfCircleDock: View {
    let isRecording: Bool
    let isLiveActive: Bool
    let isLiveConnected: Bool
    let isLiveMuted: Bool
    @ObservedObject private var meter: SpeechMeterState
    let theme: IterateTheme
    /// 与 `ContentView.isDarkMode` 对应；勿用系统 `colorScheme`，否则系统深色 + App 浅色时电条会错成白色。
    let iterateAppearanceIsLight: Bool
    let usesIntegratedFooterGlass: Bool
    let onLongPress: () -> Void
    let action: () -> Void

    init(
        isRecording: Bool,
        isLiveActive: Bool,
        isLiveConnected: Bool,
        isLiveMuted: Bool,
        meter: SpeechMeterState,
        theme: IterateTheme,
        iterateAppearanceIsLight: Bool,
        usesIntegratedFooterGlass: Bool = false,
        onLongPress: @escaping () -> Void,
        action: @escaping () -> Void
    ) {
        self.isRecording = isRecording
        self.isLiveActive = isLiveActive
        self.isLiveConnected = isLiveConnected
        self.isLiveMuted = isLiveMuted
        self._meter = ObservedObject(wrappedValue: meter)
        self.theme = theme
        self.iterateAppearanceIsLight = iterateAppearanceIsLight
        self.usesIntegratedFooterGlass = usesIntegratedFooterGlass
        self.onLongPress = onLongPress
        self.action = action
    }

    var body: some View {
        let m = VoiceHalfCircleDockMetrics.self
        let barTrackWidth = m.width - 32
        let barFill: Color = iterateAppearanceIsLight ? .black : theme.text
        let barTrack: Color = iterateAppearanceIsLight ? Color.black.opacity(0.14) : theme.text.opacity(0.22)

        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                dockContent(
                    barTrackWidth: barTrackWidth,
                    barTrack: barTrack,
                    barFill: barFill,
                    microphoneForeground: microphoneForeground,
                    legacyRing: legacyRing
                )
            }
        } else {
            dockContent(
                barTrackWidth: barTrackWidth,
                barTrack: barTrack,
                barFill: barFill,
                microphoneForeground: microphoneForeground,
                legacyRing: legacyRing
            )
        }
    }

    private var microphoneForeground: Color {
        if isLiveActive {
            return theme.accent
        }
        if isRecording {
            return iterateAppearanceIsLight ? .black : theme.activeText
        }
        return theme.textSecondary
    }

    private var legacyRing: Color {
        if isLiveActive {
            return theme.accent.opacity(0.52)
        }
        if isRecording {
            return iterateAppearanceIsLight ? Color.black.opacity(0.18) : theme.border.opacity(0.45)
        }
        return theme.border
    }

    @ViewBuilder
    private func dockContent(
        barTrackWidth: CGFloat,
        barTrack: Color,
        barFill: Color,
        microphoneForeground: Color,
        legacyRing: Color
    ) -> some View {
        let m = VoiceHalfCircleDockMetrics.self
        let micLevel = meter.level
        ZStack(alignment: .bottom) {
            platterSurface

            VStack(spacing: 9) {
                if isRecording {
                    TypelessStyleMicLevelBar(
                        level: micLevel,
                        trackColor: barTrack,
                        fillColor: barFill,
                        barWidth: barTrackWidth
                    )
                    .offset(y: -m.recordingBarLift)
                }

                microphoneControl(
                    foregroundColor: microphoneForeground,
                    legacyRing: legacyRing
                )
            }
            .offset(y: m.micButtonYOffset)
        }
        .frame(width: m.width, height: m.outerHeight)
    }

    @ViewBuilder
    private var platterSurface: some View {
        let m = VoiceHalfCircleDockMetrics.self
        if #available(iOS 26.0, *) {
            if usesIntegratedFooterGlass {
                Color.clear
                    .frame(width: m.width, height: m.semicircleHeight)
            } else {
                Color.clear
                    .frame(width: m.width, height: m.semicircleHeight)
                    .glassEffect(.clear, in: TopHalfCircleShape())
                    .overlay(platterArc)
            }
        } else {
            TopHalfCircleShape()
                .fill(.ultraThinMaterial)
                .frame(width: m.width, height: m.semicircleHeight)
                .overlay(platterArc)
        }
    }

    private var platterArc: some View {
        TopHalfCircleArcShape()
            .stroke(
                isLiveActive
                    ? theme.accent.opacity(0.65)
                    : isRecording ? theme.text.opacity(0.4) : theme.border.opacity(0.65),
                lineWidth: VoiceHalfCircleDockMetrics.arcStrokeWidth
            )
    }

    @ViewBuilder
    private func microphoneLabel(foregroundColor: Color) -> some View {
        let micLevel = meter.level
        Group {
            if isLiveActive {
                Image(systemName: isLiveMuted
                    ? "mic.slash.fill"
                    : isLiveConnected ? "waveform.circle.fill" : "waveform.circle")
                    .font(.system(size: VoiceHalfCircleDockMetrics.micFontSize, weight: .semibold))
                    .foregroundColor(foregroundColor)
            } else if isRecording {
                RecordingWaveformIcon(
                    level: micLevel,
                    foregroundColor: foregroundColor
                )
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: VoiceHalfCircleDockMetrics.micFontSize, weight: .semibold))
                    .foregroundColor(foregroundColor)
            }
        }
        .frame(
            width: VoiceHalfCircleDockMetrics.micButtonSize,
            height: VoiceHalfCircleDockMetrics.micButtonSize
        )
        .contentShape(Circle())
    }

    private var microphoneGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45, maximumDistance: 16)
            .exclusively(before: TapGesture())
            .onEnded { result in
                switch result {
                case .first(_):
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onLongPress()
                case .second:
                    action()
                }
            }
    }

    @ViewBuilder
    private func microphoneControl(foregroundColor: Color, legacyRing: Color) -> some View {
        microphoneLabel(foregroundColor: foregroundColor)
            .gesture(microphoneGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                isLiveActive
                    ? (isLiveMuted ? "继续 Codex Live 收音" : "静音 Codex Live")
                    : isRecording ? "停止语音输入" : "开始语音输入"
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                action()
            }
            .accessibilityAction(named: Text(isLiveActive ? "退出 GPT Live" : "进入 GPT Live")) {
                onLongPress()
            }
        }
}

struct TopHalfCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.closeSubpath()

        return path
    }
}

/// 仅上半圆弧，无底边弦线；footer 下方不再绘制全宽灰线。
struct TopHalfCircleArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        return path
    }
}

struct BridgeSecondaryButton: View {
    let title: String
    let theme: IterateTheme
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                footerActionLabel
                    .frame(height: VoiceFooterBarLayout.footerActionLabelHeight)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glass(.clear))
            .buttonBorderShape(.roundedRectangle(radius: 8))
        } else {
            Button(action: action) {
                footerActionLabel
                    .padding(.vertical, 10)
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

    private var footerActionLabel: some View {
        Text(title)
            .font(.system(size: 22, weight: .bold))
            .frame(maxWidth: .infinity)
            .foregroundColor(theme.text)
    }
}

struct BridgePrimaryButton: View {
    let title: String
    let theme: IterateTheme
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                footerActionLabel(foregroundColor: theme.text)
                    .frame(height: VoiceFooterBarLayout.footerActionLabelHeight)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glass(.clear))
            .buttonBorderShape(.roundedRectangle(radius: 8))
        } else {
            Button(action: action) {
                footerActionLabel(foregroundColor: theme.activeText)
                    .padding(.vertical, 10)
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

    private func footerActionLabel(foregroundColor: Color) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .foregroundColor(foregroundColor)
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
    let isDragging: Bool
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
                    .stroke(isDragging ? theme.accent.opacity(0.7) : theme.borderLight, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(isDragging ? 0.78 : 1)
        .scaleEffect(isDragging ? 1.05 : 1)
        .shadow(
            color: Color.black.opacity(isDragging ? 0.2 : 0),
            radius: isDragging ? 12 : 0,
            y: isDragging ? 6 : 0
        )
        .accessibilityHint("轻点插入，长按并拖动可调整顺序")
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isDragging)
    }
}

struct ConditionalToggleRow: View {
    let prompt: PromptItem
    @ObservedObject var webSocketManager: WebSocketManager
    let projectPath: String?
    let requestId: String?
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
                    webSocketManager.updateConditionalState(
                        promptId: prompt.id,
                        newState: newValue,
                        projectPath: projectPath,
                        requestId: requestId
                    )
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
        webSocketManager.updateConditionalActive(
            promptId: prompt.id,
            isActive: value,
            projectPath: projectPath,
            requestId: requestId
        )
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
    @Binding var selection: NSRange
    @Binding var isFocused: Bool
    @Binding var isDropTargeted: Bool
    let placeholder: String
    let ghostText: String?
    let theme: IterateTheme
    let onPasteImage: (UIImage) -> Void
    let onAcceptGhostSuggestion: () -> Bool
    let onDrop: ([NSItemProvider]) -> Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            PasteAwareTextView(
                text: $text,
                selection: $selection,
                isFocused: $isFocused,
                ghostText: ghostText,
                theme: theme,
                onPasteImage: onPasteImage,
                onAcceptGhostSuggestion: onAcceptGhostSuggestion
            )
                .frame(minHeight: 120, maxHeight: 180)

            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
                    .padding(.leading, 18)
                    .padding(.trailing, 18)
                    .padding(.vertical, 16)
            }
        }
        .padding(10)
        .background(theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isDropTargeted ? theme.accent : theme.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onDrop(of: [UTType.image.identifier], isTargeted: $isDropTargeted, perform: onDrop)
    }
}

struct PasteAwareTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var isFocused: Bool
    let ghostText: String?
    let theme: IterateTheme
    let onPasteImage: (UIImage) -> Void
    let onAcceptGhostSuggestion: () -> Bool

    func makeUIView(context: Context) -> ImagePasteTextView {
        let textView = ImagePasteTextView()
        textView.onPasteImage = onPasteImage
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.textColor = UIColor(theme.text)
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 0
        textView.layer.borderColor = UIColor.clear.cgColor
        textView.clipsToBounds = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        return textView
    }

    func updateUIView(_ uiView: ImagePasteTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.selectedRange != selection {
            uiView.selectedRange = selection
        }
        uiView.textColor = UIColor(theme.text)
        uiView.backgroundColor = .clear
        uiView.layer.borderColor = UIColor.clear.cgColor
        uiView.updateGhostText(ghostText, theme: theme)
        context.coordinator.ghostText = ghostText
        context.coordinator.onAcceptGhostSuggestion = onAcceptGhostSuggestion

        if isFocused && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                guard isFocused, !uiView.isFirstResponder else { return }
                uiView.becomeFirstResponder()
            }
        } else if !isFocused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            selection: $selection,
            isFocused: $isFocused,
            ghostText: ghostText,
            onAcceptGhostSuggestion: onAcceptGhostSuggestion
        )
    }

    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var selection: NSRange
        @Binding var isFocused: Bool
        var ghostText: String?
        var onAcceptGhostSuggestion: () -> Bool

        init(
            text: Binding<String>,
            selection: Binding<NSRange>,
            isFocused: Binding<Bool>,
            ghostText: String?,
            onAcceptGhostSuggestion: @escaping () -> Bool
        ) {
            _text = text
            _selection = selection
            _isFocused = isFocused
            self.ghostText = ghostText
            self.onAcceptGhostSuggestion = onAcceptGhostSuggestion
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            let shouldAccept = GhostSuggestionReturnKeyPolicy.shouldAcceptSuggestion(
                replacementText: replacement,
                hasVisibleSuggestion: !(ghostText?.isEmpty ?? true),
                isComposing: textView.markedTextRange != nil
            )
            guard shouldAccept else { return true }

            return !onAcceptGhostSuggestion()
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            selection = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            selection = textView.selectedRange
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFocused = false
        }
    }
}

final class ImagePasteTextView: UITextView {
    var onPasteImage: ((UIImage) -> Void)?
    private let ghostLabel = UILabel()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureGhostLabel()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureGhostLabel()
    }

    private func configureGhostLabel() {
        ghostLabel.isUserInteractionEnabled = false
        ghostLabel.numberOfLines = 1
        ghostLabel.lineBreakMode = .byClipping
        ghostLabel.backgroundColor = .clear
        ghostLabel.isHidden = true
        addSubview(ghostLabel)
    }

    func updateGhostText(_ ghostText: String?, theme: IterateTheme) {
        ghostLabel.font = font
        ghostLabel.textColor = UIColor(theme.textSecondary).withAlphaComponent(0.55)
        ghostLabel.text = ghostText
        refreshGhostOverlay()
    }

    func refreshGhostOverlay() {
        guard let ghostText = ghostLabel.text,
              !ghostText.isEmpty,
              selectedRange.length == 0,
              let insertionPosition = selectedTextRange?.end else {
            ghostLabel.isHidden = true
            return
        }

        let caret = caretRect(for: insertionPosition)
        guard !caret.isNull else {
            ghostLabel.isHidden = true
            return
        }

        let trailingInset = textContainerInset.right + textContainer.lineFragmentPadding
        let maxWidth = bounds.width - trailingInset - caret.maxX
        guard maxWidth > 8 else {
            ghostLabel.isHidden = true
            return
        }

        ghostLabel.isHidden = false
        ghostLabel.frame = CGRect(
            x: caret.maxX,
            y: caret.minY,
            width: maxWidth,
            height: caret.height
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshGhostOverlay()
    }

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
    @Binding var focusedRequestId: String?
    @Binding var focusedProjectPath: String?
    @Binding var focusedRoutePreviewMessage: String?
    @Binding var isManualRouteSelection: Bool
    let serverURL: String
    let relayControlBaseURL: String
    let relayMacDeviceID: String
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    @State private var projects: [ProjectInfo] = []
    @State private var isLoading = true

    private func selectProject(_ project: ProjectInfo) {
        let projectPath = project.projectPath

        focusedRequestId = project.requestId
        focusedProjectPath = projectPath
        focusedRoutePreviewMessage = project.optimisticPreviewMessage
        isManualRouteSelection = true

        isPresented = false

        DispatchQueue.main.async {
            webSocketManager.switchProject(to: projectPath, requestId: project.requestId)
        }
    }

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
                    ForEach(projects, id: \.stableId) { project in
                        Button(action: {
                            selectProject(project)
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
                                    if let sourceLabel = project.sourceLabel {
                                        Text(sourceLabel)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer(minLength: 12)
                                HStack(spacing: 8) {
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
                                    TimelineView(.periodic(from: Date(), by: 60)) { context in
                                        Text(ActiveProjectTimeFormatter.label(
                                            for: project.lastActiveAt,
                                            now: context.date
                                        ))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
            restoreCachedProjectsIfAvailable()
            fetchProjects(showLoading: projects.isEmpty)
        }
        .onReceive(refreshTimer) { _ in
            fetchProjects(showLoading: false)
        }
    }

    private var activeSessionsBaseURL: String {
        serverURL
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")
            .replacingOccurrences(of: "/ws", with: "")
    }

    private var activeSessionsCacheKey: String {
        if webSocketManager.currentTransportMode == "relay",
           let relayBaseURL = normalizedRelayControlBaseURL() {
            let macDeviceID = normalizedRelayMacDeviceID()
            return "\(relayBaseURL)/api/devices/\(relayPathComponent(macDeviceID))"
        }
        return activeSessionsBaseURL
    }

    private func normalizedRelayMacDeviceID() -> String {
        let trimmed = relayMacDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "local-mac" : trimmed
    }

    private func normalizedRelayControlBaseURL() -> String? {
        var baseURL = relayControlBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")
        while baseURL.hasSuffix("/") {
            baseURL.removeLast()
        }
        guard !baseURL.isEmpty,
              let components = URLComponents(string: baseURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else {
            return nil
        }
        return baseURL
    }

    private func relayPathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func applyRelayHeaders(to request: inout URLRequest) {
        request.setValue("ios", forHTTPHeaderField: "X-Iterate-Client-Kind")
        guard let relayBaseURL = normalizedRelayControlBaseURL() else {
            return
        }
        RelayAuthStore.applyAuthHeaders(
            to: &request,
            relayBaseURL: relayBaseURL,
            relayDeviceID: normalizedRelayMacDeviceID()
        )
    }

    private func activeSessionsRequest() -> URLRequest? {
        if webSocketManager.currentTransportMode == "relay",
           let relayBaseURL = normalizedRelayControlBaseURL() {
            guard let url = URL(string: "\(relayBaseURL)/api/devices/\(relayPathComponent(normalizedRelayMacDeviceID()))/sessions") else {
                return nil
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 8
            applyRelayHeaders(to: &request)
            return request
        }

        guard let url = URL(string: "\(activeSessionsBaseURL)/api/active-sessions") else {
            return nil
        }
        return DeviceAuthStore.authorizedRequest(url: url)
    }

    private var currentRequestIdHint: String? {
        let currentRequestId = focusedRequestId
            ?? webSocketManager.mcpMessages.first?.payload?.request?.requestId
        return currentRequestId
    }

    private func mergeCurrentFlags(into projects: [ProjectInfo]) -> [ProjectInfo] {
        mergeActiveProjectFlags(
            into: projects,
            currentRequestId: currentRequestIdHint,
            webSocketManager: webSocketManager
        )
    }

    @discardableResult
    private func restoreCachedProjectsIfAvailable() -> Bool {
        guard let cached = ActiveProjectCache.projectsByBaseURL[activeSessionsCacheKey], !cached.isEmpty else {
            return false
        }
        projects = mergeCurrentFlags(into: cached)
        isLoading = false
        return true
    }

    private func fallbackToCurrentProjectIfNeeded() {
        guard projects.isEmpty else { return }

        guard let request = webSocketManager.mcpMessages.first(where: {
            $0.payload?.request?.requestId == currentRequestIdHint
        })?.payload?.request ?? webSocketManager.mcpMessages.first?.payload?.request else {
            return
        }

        let projectPath = request.projectPath ?? "Unknown"
        let projectName = projectPath.components(separatedBy: "/").last ?? projectPath
        projects = [
                ProjectInfo(
                    requestId: request.requestId ?? projectPath,
                    name: projectName,
                    projectPath: projectPath,
                    title: request.message ?? "",
                    isCurrent: true,
                    isWaiting: webSocketManager.waitingStatus(
                        projectPath: projectPath,
                        requestId: request.requestId
                    ),
                    source: "current_fallback",
                    port: nil,
                    lastActiveAt: nil
                )
            ]
        isLoading = false
    }

    private func preserveProjectsOrFallbackToCurrentProject() {
        if !projects.isEmpty {
            projects = mergeCurrentFlags(into: projects)
            isLoading = false
            return
        }
        if restoreCachedProjectsIfAvailable() {
            return
        }
        fallbackToCurrentProjectIfNeeded()
    }

    func fetchProjects(showLoading: Bool = true) {
        if showLoading {
            isLoading = true
        }
        guard let request = activeSessionsRequest() else {
            isLoading = false
            preserveProjectsOrFallbackToCurrentProject()
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "project_picker_active_sessions") {
                    preserveProjectsOrFallbackToCurrentProject()
                    return
                }

                guard error == nil,
                      let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let sessions = json["sessions"] as? [[String: Any]] else {
                    preserveProjectsOrFallbackToCurrentProject()
                    return
                }

                let fetchedProjects = sessions.map(activeProjectInfo(from:))
                let resolvedProjects = mergeCurrentFlags(into: fetchedProjects)
                projects = resolvedProjects
                ActiveProjectCache.projectsByBaseURL[activeSessionsCacheKey] = resolvedProjects
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
    let source: String
    let port: Int?
    let lastActiveAt: Date?

    var stableId: String {
        return requestId
    }

    var optimisticPreviewMessage: String? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? nil : trimmedTitle
    }

    var sourceLabel: String? {
        switch source {
        case "window_registry", "current_fallback", "legacy":
            return nil
        default:
            return source.isEmpty ? nil : source
        }
    }
}

private enum ActiveProjectCache {
    static var projectsByBaseURL: [String: [ProjectInfo]] = [:]
}

private func activeProjectInfo(from session: [String: Any]) -> ProjectInfo {
    let requestId = session["request_id"] as? String ?? "unknown-request"
    let projectPath = session["project_path"] as? String ?? "Unknown"
    let projectName = session["project_name"] as? String
        ?? projectPath.components(separatedBy: "/").last
        ?? projectPath
    let title = session["title"] as? String ?? ""
    let source = session["source"] as? String ?? "window_registry"
    let port = session["port"] as? Int
    let lastActiveAt = ActiveProjectTimeFormatter.date(from: session["last_active_at"] as? String)
    return ProjectInfo(
        requestId: requestId,
        name: projectName,
        projectPath: projectPath,
        title: title,
        isCurrent: false,
        isWaiting: false,
        source: source,
        port: port,
        lastActiveAt: lastActiveAt
    )
}

private func mergeActiveProjectFlags(
    into projects: [ProjectInfo],
    currentRequestId: String?,
    webSocketManager: WebSocketManager
) -> [ProjectInfo] {
    projects.map { project in
        ProjectInfo(
            requestId: project.requestId,
            name: project.name,
            projectPath: project.projectPath,
            title: project.title,
            isCurrent: project.requestId == currentRequestId,
            isWaiting: webSocketManager.waitingStatus(
                projectPath: project.projectPath,
                requestId: project.requestId
            ),
            source: project.source,
            port: project.port,
            lastActiveAt: project.lastActiveAt
        )
    }
}

private func watchRelayProjectPayload(from projects: [ProjectInfo]) -> [[String: Any]] {
    projects.map { project in
        var payload: [String: Any] = [
            "request_id": project.requestId,
            "project_path": project.projectPath,
            "name": project.name,
            "title": project.title,
            "is_current": project.isCurrent,
            "is_waiting": project.isWaiting,
            "source": project.source
        ]
        if let port = project.port {
            payload["port"] = port
        }
        return payload
    }
}

// MARK: - 路径选择器
private struct FileSelectorPathRow: Identifiable {
    let relativePath: String
    let name: String
    let isDirectory: Bool
    let depth: Int

    var id: String { relativePath }
}

enum FileSelectorMode {
    case insertReference
    case chooseCodexDefaultProject
}

struct FileSelectorView: View {
    let preferredProjectPath: String?
    let fallbackProjectPaths: [String]
    let mode: FileSelectorMode
    @Binding var isPresented: Bool
    @Binding var userInput: String
    let onSelectDefaultProjectPath: ((String) -> Void)?
    @State private var currentDirectory: String? = nil
    @State private var currentEntries: [String] = []
    @State private var searchText = ""
    @State private var isLoadingDirectory = true
    @State private var loadErrorMessage: String? = nil
    @State private var loadGeneration = 0
    @State private var browserRootPath: String? = nil
    @State private var initialDirectoryPath: String? = nil
    @State private var fallbackNotice: String? = nil
    @State private var showCreateDirectoryAlert = false
    @State private var newDirectoryName = ""
    @State private var isCreatingDirectory = false

    private var visibleRows: [FileSelectorPathRow] {
        let rows = currentEntries.map { entry in
            FileSelectorPathRow(
                relativePath: entry,
                name: displayName(for: entry),
                isDirectory: entry.hasSuffix("/"),
                depth: 0
            )
        }
        guard !searchText.isEmpty else {
            return rows
        }
        let keyword = searchText.lowercased()
        return rows.filter {
            $0.name.lowercased().contains(keyword) ||
                $0.relativePath.lowercased().contains(keyword) ||
                absolutePath(for: $0.relativePath)?.lowercased().contains(keyword) == true
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text(instructionText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 12)

                if let fallbackNotice {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.shield")
                            .foregroundColor(.orange)
                        Text(fallbackNotice)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("搜索路径...", text: $searchText)
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding()

                if isLoadingDirectory {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if let loadErrorMessage {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                        Text(loadErrorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                } else if currentDirectory == nil {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                        Text("未找到项目路径")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                        Text("请先切换到一个项目，或长按 + 设置默认路径")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                } else {
                    currentDirectoryHeader
                    if visibleRows.isEmpty {
                        Spacer()
                        Text(searchText.isEmpty ? "当前目录为空" : "未找到路径")
                            .foregroundColor(.gray)
                        Spacer()
                    } else {
                        List(visibleRows) { row in
                            pathRow(row)
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
                if currentDirectory != nil && loadErrorMessage == nil {
                    ToolbarItemGroup(placement: .confirmationAction) {
                        if mode == .chooseCodexDefaultProject {
                            Button {
                                newDirectoryName = ""
                                showCreateDirectoryAlert = true
                            } label: {
                                Image(systemName: "folder.badge.plus")
                            }
                            .disabled(isCreatingDirectory)
                        }
                        Button("使用当前目录") {
                            selectCurrentDirectory()
                        }
                    }
                }
            }
        }
        .onAppear {
            loadInitialDirectory()
        }
        .onChange(of: preferredProjectPath ?? "") { _ in
            loadInitialDirectory()
        }
        .onChange(of: fallbackProjectPaths) { _ in
            loadInitialDirectory()
        }
        .alert("新建文件夹", isPresented: $showCreateDirectoryAlert) {
            TextField("文件夹名", text: $newDirectoryName)
            Button("取消", role: .cancel) {
                newDirectoryName = ""
            }
            Button("创建并设为默认") {
                createDirectoryAndSelectAsDefault()
            }
        } message: {
            Text("将在当前目录下创建新文件夹")
        }
    }

    @ViewBuilder
    private var currentDirectoryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Button(action: navigateToParentDirectory) {
                    Label("上一级", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(parentDirectory == nil)

                Spacer()

                Button(action: navigateToOriginalProjectDirectory) {
                    Label("原路径", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Color.accentColor.opacity(canNavigateToOriginalProjectDirectory ? 0.10 : 0.05),
                            in: Capsule()
                        )
                }
                .buttonStyle(.borderless)
                .disabled(!canNavigateToOriginalProjectDirectory)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("当前目录")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(currentDirectory ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if breadcrumbItems.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(breadcrumbItems.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            Button(action: {
                                navigate(to: item.path)
                            }) {
                                Text(item.label)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(item.path == currentDirectory ? .primary : .accentColor)
                            .disabled(item.path == currentDirectory)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func pathRow(_ row: FileSelectorPathRow) -> some View {
        Button(action: {
            selectPath(row)
        }) {
            HStack(spacing: 12) {
                Image(systemName: row.isDirectory ? "folder" : "doc")
                    .foregroundColor(.gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    if let absolutePath = absolutePath(for: row.relativePath) {
                        Text(absolutePath)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if row.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadInitialDirectory() {
        loadGeneration += 1
        let generation = loadGeneration
        isLoadingDirectory = true
        loadErrorMessage = nil
        fallbackNotice = nil
        browserRootPath = nil
        initialDirectoryPath = nil
        currentDirectory = nil
        currentEntries = []
        searchText = ""

        let baseURL = ServerConfig.currentHTTPBaseURL()
        guard let url = URL(string: "\(baseURL)/files/roots") else {
            isLoadingDirectory = false
            loadErrorMessage = "路径加载失败：请求地址无效"
            return
        }

        let request = DeviceAuthStore.authorizedRequest(url: url)
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard generation == loadGeneration else {
                    return
                }
                if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "file_selector_roots") {
                    isLoadingDirectory = false
                    loadErrorMessage = "设备授权已失效，请重新配对"
                    return
                }
                if let error {
                    isLoadingDirectory = false
                    loadErrorMessage = "路径加载失败：\(error.localizedDescription)"
                    return
                }
                if let http = response as? HTTPURLResponse,
                   http.statusCode == 404 {
                    loadLegacyInitialDirectory(generation: generation)
                    return
                }
                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    isLoadingDirectory = false
                    loadErrorMessage = fileSelectorErrorMessage(from: data) ?? "路径加载失败：HTTP \(http.statusCode)"
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let roots = json["roots"] as? [String] else {
                    isLoadingDirectory = false
                    loadErrorMessage = "路径加载失败：授权目录响应无效"
                    return
                }
                guard let location = CodexFileBrowserPath.resolveInitialLocation(
                    preferredPath: preferredProjectPath,
                    fallbackPaths: fallbackProjectPaths,
                    allowedRoots: roots
                ) else {
                    isLoadingDirectory = false
                    loadErrorMessage = "这台 iPhone 尚未获得 Mac 目录授权，请在 Mac 设置的 iPhone 配对区域选择授权目录"
                    return
                }
                applyInitialLocation(location, generation: generation, legacyServer: false)
            }
        }.resume()
    }

    private func loadLegacyInitialDirectory(generation: Int) {
        guard let location = CodexFileBrowserPath.legacyInitialLocation(
            preferredPath: preferredProjectPath,
            fallbackPaths: fallbackProjectPaths
        ) else {
            isLoadingDirectory = false
            loadErrorMessage = "未找到可安全浏览的项目路径"
            return
        }
        applyInitialLocation(location, generation: generation, legacyServer: true)
    }

    private func applyInitialLocation(
        _ location: CodexFileBrowserInitialLocation,
        generation: Int,
        legacyServer: Bool
    ) {
        browserRootPath = location.rootPath
        initialDirectoryPath = location.directoryPath
        currentDirectory = location.directoryPath
        if legacyServer {
            fallbackNotice = location.usedFallback
                ? "Mac 尚未提供设备授权目录清单；已忽略越界的默认路径，并把浏览范围限制在当前项目"
                : "Mac 尚未提供设备授权目录清单；为安全起见，浏览范围仅限当前项目"
        } else if location.usedFallback {
            fallbackNotice = "保存的默认路径不在这台 iPhone 的授权范围内，已改用授权目录；可在 Mac 设置中调整授权范围"
        }
        fetchEntries(forDirectory: location.directoryPath, generation: generation)
    }

    private func fetchEntries(forDirectory directoryPath: String, generation: Int) {
        guard let directoryPath = CodexFileBrowserPath.normalizedDirectory(directoryPath),
              let authorizedRootPath = browserRootPath,
              authorizedRootPath != "/",
              CodexFileBrowserPath.isInside(directoryPath, rootPath: authorizedRootPath) else {
            isLoadingDirectory = false
            loadErrorMessage = "路径加载失败：目录超出这台 iPhone 的授权范围"
            currentEntries = []
            return
        }

        isLoadingDirectory = true
        loadErrorMessage = nil

        let baseURL = ServerConfig.currentHTTPBaseURL()
        var components = URLComponents(string: "\(baseURL)/files")
        components?.queryItems = [
            URLQueryItem(name: "project_path", value: directoryPath),
            URLQueryItem(name: "max_depth", value: "0")
        ]
        guard let url = components?.url else {
            isLoadingDirectory = false
            loadErrorMessage = "路径加载失败：请求地址无效"
            return
        }

        let request = DeviceAuthStore.authorizedRequest(url: url)
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard generation == loadGeneration else {
                    return
                }
                isLoadingDirectory = false
                if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "file_selector") {
                    loadErrorMessage = "设备授权已失效，请重新配对"
                    currentEntries = []
                    return
                }
                if let error {
                    loadErrorMessage = "路径加载失败：\(error.localizedDescription)"
                    currentEntries = []
                    return
                }
                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    loadErrorMessage = fileSelectorErrorMessage(from: data) ?? "路径加载失败：HTTP \(http.statusCode)"
                    currentEntries = []
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let fileList = json["files"] as? [String] else {
                    loadErrorMessage = "路径加载失败：响应格式无效"
                    currentEntries = []
                    return
                }
                if let returnedRoot = json["browser_root"] as? String,
                   let normalizedRoot = CodexFileBrowserPath.allowedRoots([returnedRoot]).first,
                   CodexFileBrowserPath.isInside(directoryPath, rootPath: normalizedRoot) {
                    browserRootPath = normalizedRoot
                }
                loadErrorMessage = nil
                currentEntries = fileList.sorted(by: sortEntries)
            }
        }.resume()
    }

    private func selectPath(_ row: FileSelectorPathRow) {
        guard let absolutePath = absolutePath(for: row.relativePath) else {
            return
        }
        if row.isDirectory {
            navigate(to: absolutePath)
            return
        }

        switch mode {
        case .insertReference:
            insertReference(absolutePath)
        case .chooseCodexDefaultProject:
            selectCurrentDirectory()
        }
    }

    private func selectCurrentDirectory() {
        guard let currentDirectory else {
            return
        }
        switch mode {
        case .insertReference:
            insertReference(currentDirectory)
        case .chooseCodexDefaultProject:
            onSelectDefaultProjectPath?(currentDirectory)
            isPresented = false
        }
    }

    private func createDirectoryAndSelectAsDefault() {
        guard mode == .chooseCodexDefaultProject,
              let currentDirectory else {
            return
        }

        let directoryName = newDirectoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directoryName.isEmpty else {
            loadErrorMessage = "新建文件夹失败：文件夹名不能为空"
            return
        }

        let baseURL = ServerConfig.currentHTTPBaseURL()
        guard let url = URL(string: "\(baseURL)/files/mkdir"),
              let body = try? JSONSerialization.data(withJSONObject: [
                  "parent_path": currentDirectory,
                  "name": directoryName
              ]) else {
            loadErrorMessage = "新建文件夹失败：请求地址无效"
            return
        }

        var request = DeviceAuthStore.authorizedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        isCreatingDirectory = true

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isCreatingDirectory = false

                if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "file_selector_mkdir") {
                    loadErrorMessage = "设备授权已失效，请重新配对"
                    return
                }
                if let error {
                    loadErrorMessage = "新建文件夹失败：\(error.localizedDescription)"
                    return
                }
                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    loadErrorMessage = fileSelectorErrorMessage(from: data) ?? "新建文件夹失败：HTTP \(http.statusCode)"
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let createdPath = json["path"] as? String,
                      CodexFileBrowserPath.normalizedDirectory(createdPath) != nil else {
                    loadErrorMessage = "新建文件夹失败：响应格式无效"
                    return
                }

                onSelectDefaultProjectPath?(createdPath)
                isPresented = false
            }
        }.resume()
    }

    private func insertReference(_ absolutePath: String) {
        let fileRef = "@\(absolutePath)"
        if userInput.isEmpty {
            userInput = fileRef
        } else if userInput.hasSuffix(" ") {
            userInput += fileRef
        } else {
            userInput += " \(fileRef)"
        }
        isPresented = false
    }

    private func navigateToParentDirectory() {
        guard let parentDirectory else {
            return
        }
        navigate(to: parentDirectory)
    }

    private func navigateToOriginalProjectDirectory() {
        guard let initialDirectoryPath,
              currentDirectory != initialDirectoryPath else {
            return
        }
        navigate(to: initialDirectoryPath)
    }

    private func navigate(to directoryPath: String) {
        guard let normalizedDirectory = CodexFileBrowserPath.normalizedDirectory(directoryPath),
              let browserRootPath,
              CodexFileBrowserPath.isInside(normalizedDirectory, rootPath: browserRootPath) else {
            loadErrorMessage = "无法打开：目录超出这台 iPhone 的授权范围"
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        currentDirectory = normalizedDirectory
        searchText = ""
        fetchEntries(forDirectory: normalizedDirectory, generation: generation)
    }

    private func absolutePath(for entry: String) -> String? {
        guard let currentDirectory else {
            return nil
        }
        return CodexFileBrowserPath.childPath(currentDirectory: currentDirectory, entry: entry)
    }

    private func displayName(for entry: String) -> String {
        entry.hasSuffix("/") ? String(entry.dropLast()) : entry
    }

    private func sortEntries(_ lhs: String, _ rhs: String) -> Bool {
        let lhsIsDirectory = lhs.hasSuffix("/")
        let rhsIsDirectory = rhs.hasSuffix("/")
        if lhsIsDirectory != rhsIsDirectory {
            return lhsIsDirectory
        }
        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }

    private func fileSelectorErrorMessage(from data: Data?) -> String? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? String,
              !error.isEmpty else {
            return nil
        }
        switch error {
        case "file_list_root_not_allowed":
            return "当前路径未获这台 iPhone 授权，请在 Mac 设置的 iPhone 配对区域选择授权目录"
        case "missing_scope_file_list":
            return "这台 iPhone 没有文件浏览权限，请重新配对"
        default:
            return "路径加载失败：\(error)"
        }
    }

    private var parentDirectory: String? {
        guard let currentDirectory,
              let browserRootPath else {
            return nil
        }
        return CodexFileBrowserPath.parent(of: currentDirectory, constrainedTo: browserRootPath)
    }

    private var canNavigateToOriginalProjectDirectory: Bool {
        guard let currentDirectory,
              let initialDirectoryPath else {
            return false
        }
        return currentDirectory != initialDirectoryPath
    }

    private var breadcrumbItems: [CodexFileBrowserBreadcrumb] {
        guard let currentDirectory,
              let browserRootPath else {
            return []
        }
        return CodexFileBrowserPath.breadcrumbs(of: currentDirectory, constrainedTo: browserRootPath)
    }

    private var instructionText: String {
        switch mode {
        case .insertReference:
            return "浏览 Mac 目录；点文件插入引用，点目录进入下一层"
        case .chooseCodexDefaultProject:
            return "浏览 Mac 目录；进入目标目录后点“使用当前目录”"
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .insertReference:
            return "路径"
        case .chooseCodexDefaultProject:
            return "默认路径"
        }
    }
}

// MARK: - 图片选择器
struct ImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
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
                                self?.parent.onImagePicked(image)
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
        let request = DeviceAuthStore.authorizedRequest(url: url)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "image_overlay") {
                    loadFailed = true
                    return
                }
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

private enum WatchRelayPayloadPolicy {
    static let messageCharacterLimit = 800

    static func preview(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > messageCharacterLimit else { return trimmed }
        return String(trimmed.prefix(messageCharacterLimit)) + "…"
    }
}

final class WatchRelayCoordinator: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchRelayCoordinator()
    private static let stateRevisionDefaultsKey = "iterate.watch.relay.state_revision"

    typealias ActionHandler = (
        _ action: String,
        _ userInput: String,
        _ selectedOptions: [String],
        _ projectPath: String?,
        _ requestId: String?
    ) -> Void

    var onAction: ActionHandler?

    @Published private(set) var isReachable = false

    private var lastState: [String: Any] = [:]
    private var lastStateRevision = (
        UserDefaults.standard.object(forKey: WatchRelayCoordinator.stateRevisionDefaultsKey) as? NSNumber
    )?.uint64Value ?? 0

    override init() {
        super.init()
        activateSessionIfNeeded()
    }

    func updateState(
        status: String,
        projectName: String,
        message: String,
        projectPath: String?,
        requestId: String?,
        options: [String],
        isConnected: Bool,
        isWaiting: Bool,
        reason: String
    ) {
        let stateID = UUID().uuidString
        let stateRevision = nextStateRevision()
        var state: [String: Any] = [
            "type": "state",
            "state_id": stateID,
            "state_revision": NSNumber(value: stateRevision),
            "status": status,
            "project_name": projectName,
            "message": WatchRelayPayloadPolicy.preview(message),
            "options": options,
            "is_connected": isConnected,
            "is_waiting": isWaiting,
            "reason": reason,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        if let projectPath, !projectPath.isEmpty {
            state["project_path"] = projectPath
        }
        if let requestId, !requestId.isEmpty {
            state["request_id"] = requestId
        }

        lastState = state
        sendState(state)
    }

    private func nextStateRevision() -> UInt64 {
        let wallClockMilliseconds = UInt64(max(0, Date().timeIntervalSince1970 * 1_000))
        let incrementedRevision = lastStateRevision == UInt64.max
            ? lastStateRevision
            : lastStateRevision + 1
        lastStateRevision = max(incrementedRevision, wallClockMilliseconds)
        UserDefaults.standard.set(
            NSNumber(value: lastStateRevision),
            forKey: WatchRelayCoordinator.stateRevisionDefaultsKey
        )
        return lastStateRevision
    }

    func sendProjects(_ projects: [[String: Any]], reason: String) {
        let payload: [String: Any] = [
            "type": "projects",
            "projects": projects,
            "reason": reason,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        do {
            try session.updateApplicationContext(payload)
        } catch {
            print("[WatchRelay] update projects context failed: \(error.localizedDescription)")
        }
        guard session.isReachable else { return }
        session.sendMessage(payload, replyHandler: nil) { error in
            print("[WatchRelay] send projects failed: \(error.localizedDescription)")
        }
    }

    func forwardNotification(
        title: String,
        body: String,
        userInfo: [AnyHashable: Any],
        reason: String
    ) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            print("[WatchRelay] skip notification forward, session not activated reason=\(reason)")
            return
        }

        var payload: [String: Any] = [
            "type": "notification",
            "title": title,
            "body": body,
            "reason": reason,
            "forwarded_at": ISO8601DateFormatter().string(from: Date()),
            "notifications_enabled": UserDefaults.standard.object(forKey: WebSocketManager.notificationsEnabledDefaultsKey) as? Bool ?? true
        ]
        copyString("source", from: userInfo, to: &payload)
        copyString("request_id", from: userInfo, to: &payload)
        copyString("project_path", from: userInfo, to: &payload)
        copyString("expires_at", from: userInfo, to: &payload)
        copyString("sent_at", from: userInfo, to: &payload)

        #if !targetEnvironment(simulator)
        _ = session.transferUserInfo(payload)
        #endif

        guard session.isReachable else { return }
        session.sendMessage(payload, replyHandler: nil) { error in
            print("[WatchRelay] send notification failed: \(error.localizedDescription)")
        }
    }

    private func copyString(_ key: String, from source: [AnyHashable: Any], to payload: inout [String: Any]) {
        guard let value = source[key] as? String, !value.isEmpty else { return }
        payload[key] = value
    }

    private func activateSessionIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.delegate == nil else {
            isReachable = session.isReachable
            return
        }
        session.delegate = self
        session.activate()
    }

    private func sendState(_ state: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        do {
            try session.updateApplicationContext(state)
        } catch {
            print("[WatchRelay] update context failed: \(error.localizedDescription)")
        }

        guard session.isReachable else { return }
        session.sendMessage(state, replyHandler: nil) { error in
            print("[WatchRelay] send state failed: \(error.localizedDescription)")
        }
    }

    private func handleIncoming(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        if type == "request_state" {
            if !lastState.isEmpty {
                sendState(lastState)
            } else {
                onAction?("request_state", "", [], nil, nil)
            }
            return
        }

        guard type == "action" else { return }
        let action = message["action"] as? String ?? "continue"
        let userInput = message["user_input"] as? String ?? ""
        let selectedOptions = message["selected_options"] as? [String] ?? []
        let projectPath = message["project_path"] as? String
        let requestId = message["request_id"] as? String
        onAction?(action, userInput, selectedOptions, projectPath, requestId)
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
        if let error {
            print("[WatchRelay] activation failed: \(error.localizedDescription)")
        }
        if activationState == .activated, !lastState.isEmpty {
            sendState(lastState)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
        if session.isReachable, !lastState.isEmpty {
            sendState(lastState)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.handleIncoming(message)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
