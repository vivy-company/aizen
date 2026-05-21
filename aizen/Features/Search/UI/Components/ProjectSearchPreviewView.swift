import SwiftUI

struct ProjectSearchPreviewView: View {
    let preview: ProjectSearchPreview

    private struct ScrollTarget: Hashable {
        let path: String
        let line: Int
    }

    private var lines: [String] {
        let splitLines = preview.content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        return splitLines.isEmpty ? [""] : splitLines
    }

    private var targetLineNumber: Int? {
        preview.openRequest?.line
    }

    private var scrollTarget: ScrollTarget? {
        guard let targetLineNumber else { return nil }
        return ScrollTarget(path: preview.path, line: targetLineNumber)
    }

    private var lineNumberWidth: CGFloat {
        let largestLineNumber = max(lines.count, targetLineNumber ?? 1)
        return CGFloat(max(3, String(largestLineNumber).count)) * 8
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { offset, line in
                        lineRow(line: line, number: offset + 1)
                            .id(offset + 1)
                    }
                }
                .padding(.vertical, 10)
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.opacity(0.08))
            .textSelection(.disabled)
            .task(id: scrollTarget) {
                guard let scrollTarget else { return }
                proxy.scrollTo(scrollTarget.line, anchor: .center)
            }
        }
    }

    private func lineRow(line: String, number: Int) -> some View {
        let isTargetLine = number == targetLineNumber

        return HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(lineNumberColor(isTargetLine: isTargetLine))
                .frame(width: lineNumberWidth, alignment: .trailing)

            Text(attributedLine(line, number: number))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.86))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .background {
            if isTargetLine {
                Rectangle()
                    .fill(Color.white.opacity(0.055))
            }
        }
    }

    private func attributedLine(_ line: String, number: Int) -> AttributedString {
        let renderedLine = line.isEmpty ? " " : line
        var attributed = AttributedString(renderedLine)

        guard let highlightRange = highlightRange(in: line, number: number),
              let stringRange = Range(highlightRange, in: line),
              let lowerBound = AttributedString.Index(stringRange.lowerBound, within: attributed),
              let upperBound = AttributedString.Index(stringRange.upperBound, within: attributed) else {
            return attributed
        }

        attributed[lowerBound..<upperBound].backgroundColor = Color.accentColor.opacity(0.28)
        attributed[lowerBound..<upperBound].foregroundColor = Color.primary
        return attributed
    }

    private func lineNumberColor(isTargetLine: Bool) -> Color {
        isTargetLine ? Color.primary.opacity(0.78) : Color.secondary.opacity(0.56)
    }

    private func highlightRange(in line: String, number: Int) -> NSRange? {
        guard let request = preview.openRequest,
              let startLine = request.line else {
            return nil
        }

        let endLine = request.endLine ?? startLine
        guard number >= startLine, number <= endLine else {
            return nil
        }

        let lineLength = (line as NSString).length
        guard lineLength > 0 else {
            return nil
        }

        let startColumn = number == startLine
            ? max((request.column ?? 1) - 1, 0)
            : 0
        let endColumn = number == endLine
            ? max((request.endColumn ?? (request.column ?? 1)) - 1, startColumn + 1)
            : lineLength
        let location = min(startColumn, lineLength)
        let endLocation = min(max(endColumn, location + 1), lineLength)
        guard endLocation > location else {
            return nil
        }

        return NSRange(location: location, length: endLocation - location)
    }
}
