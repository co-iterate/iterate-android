import SwiftUI
import UIKit
import QuartzCore

private enum MarkdownInlineImageCache {
    static let shared = NSCache<NSURL, UIImage>()
}

private final class MarkdownParsedElementCacheEntry: NSObject {
    let sourceText: String
    let elements: [MarkdownView.MarkdownElement]

    init(sourceText: String, elements: [MarkdownView.MarkdownElement]) {
        self.sourceText = sourceText
        self.elements = elements
    }
}

private enum MarkdownParsedElementCache {
    static let shared: NSCache<NSString, MarkdownParsedElementCacheEntry> = {
        let cache = NSCache<NSString, MarkdownParsedElementCacheEntry>()
        cache.countLimit = 24
        return cache
    }()
}

struct MarkdownView: View, Equatable {
    let text: String
    let theme: IterateTheme
    var cacheKey: String? = nil
    var themeKey: String = "default"
    var onImageTap: ((URL) -> Void)? = nil
    var onQuoteSelection: ((String) -> Void)? = nil
    var onSearchSelection: ((String) -> Void)? = nil
    private var bridgeBaseURL: String { ServerConfig.currentHTTPBaseURL() }
    @State private var copiedCodeID: String?

    static func == (lhs: MarkdownView, rhs: MarkdownView) -> Bool {
        lhs.text == rhs.text
            && lhs.cacheKey == rhs.cacheKey
            && lhs.themeKey == rhs.themeKey
    }

