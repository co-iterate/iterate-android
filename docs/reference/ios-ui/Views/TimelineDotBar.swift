import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private struct TimelineTooltipDotFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct TimelineDotBar: View {
    let nodes: [TimelineNode]
    let currentNodeId: String?
    let theme: IterateTheme
    let onDotTap: (String) -> Void

    @State private var tooltipNode: TimelineNode? = nil
    @State private var tooltipDotMidY: CGFloat? = nil
    @State private var dotFrames: [String: CGRect] = [:]
    @State private var lastScrubbedNodeId: String? = nil
    @State private var isScrubbing = false
    @State private var tooltipHideWorkItem: DispatchWorkItem? = nil
#if canImport(UIKit)
    @State private var impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
#endif

    private let barWidth: CGFloat = 32
    private let dotSize: CGFloat = 12
    private let connectorHeight: CGFloat = 9
    private let coordinateSpaceName = "timelineDotBarSpace"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                        dotRow(for: node, at: index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                cancelTooltipHide()
                                if tooltipNode?.id == node.id {
                                    // 再次点击同一节点：关闭 tooltip
                                    withAnimation { tooltipNode = nil; tooltipDotMidY = nil }
                                } else {
                                    // 点击新节点：显示 tooltip（不自动消失）
                                    tooltipNode = node
                                    tooltipDotMidY = dotFrames[node.id]?.midY
                                    if !node.content.isEmpty {
                                        onDotTap(node.content)
                                    }
                                }
                            }
                            .id(node.id)
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollDisabled(isScrubbing)
        }
        .frame(width: barWidth)
        .background(
            ScrollViewLongPressScrubBridge(
                onScrubbingStart: { y in
                    beginScrubbing(at: y)
                },
                onScrubbingMove: { y in
                    updateScrubbing(at: y)
                },
                onScrubbingEnd: {
                    endScrubbing()
                }
            )
        )
        .coordinateSpace(name: coordinateSpaceName)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.border.opacity(0.9), lineWidth: 1)
        )
        .overlay(
            Group {
                if let node = tooltipNode, !node.content.isEmpty, let tooltipY = tooltipDotMidY {
                    tooltipView(text: node.content, nodeType: node.nodeType)
                        .alignmentGuide(.top) { dimensions in
                            dimensions[VerticalAlignment.center]
                        }
                        .offset(x: -(barWidth / 2 + 8), y: tooltipY)
                        .transition(.opacity)
                        .onTapGesture {
                            cancelTooltipHide()
                            withAnimation { tooltipNode = nil }
                        }
                }
            },
            alignment: .topTrailing
        )
        .onPreferenceChange(TimelineTooltipDotFramePreferenceKey.self) { frames in
            dotFrames = frames
            guard let nodeId = tooltipNode?.id else {
                tooltipDotMidY = nil
                return
            }
            tooltipDotMidY = frames[nodeId]?.midY
        }
        .onChange(of: tooltipNode?.id) { nodeId in
            tooltipDotMidY = nodeId.flatMap { dotFrames[$0]?.midY }
        }
        .zIndex(tooltipNode != nil ? 999 : 0)
    }

    @ViewBuilder
    private func tooltipView(text: String, nodeType: String) -> some View {
        let preview = text.count > 80 ? String(text.prefix(80)) + "..." : text
        let typeLabel = nodeType == "user" ? "用户" : "助手"
        VStack(alignment: .leading, spacing: 4) {
            Text(typeLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.72))
            Text(preview)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(hex: "#1a1a1a"))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.4), radius: 6, x: -2, y: 2)
        .frame(width: 220, alignment: .trailing)
    }

    @ViewBuilder
    private func dotRow(for node: TimelineNode, at index: Int) -> some View {
        let isActive = node.id == currentNodeId

        VStack(spacing: 0) {
            connector(isVisible: index > 0)

            Circle()
                .fill(dotColor(for: node))
                .frame(width: dotSize, height: dotSize)
                .overlay(
                    Circle()
                        .stroke(theme.accent, lineWidth: isActive ? 1.5 : 0)
                )
                .scaleEffect(isActive ? 1.2 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isActive)

            connector(isVisible: index < nodes.count - 1)
        }
        .padding(.horizontal, (barWidth - dotSize) / 2)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: TimelineTooltipDotFramePreferenceKey.self,
                    value: [node.id: geometry.frame(in: .named(coordinateSpaceName))]
                )
            }
        )
    }


    private func beginScrubbing(at y: CGFloat) {
        guard !isScrubbing else { return }
        isScrubbing = true
        cancelTooltipHide()
        lastScrubbedNodeId = nil
        prepareHaptics()
        updateScrubbing(at: y)
    }

    private func updateScrubbing(at y: CGFloat) {
        guard let node = nearestNode(to: y) else { return }
        selectTooltipNode(node)
    }

    private func nearestNode(to y: CGFloat) -> TimelineNode? {
        nodes
            .compactMap { node -> (node: TimelineNode, distance: CGFloat)? in
                guard let frame = dotFrames[node.id] else { return nil }
                return (node: node, distance: abs(frame.midY - y))
            }
            .min(by: { $0.distance < $1.distance })?
            .node
    }

    private func selectTooltipNode(_ node: TimelineNode) {
        if lastScrubbedNodeId != node.id {
            triggerHaptic()
            lastScrubbedNodeId = node.id
        }
        tooltipNode = node
        tooltipDotMidY = dotFrames[node.id]?.midY
    }

    private func endScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        lastScrubbedNodeId = nil
        scheduleTooltipHide()
    }

    private func scheduleTooltipHide() {
        tooltipHideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation {
                tooltipNode = nil
                tooltipDotMidY = nil
            }
        }
        tooltipHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func cancelTooltipHide() {
        tooltipHideWorkItem?.cancel()
        tooltipHideWorkItem = nil
    }

    private func prepareHaptics() {
#if canImport(UIKit)
        impactFeedbackGenerator.prepare()
#endif
    }

    private func triggerHaptic() {
#if canImport(UIKit)
        impactFeedbackGenerator.impactOccurred()
        impactFeedbackGenerator.prepare()
#endif
    }

    @ViewBuilder
    private func connector(isVisible: Bool) -> some View {
        if isVisible {
            Rectangle()
                .fill(Color(hex: "#d1d5db"))
                .frame(width: 1, height: connectorHeight)
        } else {
            Color.clear
                .frame(width: 1, height: connectorHeight)
        }
    }

    private func dotColor(for node: TimelineNode) -> Color {
        // 与桌面端完全一致：用户 #9ca3af，助手 #374151
        if node.nodeType == "user" {
            return Color(hex: "#9ca3af")
        }
        return Color(hex: "#374151")
    }
}

