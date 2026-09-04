import SwiftUI
import UIKit

struct MarkdownView: View {
    let text: String
    let theme: IterateTheme
    var onImageTap: ((URL) -> Void)? = nil
    private var bridgeBaseURL: String? {
        BridgeAuthStore.activeBaseURL()?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseMarkdown(text), id: \.id) { element in
                renderElement(element)
            }
        }
    }

    struct MarkdownElement: Identifiable {
        let id = UUID()
        let type: ElementType
        let content: String
        let level: Int
        let tableData: TableData?

        init(type: ElementType, content: String, level: Int, tableData: TableData? = nil) {
            self.type = type
            self.content = content
            self.level = level
            self.tableData = tableData
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
        }
    }

    struct TableData {
        let headers: [String]
        let rows: [[String]]
    }

    func parseMarkdown(_ text: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        let lines = text.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeBlockContent = ""
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("```") {
                if inCodeBlock {
                    elements.append(MarkdownElement(type: .codeBlock, content: codeBlockContent, level: 0))
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

                    elements.append(
                        MarkdownElement(
                            type: .table,
                            content: "",
                            level: 0,
                            tableData: TableData(headers: headers, rows: rows)
                        )
                    )
                    continue
                }
            }

            // 检查图片语法 ![alt](url)
            if let imageURL = parseImageLine(line) {
                elements.append(MarkdownElement(type: .image, content: imageURL, level: 0))
            } else if line.hasPrefix("### ") {
                elements.append(MarkdownElement(type: .heading, content: String(line.dropFirst(4)), level: 3))
            } else if line.hasPrefix("## ") {
                elements.append(MarkdownElement(type: .heading, content: String(line.dropFirst(3)), level: 2))
            } else if line.hasPrefix("# ") {
                elements.append(MarkdownElement(type: .heading, content: String(line.dropFirst(2)), level: 1))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                elements.append(MarkdownElement(type: .listItem, content: String(line.dropFirst(2)), level: 0))
            } else if line.hasPrefix("> ") {
                elements.append(MarkdownElement(type: .blockquote, content: String(line.dropFirst(2)), level: 0))
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                elements.append(MarkdownElement(type: .paragraph, content: line, level: 0))
            }
            index += 1
        }

        return elements
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
            guard let bridgeBaseURL else { return nil }
            url = bridgeBaseURL + url
        }
        return url
    }

    @ViewBuilder
    func renderElement(_ element: MarkdownElement) -> some View {
        switch element.type {
        case .heading:
            Text(element.content)
                .font(.system(size: element.level == 1 ? 18 : (element.level == 2 ? 16 : 14), weight: .semibold))
                .foregroundColor(theme.text)
        case .paragraph:
            Text(inlineAttributedString(element.content))
                .foregroundColor(theme.text)
                .lineSpacing(4)
        case .codeBlock:
            Text(element.content)
                .font(.system(size: 13, design: .monospaced))
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
                Text(inlineAttributedString(element.content))
                    .foregroundColor(theme.text)
                    .lineSpacing(4)
            }
        case .blockquote:
            HStack(spacing: 8) {
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: 3)
                Text(element.content)
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
                    .italic()
            }
            .padding(.vertical, 4)
        case .inlineCode:
            Text(element.content)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.card)
                .cornerRadius(4)
        case .table:
            if let tableData = element.tableData {
                renderTable(tableData)
            }
        case .image:
            if let url = URL(string: element.content) {
                AuthenticatedRemoteImage(url: url, theme: theme, onTap: { onImageTap?(url) })
            }
        }
    }

    @ViewBuilder
    func renderTable(_ tableData: TableData) -> some View {
        let columnCount = max(tableData.headers.count, 1)
        let availableWidth = max(UIScreen.main.bounds.width - 48, 280)
        let columnWidth = max(96, floor(availableWidth / CGFloat(columnCount)))
        let tableMinWidth = columnWidth * CGFloat(columnCount)

        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(tableData.headers.indices, id: \.self) { columnIndex in
                        Text(inlineAttributedString(tableData.headers[columnIndex], baseSize: 13))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(theme.text)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(width: columnWidth, alignment: .leading)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                            .background(theme.backgroundSecondary)
                            .overlay(alignment: .trailing) {
                                if columnIndex < tableData.headers.count - 1 {
                                    Rectangle()
                                        .fill(theme.border)
                                        .frame(width: 1)
                                }
                            }
                    }
                }

                Divider()
                    .background(theme.border)

                ForEach(tableData.rows.indices, id: \.self) { rowIndex in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(tableData.headers.indices, id: \.self) { columnIndex in
                            let cell = columnIndex < tableData.rows[rowIndex].count ? tableData.rows[rowIndex][columnIndex] : ""
                            Text(inlineAttributedString(cell, baseSize: 13))
                                .foregroundColor(theme.text)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(width: columnWidth, alignment: .leading)
                                .frame(maxHeight: .infinity, alignment: .topLeading)
                                .background(rowIndex.isMultiple(of: 2) ? theme.card : theme.backgroundSecondary.opacity(0.45))
                                .overlay(alignment: .trailing) {
                                    if columnIndex < tableData.headers.count - 1 {
                                        Rectangle()
                                            .fill(theme.border)
                                            .frame(width: 1)
                                    }
                                }
                        }
                    }
                    if rowIndex < tableData.rows.count - 1 {
                        Divider()
                            .background(theme.border)
                    }
                }
            }
            .frame(minWidth: tableMinWidth, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.border, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private final class AuthenticatedImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var failed = false
    private var task: URLSessionDataTask?

    func load(_ url: URL) {
        guard task == nil else { return }
        task = URLSession.shared.dataTask(with: BridgeAuthStore.authorizedRequest(for: url)) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data {
                    self.image = UIImage(data: data)
                }
                self.failed = self.image == nil
            }
        }
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

private struct AuthenticatedRemoteImage: View {
    let url: URL
    let theme: IterateTheme
    let onTap: () -> Void
    @StateObject private var loader = AuthenticatedImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(8)
                    .onTapGesture(perform: onTap)
            } else if loader.failed {
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
        .onAppear { loader.load(url) }
        .onDisappear { loader.cancel() }
    }
}