    var body: some View {
        let parsedElements = cachedParsedElements(for: text, cacheKey: cacheKey)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parsedElements) { element in
                renderElement(element)
            }
        }
        .id(cacheKey ?? "uncached-markdown")
    }

    struct MarkdownElement: Identifiable {
        let id: String
        let type: ElementType
        let content: String
        let level: Int
        let tableData: TableData?
        let groupedElements: [MarkdownElement]

        init(
            id: String,
            type: ElementType,
            content: String,
            level: Int,
            tableData: TableData? = nil,
            groupedElements: [MarkdownElement] = []
        ) {
            self.id = id
            self.type = type
            self.content = content
            self.level = level
            self.tableData = tableData
            self.groupedElements = groupedElements
        }

        enum ElementType {
            case heading
            case paragraph
            case codeBlock
            case inlineCode
            case listItem
            case blockquote
            case image
            case table
            case textRun
        }
    }

    struct TableData {
        let headers: [String]
        let rows: [[String]]
    }

    private func stableElementID(
        index: Int,
        type: MarkdownElement.ElementType,
        level: Int
    ) -> String {
        "\(index)|\(String(describing: type))|\(level)"
    }

    private func cachedParsedElements(for text: String, cacheKey: String?) -> [MarkdownElement] {
        guard let cacheKey, !cacheKey.isEmpty else {
            return parseMarkdown(text)
        }

        let key = cacheKey as NSString
        if let cached = MarkdownParsedElementCache.shared.object(forKey: key),
           cached.sourceText == text {
            return cached.elements
        }

        let startedAt = CACurrentMediaTime()
        let parsed = parseMarkdown(text)
        MarkdownParsedElementCache.shared.setObject(
            MarkdownParsedElementCacheEntry(sourceText: text, elements: parsed),
            forKey: key
        )
#if DEBUG
        print(
            "[MarkdownPerf] parsed cache_key=\(cacheKey) chars=\(text.count) " +
            "elements=\(parsed.count) elapsed_ms=\(String(format: "%.1f", (CACurrentMediaTime() - startedAt) * 1000))"
        )
#endif
        return parsed
    }

    func parseMarkdown(_ text: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        let lines = text.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeBlockContent = ""
        var index = 0

        func appendElement(
            type: MarkdownElement.ElementType,
            content: String,
            level: Int,
            tableData: TableData? = nil
        ) {
            let elementIndex = elements.count
            elements.append(
                MarkdownElement(
                    id: stableElementID(
                        index: elementIndex,
                        type: type,
                        level: level
                    ),
                    type: type,
                    content: content,
                    level: level,
                    tableData: tableData
                )
            )
        }

        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("```") {
                if inCodeBlock {
                    appendElement(type: .codeBlock, content: codeBlockContent, level: 0)
                    codeBlockContent = ""
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                index += 1
                continue
            }

            if inCodeBlock {
                codeBlockContent += (codeBlockContent.isEmpty ? "" : "\n") + line
                index += 1
                continue
            }

            // GFM table:
            // | col1 | col2 |
            // |------|------|
            // | a    | b    |
            if isTableRowLine(line),
               index + 1 < lines.count,
               isTableSeparatorLine(lines[index + 1]) {
                let headers = parseTableCells(line)
                if !headers.isEmpty {
                    var rows: [[String]] = []
                    index += 2

                    while index < lines.count {
                        let rowLine = lines[index]
                        let trimmedRowLine = rowLine.trimmingCharacters(in: .whitespaces)
                        if trimmedRowLine.isEmpty || !isTableRowLine(rowLine) {
                            break
                        }
                        if isTableSeparatorLine(rowLine) {
                            index += 1
                            continue
                        }
                        let rowCells = normalizeTableRow(parseTableCells(rowLine), columnCount: headers.count)
                        rows.append(rowCells)
                        index += 1
                    }

                    appendElement(
                        type: .table,
                        content: "",
                        level: 0,
                        tableData: TableData(headers: headers, rows: rows)
                    )
                    continue
                }
            }

            // 检查图片语法 ![alt](url)
            if let imageURL = parseImageLine(line) {
                appendElement(type: .image, content: imageURL, level: 0)
            } else if line.hasPrefix("### ") {
                appendElement(type: .heading, content: String(line.dropFirst(4)), level: 3)
            } else if line.hasPrefix("## ") {
                appendElement(type: .heading, content: String(line.dropFirst(3)), level: 2)
            } else if line.hasPrefix("# ") {
                appendElement(type: .heading, content: String(line.dropFirst(2)), level: 1)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                appendElement(type: .listItem, content: String(line.dropFirst(2)), level: 0)
            } else if line.hasPrefix("> ") {
                appendElement(type: .blockquote, content: String(line.dropFirst(2)), level: 0)
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                appendElement(type: .paragraph, content: line, level: 0)
            }
            index += 1
        }

        return groupSelectableTextElements(elements)
    }

    private func groupSelectableTextElements(_ elements: [MarkdownElement]) -> [MarkdownElement] {
        var grouped: [MarkdownElement] = []
        var run: [MarkdownElement] = []

        func flushRun() {
            guard !run.isEmpty else { return }
            if run.count == 1 {
                grouped.append(run[0])
            } else if let first = run.first, let last = run.last {
                grouped.append(
                    MarkdownElement(
                        id: "text-run|\(first.id)|\(last.id)",
                        type: .textRun,
                        content: "",
                        level: 0,
                        groupedElements: run
                    )
                )
            }
            run.removeAll(keepingCapacity: true)
        }

        for element in elements {
            switch element.type {
            case .paragraph, .listItem:
                if parseStandaloneInlineCode(element.content) == nil {
                    run.append(element)
                } else {
                    flushRun()
                    grouped.append(element)
                }
            case .heading, .codeBlock, .blockquote, .inlineCode, .table, .image, .textRun:
                flushRun()
                grouped.append(element)
            }
        }
        flushRun()
        return grouped
    }

    func isTableRowLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.filter { $0 == "|" }.count >= 2
    }

    func parseTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    func isTableSeparatorLine(_ line: String) -> Bool {
        let cells = parseTableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell.replacingOccurrences(of: ":", with: "")
            return !stripped.isEmpty && stripped.allSatisfy { $0 == "-" }
        }
    }

    func normalizeTableRow(_ row: [String], columnCount: Int) -> [String] {
        var normalized = row
        if normalized.count < columnCount {
            normalized.append(contentsOf: Array(repeating: "", count: columnCount - normalized.count))
        } else if normalized.count > columnCount {
            normalized = Array(normalized.prefix(columnCount))
        }
        return normalized
    }

    func inlineAttributedString(_ text: String, baseSize: CGFloat = 14) -> AttributedString {
        let pattern = #"\*\*(.+?)\*\*|`([^`]+)`"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            var plain = AttributedString(text)
            plain.font = .system(size: baseSize)
            return plain
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        if matches.isEmpty {
            var plain = AttributedString(text)
            plain.font = .system(size: baseSize)
            return plain
        }

        var result = AttributedString()
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                let plain = nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                var plainPart = AttributedString(plain)
                plainPart.font = .system(size: baseSize)
                result.append(plainPart)
            }

            if match.range(at: 1).location != NSNotFound {
                let bold = nsText.substring(with: match.range(at: 1))
                var boldPart = AttributedString(bold)
                boldPart.font = .system(size: baseSize, weight: .semibold)
                result.append(boldPart)
            } else if match.range(at: 2).location != NSNotFound {
                let code = nsText.substring(with: match.range(at: 2))
                var codePart = AttributedString(code)
                codePart.font = .system(size: baseSize - 1, design: .monospaced)
                codePart.backgroundColor = theme.backgroundSecondary
                result.append(codePart)
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < nsText.length {
            let tail = nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor))
            var tailPart = AttributedString(tail)
            tailPart.font = .system(size: baseSize)
            result.append(tailPart)
        }

        return result
    }

    // 解析图片行：![alt](url) -> 返回完整 URL
    func parseImageLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("![") else { return nil }
        // 简单正则匹配 ![...](url)
        let pattern = #"^!\[([^\]]*)\]\(([^)]+)\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.numberOfRanges >= 3 else { return nil }
        let urlRange = Range(match.range(at: 2), in: trimmed)!
        var url = String(trimmed[urlRange])
        // 相对路径转绝对路径
        if url.hasPrefix("/") {
            url = bridgeBaseURL + url
        }
        return url
    }

    private func selectableText(
        _ attributedText: AttributedString,
        plainText: String,
        defaultFont: UIFont,
        foregroundColor: Color,
        lineSpacing: CGFloat = 0
    ) -> some View {
        SelectableMarkdownTextView(
            attributedText: attributedText,
            plainText: plainText,
            defaultFont: defaultFont,
            foregroundColor: UIColor(foregroundColor),
            lineSpacing: lineSpacing,
            onQuoteSelection: onQuoteSelection,
            onSearchSelection: onSearchSelection
        )
    }

    @ViewBuilder
    func renderElement(_ element: MarkdownElement) -> some View {
        switch element.type {
        case .heading:
            let fontSize: CGFloat = element.level == 1 ? 18 : (element.level == 2 ? 16 : 14)
            selectableText(
                AttributedString(element.content),
                plainText: element.content,
                defaultFont: .systemFont(ofSize: fontSize, weight: .semibold),
                foregroundColor: theme.text
            )
        case .paragraph:
            if let inlineCode = parseStandaloneInlineCode(element.content) {
                inlineCodeChip(inlineCode, id: element.id)
            } else {
                let attributedContent = inlineAttributedString(element.content)
                selectableText(
                    attributedContent,
                    plainText: NSAttributedString(attributedContent).string,
                    defaultFont: .systemFont(ofSize: 14),
                    foregroundColor: theme.text,
                    lineSpacing: 4
                )
            }
        case .codeBlock:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button {
                        copyCodeToClipboard(element.content, id: element.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedCodeID == element.id ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                            Text(copiedCodeID == element.id ? "已复制" : "复制")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.card)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                selectableText(
                    AttributedString(element.content),
                    plainText: element.content,
                    defaultFont: .monospacedSystemFont(ofSize: 13, weight: .regular),
                    foregroundColor: theme.text
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.backgroundSecondary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.border, lineWidth: 1)
            )
        case .listItem:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .foregroundColor(theme.text)
                if let inlineCode = parseStandaloneInlineCode(element.content) {
                    inlineCodeChip(inlineCode, id: element.id)
                } else {
                    let attributedContent = inlineAttributedString(element.content)
                    selectableText(
                        attributedContent,
                        plainText: NSAttributedString(attributedContent).string,
                        defaultFont: .systemFont(ofSize: 14),
                        foregroundColor: theme.text,
                        lineSpacing: 4
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .blockquote:
            HStack(spacing: 8) {
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: 3)
                if let inlineCode = parseStandaloneInlineCode(element.content) {
                    inlineCodeChip(inlineCode, id: element.id)
                } else {
                    selectableText(
                        AttributedString(element.content),
                        plainText: element.content,
                        defaultFont: .italicSystemFont(ofSize: 14),
                        foregroundColor: theme.textSecondary
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 4)
        case .inlineCode:
            selectableText(
                AttributedString(element.content),
                plainText: element.content,
                defaultFont: .monospacedSystemFont(ofSize: 13, weight: .regular),
                foregroundColor: theme.text
            )
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.card)
                .cornerRadius(4)
        case .textRun:
            renderSelectableTextRun(element.groupedElements)
        case .table:
            if let tableData = element.tableData {
                renderTable(tableData)
            }
        case .image:
            if let url = URL(string: element.content) {
                InlineMarkdownImageView(url: url, theme: theme) {
                    onImageTap?(url)
                }
            }
        }
    }

    private func renderSelectableTextRun(_ elements: [MarkdownElement]) -> some View {
        var attributedText = AttributedString()

        for (index, element) in elements.enumerated() {
            if index > 0 {
                let previousType = elements[index - 1].type
                let separator = previousType == .listItem && element.type == .listItem ? "\n" : "\n\n"
                var separatorText = AttributedString(separator)
                separatorText.font = .system(size: 14)
                attributedText.append(separatorText)
            }

            switch element.type {
            case .paragraph:
                attributedText.append(inlineAttributedString(element.content))
            case .listItem:
                var bullet = AttributedString("• ")
                bullet.font = .system(size: 14)
                attributedText.append(bullet)
                attributedText.append(inlineAttributedString(element.content))
            case .heading, .codeBlock, .blockquote, .inlineCode, .table, .image, .textRun:
                continue
            }
        }

        return selectableText(
            attributedText,
            plainText: NSAttributedString(attributedText).string,
            defaultFont: .systemFont(ofSize: 14),
            foregroundColor: theme.text,
            lineSpacing: 4
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyCodeToClipboard(_ content: String, id: String) {
        UIPasteboard.general.string = content
        copiedCodeID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedCodeID == id {
                copiedCodeID = nil
            }
        }
    }

    private func parseStandaloneInlineCode(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("`"), trimmed.hasSuffix("`"), trimmed.count >= 3 else {
            return nil
        }
        let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : inner
    }

    @ViewBuilder
    private func inlineCodeChip(_ code: String, id: String) -> some View {
        HStack(spacing: 6) {
            selectableText(
                AttributedString(code),
                plainText: code,
                defaultFont: .monospacedSystemFont(ofSize: 13, weight: .regular),
                foregroundColor: theme.text
            )

            Button {
                copyCodeToClipboard(code, id: id)
            } label: {
                Image(systemName: copiedCodeID == id ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(theme.backgroundSecondary)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    func renderTable(_ tableData: TableData) -> some View {
        if tableData.headers.count <= 2 {
            renderCompactTable(tableData)
        } else {
            renderStackedTable(tableData)
        }
    }

    @ViewBuilder
    private func renderCompactTable(_ tableData: TableData) -> some View {
        let hasSecondColumn = tableData.headers.count > 1
        let firstColumnWidth: CGFloat? = hasSecondColumn ? 118 : nil

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                compactTableCell(
                    tableData.headers.first ?? "",
                    isHeader: true,
                    width: firstColumnWidth,
                    background: theme.backgroundSecondary
                )

                if hasSecondColumn {
                    Divider()
                        .background(theme.border)
                    compactTableCell(
                        tableData.headers[1],
                        isHeader: true,
                        width: nil,
                        background: theme.backgroundSecondary
                    )
                }
            }

            if !tableData.rows.isEmpty {
                Divider()
                    .background(theme.border)
            }

            ForEach(tableData.rows.indices, id: \.self) { rowIndex in
                let rowBackground = rowIndex.isMultiple(of: 2) ? theme.card : theme.backgroundSecondary.opacity(0.45)

                HStack(alignment: .top, spacing: 0) {
                    compactTableCell(
                        tableData.rows[rowIndex].first ?? "",
                        isHeader: false,
                        width: firstColumnWidth,
                        background: rowBackground
                    )

                    if hasSecondColumn {
                        Divider()
                            .background(theme.border)
                        compactTableCell(
                            tableData.rows[rowIndex].count > 1 ? tableData.rows[rowIndex][1] : "",
                            isHeader: false,
                            width: nil,
                            background: rowBackground
                        )
                    }
                }

                if rowIndex < tableData.rows.count - 1 {
                    Divider()
                        .background(theme.border)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func compactTableCell(
        _ text: String,
        isHeader: Bool,
        width: CGFloat?,
        background: Color
    ) -> some View {
        let attributedContent = inlineAttributedString(text, baseSize: 13)
        return selectableText(
            attributedContent,
            plainText: NSAttributedString(attributedContent).string,
            defaultFont: .systemFont(ofSize: 13, weight: isHeader ? .semibold : .regular),
            foregroundColor: theme.text
        )
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(background)
    }

    private func renderStackedTable(_ tableData: TableData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tableData.rows.indices, id: \.self) { rowIndex in
                let rowBackground = rowIndex.isMultiple(of: 2) ? theme.card : theme.backgroundSecondary.opacity(0.45)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tableData.headers.indices, id: \.self) { columnIndex in
                        let cell = columnIndex < tableData.rows[rowIndex].count ? tableData.rows[rowIndex][columnIndex] : ""
                        let attributedHeader = inlineAttributedString(tableData.headers[columnIndex], baseSize: 12)
                        let attributedCell = inlineAttributedString(cell, baseSize: 13)
                        HStack(alignment: .top, spacing: 10) {
                            selectableText(
                                attributedHeader,
                                plainText: NSAttributedString(attributedHeader).string,
                                defaultFont: .systemFont(ofSize: 12, weight: .semibold),
                                foregroundColor: theme.textSecondary
                            )
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: 86, alignment: .leading)

                            selectableText(
                                attributedCell,
                                plainText: NSAttributedString(attributedCell).string,
                                defaultFont: .systemFont(ofSize: 13),
                                foregroundColor: theme.text
                            )
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(rowBackground)

                if rowIndex < tableData.rows.count - 1 {
                    Divider()
                        .background(theme.border)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.border, lineWidth: 1)
        )
    }
}

private struct SelectableMarkdownTextView: UIViewRepresentable {
    let attributedText: AttributedString
    let plainText: String
    let defaultFont: UIFont
    let foregroundColor: UIColor
    let lineSpacing: CGFloat
    let onQuoteSelection: ((String) -> Void)?
    let onSearchSelection: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onQuoteSelection: onQuoteSelection,
            onSearchSelection: onSearchSelection
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.isAccessibilityElement = true
        textView.accessibilityLabel = plainText
        textView.accessibilityTraits = .staticText
        textView.attributedText = resolvedAttributedText()
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onQuoteSelection = onQuoteSelection
        context.coordinator.onSearchSelection = onSearchSelection

        let startedAt = CACurrentMediaTime()
        let resolvedText = resolvedAttributedText()
#if DEBUG
        let elapsedMs = (CACurrentMediaTime() - startedAt) * 1_000
        if elapsedMs >= 2 {
            print(
                "[MarkdownPerf] resolved-attributed chars=\(resolvedText.length) " +
                "elapsed_ms=\(String(format: "%.1f", elapsedMs))"
            )
        }
#endif
        if !textView.attributedText.isEqual(to: resolvedText) {
            let previousSelection = textView.selectedRange
            textView.attributedText = resolvedText
            if NSMaxRange(previousSelection) <= resolvedText.length {
                textView.selectedRange = previousSelection
            }
            textView.invalidateIntrinsicContentSize()
            textView.setNeedsLayout()
        }

        textView.accessibilityLabel = plainText
        textView.accessibilityTraits = .staticText
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return nil
        }

        let measured = uiView.sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(measured.height))
    }

    private func resolvedAttributedText() -> NSAttributedString {
        let resolved = NSMutableAttributedString(attributedString: NSAttributedString(attributedText))
        let fullRange = NSRange(location: 0, length: resolved.length)
        guard fullRange.length > 0 else { return resolved }

        var missingFontRanges: [NSRange] = []
        resolved.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if value == nil {
                missingFontRanges.append(range)
            }
        }
        for range in missingFontRanges {
            resolved.addAttribute(.font, value: defaultFont, range: range)
        }
        resolved.addAttribute(.foregroundColor, value: foregroundColor, range: fullRange)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = lineSpacing
        resolved.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        return resolved
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onQuoteSelection: ((String) -> Void)?
        var onSearchSelection: ((String) -> Void)?

        init(
            onQuoteSelection: ((String) -> Void)?,
            onSearchSelection: ((String) -> Void)?
        ) {
            self.onQuoteSelection = onQuoteSelection
            self.onSearchSelection = onSearchSelection
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard let onQuoteSelection,
                  onSearchSelection != nil,
                  range.location != NSNotFound,
                  range.length > 0,
                  NSMaxRange(range) <= (textView.text as NSString).length else {
                return nil
            }

            let selectedText = (textView.text as NSString).substring(with: range)
            guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let copyAction = UIAction(
                title: "Copy",
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in
                UIPasteboard.general.string = selectedText
            }
            let quoteAction = UIAction(
                title: "引用",
                image: UIImage(systemName: "text.quote")
            ) { _ in
                onQuoteSelection(selectedText)
            }
            let searchAction = UIAction(
                title: "Search",
                image: UIImage(systemName: "magnifyingglass")
            ) { _ in
                self.onSearchSelection?(selectedText)
            }
            let filteredSystemActions = filterSystemActions(suggestedActions)
            return UIMenu(children: [copyAction, quoteAction, searchAction] + filteredSystemActions)
        }

        private func filterSystemActions(_ actions: [UIMenuElement]) -> [UIMenuElement] {
            actions.compactMap(filterSystemAction)
        }

        private func filterSystemAction(_ element: UIMenuElement) -> UIMenuElement? {
            if let command = element as? UICommand,
               command.action == #selector(UIResponderStandardEditActions.copy(_:)) {
                return nil
            }

            if let title = visibleTitle(of: element),
               title.trimmingCharacters(in: .whitespacesAndNewlines)
                   .caseInsensitiveCompare("Look Up") == .orderedSame {
                return nil
            }

            guard let menu = element as? UIMenu else {
                return element
            }

            let filteredChildren = filterSystemActions(menu.children)
            guard !filteredChildren.isEmpty else { return nil }
            return menu.replacingChildren(filteredChildren)
        }

        private func visibleTitle(of element: UIMenuElement) -> String? {
            if let action = element as? UIAction {
                return action.title
            }
            if let command = element as? UICommand {
                return command.title
            }
            if let menu = element as? UIMenu {
                return menu.title
            }
            return nil
        }
    }
}

private struct InlineMarkdownImageView: View {
    let url: URL
    let theme: IterateTheme
    let onTap: () -> Void

    @State private var loadedImage: UIImage? = nil
    @State private var loadFailed = false
    @State private var downloadTask: URLSessionDataTask? = nil

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(8)
                    .onTapGesture(perform: onTap)
            } else if loadFailed {
                HStack {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text("图片加载失败")
                        .font(.system(size: 12))
                }
                .foregroundColor(theme.textSecondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
            }
        }
        .onAppear {
            loadImageIfNeeded()
        }
        .onDisappear {
            if loadedImage == nil {
                downloadTask?.cancel()
                downloadTask = nil
            }
        }
    }

    private func loadImageIfNeeded() {
        if let cached = MarkdownInlineImageCache.shared.object(forKey: url as NSURL) {
            loadedImage = cached
            return
        }

        guard downloadTask == nil else { return }
        loadFailed = false

        let request = DeviceAuthStore.authorizedRequest(url: url)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                downloadTask = nil
                if DeviceAuthStore.clearAuthIfUnauthorized(response: response, data: data, context: "markdown_image") {
                    loadFailed = true
                    return
                }
                if let data, let image = UIImage(data: data) {
                    MarkdownInlineImageCache.shared.setObject(image, forKey: url as NSURL)
                    loadedImage = image
                    loadFailed = false
                } else if error != nil || data != nil {
                    loadFailed = true
                }
            }
        }
        downloadTask = task
        task.resume()
    }
}