// MARK: - UIKit Long Press Bridge

#if canImport(UIKit)
struct ScrollViewLongPressScrubBridge: UIViewRepresentable {
    let onScrubbingStart: (CGFloat) -> Void
    let onScrubbingMove: (CGFloat) -> Void
    let onScrubbingEnd: () -> Void

    func makeUIView(context: Context) -> ScrubBridgeHostView {
        let view = ScrubBridgeHostView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        context.coordinator.hostView = view
        context.coordinator.attachLongPressRecognizerIfNeeded()
        return view
    }

    func updateUIView(_ uiView: ScrubBridgeHostView, context: Context) {
        context.coordinator.onScrubbingStart = onScrubbingStart
        context.coordinator.onScrubbingMove = onScrubbingMove
        context.coordinator.onScrubbingEnd = onScrubbingEnd
        context.coordinator.hostView = uiView
        context.coordinator.attachLongPressRecognizerIfNeeded()
    }

    static func dismantleUIView(_ uiView: ScrubBridgeHostView, coordinator: Coordinator) {
        coordinator.detachLongPressRecognizer()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onScrubbingStart: onScrubbingStart,
            onScrubbingMove: onScrubbingMove,
            onScrubbingEnd: onScrubbingEnd
        )
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onScrubbingStart: (CGFloat) -> Void
        var onScrubbingMove: (CGFloat) -> Void
        var onScrubbingEnd: () -> Void
        weak var hostView: UIView?
        weak var attachedScrollView: UIScrollView?
        var longPressRecognizer: UILongPressGestureRecognizer?
        var isScrubbing = false

        init(onScrubbingStart: @escaping (CGFloat) -> Void,
             onScrubbingMove: @escaping (CGFloat) -> Void,
             onScrubbingEnd: @escaping () -> Void) {
            self.onScrubbingStart = onScrubbingStart
            self.onScrubbingMove = onScrubbingMove
            self.onScrubbingEnd = onScrubbingEnd
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        func attachLongPressRecognizerIfNeeded() {
            guard let hostView else { return }
            guard let scrollView = findTargetScrollView(from: hostView) else {
                DispatchQueue.main.async { [weak self] in
                    self?.attachLongPressRecognizerIfNeeded()
                }
                return
            }

            if attachedScrollView === scrollView {
                return
            }

            detachLongPressRecognizer()

            let recognizer = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleLongPress(_:))
            )
            recognizer.minimumPressDuration = 0.4
            recognizer.allowableMovement = 24
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)

            attachedScrollView = scrollView
            longPressRecognizer = recognizer
        }

        func detachLongPressRecognizer() {
            if let recognizer = longPressRecognizer {
                attachedScrollView?.removeGestureRecognizer(recognizer)
            }
            longPressRecognizer = nil
            attachedScrollView = nil
            isScrubbing = false
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let hostView else { return }
            let y = gesture.location(in: hostView).y

            switch gesture.state {
            case .began:
                isScrubbing = true
                onScrubbingStart(y)
                onScrubbingMove(y)
            case .changed:
                if isScrubbing {
                    onScrubbingMove(y)
                }
            case .ended, .cancelled, .failed:
                isScrubbing = false
                onScrubbingEnd()
            default:
                break
            }
        }

        private func findTargetScrollView(from hostView: UIView) -> UIScrollView? {
            var ancestor: UIView? = hostView.superview
            while let current = ancestor {
                var scrollViews: [UIScrollView] = []
                collectScrollViews(in: current, into: &scrollViews)

                let hostCenter = hostView.convert(
                    CGPoint(x: hostView.bounds.midX, y: hostView.bounds.midY),
                    to: current
                )
                if let matchedScrollView = scrollViews.first(where: { scrollView in
                    let scrollFrameInAncestor = scrollView.convert(scrollView.bounds, to: current)
                    return scrollFrameInAncestor.contains(hostCenter)
                }) {
                    return matchedScrollView
                }

                ancestor = current.superview
            }
            return nil
        }

        private func collectScrollViews(in root: UIView, into result: inout [UIScrollView]) {
            if let scrollView = root as? UIScrollView {
                result.append(scrollView)
            }
            for subview in root.subviews {
                collectScrollViews(in: subview, into: &result)
            }
        }
    }
}

final class ScrubBridgeHostView: UIView {
    weak var coordinator: ScrollViewLongPressScrubBridge.Coordinator?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        coordinator?.attachLongPressRecognizerIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        coordinator?.attachLongPressRecognizerIfNeeded()
    }
}
#endif
