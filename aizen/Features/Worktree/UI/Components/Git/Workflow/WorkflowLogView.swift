//
//  WorkflowLogView.swift
//  aizen
//
//  NSTableView-based log viewer for workflow logs with collapsible groups
//

import SwiftUI
import AppKit

// MARK: - NSViewRepresentable Log Table

struct WorkflowLogTableView: NSViewRepresentable {
    let logs: String
    let structuredLogs: WorkflowLogs?
    let fontSize: CGFloat
    let provider: WorkflowProvider
    @Binding var showTimestamps: Bool
    var onCoordinatorReady: ((Coordinator) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        onCoordinatorReady?(context.coordinator)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = CopyableTableView()
        tableView.copyProvider = context.coordinator
        context.coordinator.tableView = tableView

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("LogColumn"))
        column.minWidth = 100
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        // Make column fill available width
        tableView.sizeLastColumnToFit()

        tableView.headerView = nil
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = NSColor.textBackgroundColor
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.style = .plain
        tableView.gridStyleMask = []
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        // Observe frame changes to recalculate row heights
        context.coordinator.observeFrameChanges(tableView)

        scrollView.documentView = tableView

        // Parse logs in background
        context.coordinator.parseLogs(logs, structuredLogs: structuredLogs, fontSize: fontSize, showTimestamps: showTimestamps, provider: provider)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if context.coordinator.currentLogs != logs {
            context.coordinator.parseLogs(logs, structuredLogs: structuredLogs, fontSize: fontSize, showTimestamps: showTimestamps, provider: provider)
        }
        if context.coordinator.showTimestamps != showTimestamps {
            context.coordinator.showTimestamps = showTimestamps
            context.coordinator.tableView?.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, CopyableTableViewProvider {
        weak var tableView: NSTableView?
        var steps: [LogStep] = []
        var displayRows: [LogRow] = []
        var currentLogs: String = ""
        var fontSize: CGFloat = 11
        var showTimestamps: Bool = false

        private var parseTask: Task<Void, Never>?

        func parseLogs(_ logs: String, structuredLogs: WorkflowLogs? = nil, fontSize: CGFloat, showTimestamps: Bool, provider: WorkflowProvider = .github) {
            currentLogs = logs
            self.fontSize = fontSize
            self.showTimestamps = showTimestamps

            parseTask?.cancel()
            let logsSnapshot = logs
            let structuredSnapshot = structuredLogs
            let fontSizeSnapshot = fontSize
            let providerSnapshot = provider

            parseTask = Task.detached(priority: .userInitiated) {
                let parsed: [LogStep]
                if let structured = structuredSnapshot, !structured.lines.isEmpty {
                    parsed = Self.parseStructuredLogs(structured, fontSize: fontSizeSnapshot)
                } else {
                    parsed = Self.parseLogSteps(logsSnapshot, fontSize: fontSizeSnapshot, provider: providerSnapshot)
                }

                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.steps = parsed
                    self.rebuildDisplayRows()
                    self.tableView?.reloadData()

                    // Recalculate heights after layout settles
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        self?.recalculateAllHeights()
                    }
                }
            }
        }

        private func recalculateAllHeights() {
            guard let tableView = tableView, displayRows.count > 0 else { return }
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<displayRows.count))
        }

        nonisolated private static func parseStructuredLogs(_ logs: WorkflowLogs, fontSize: CGFloat) -> [LogStep] {
            var steps: [LogStep] = []
            var currentStepName = ""
            var currentGroup: LogGroup?
            var groupId = 0
            var lineId = 0
            var stepId = 0
            var currentStyle = ANSITextStyle()
            var lastGroupTitle = ""

            for logLine in logs.lines {
                let stepName = logLine.stepName

                // Handle step transitions
                if stepName != currentStepName {
                    // Save current group to previous step before transitioning
                    if let group = currentGroup, !group.lines.isEmpty, !steps.isEmpty {
                        steps[steps.count - 1].groups.append(group)
                        currentGroup = nil
                    }

                    currentStepName = stepName
                    steps.append(LogStep(id: stepId, name: stepName, groups: [], isExpanded: false))
                    stepId += 1
                }

                let currentStepIdx = steps.isEmpty ? nil : steps.count - 1

                // Check for group markers
                if logLine.isGroupStart {
                    // Save current group
                    if let group = currentGroup, !group.lines.isEmpty, let stepIdx = currentStepIdx {
                        steps[stepIdx].groups.append(group)
                    }

                    let title = logLine.groupName ?? "Output"

                    // If this is "Output", merge with previous group instead of creating new one
                    if title == "Output" && !lastGroupTitle.isEmpty {
                        if let stepIdx = currentStepIdx, !steps[stepIdx].groups.isEmpty {
                            let lastIdx = steps[stepIdx].groups.count - 1
                            currentGroup = steps[stepIdx].groups[lastIdx]
                            steps[stepIdx].groups.removeLast()
                        } else {
                            currentGroup = LogGroup(id: groupId, title: lastGroupTitle, lines: [], isExpanded: false)
                            groupId += 1
                        }
                    } else {
                        currentGroup = LogGroup(id: groupId, title: title, lines: [], isExpanded: false)
                        lastGroupTitle = title
                        groupId += 1
                    }
                } else if logLine.isGroupEnd {
                    if let group = currentGroup, let stepIdx = currentStepIdx {
                        steps[stepIdx].groups.append(group)
                        currentGroup = nil
                    }
                } else if !logLine.content.trimmingCharacters(in: .whitespaces).isEmpty {
                    let (attributed, newStyle) = parseLineToAttributedString(logLine.content, style: currentStyle, fontSize: fontSize)
                    currentStyle = newStyle

                    if currentGroup != nil {
                        currentGroup?.lines.append((id: lineId, raw: logLine.content, attributed: attributed))
                    } else if let stepIdx = currentStepIdx {
                        if steps[stepIdx].groups.isEmpty || !steps[stepIdx].groups.last!.title.isEmpty {
                            currentGroup = LogGroup(id: groupId, title: "", lines: [], isExpanded: true)
                            groupId += 1
                        } else {
                            currentGroup = steps[stepIdx].groups.removeLast()
                        }
                        currentGroup?.lines.append((id: lineId, raw: logLine.content, attributed: attributed))
                    }
                    lineId += 1
                }
            }

            // Save final group
            if let group = currentGroup, !group.lines.isEmpty, !steps.isEmpty {
                steps[steps.count - 1].groups.append(group)
            }

            return steps.filter { !$0.groups.isEmpty || $0.groups.contains { !$0.lines.isEmpty } }
        }

        nonisolated private static func parseLogSteps(_ text: String, fontSize: CGFloat, provider: WorkflowProvider = .github) -> [LogStep] {
            let lines = text.components(separatedBy: "\n")
            var steps: [LogStep] = []
            var stepNameCounts: [String: Int] = [:] // track occurrences of each step name
            var currentStepName = "" // raw step name from current line
            var currentGroup: LogGroup?
            var groupId = 0
            var lineId = 0
            var stepId = 0
            var currentStyle = ANSITextStyle()
            var lastGroupTitle = ""

            // For GitLab (plain text logs), parse section markers into collapsible groups
            if provider == .gitlab {
                return parseGitLabLogs(lines, fontSize: fontSize)
            }

            // GitHub Actions format parsing
            for line in lines {
                // Extract step name from log line format
                let (extractedStep, message) = extractStepAndMessage(line)

                // Handle step transitions
                if !extractedStep.isEmpty && extractedStep != currentStepName {
                    // Save current group to previous step before transitioning
                    if let group = currentGroup, !group.lines.isEmpty, !steps.isEmpty {
                        steps[steps.count - 1].groups.append(group)
                        currentGroup = nil
                    }

                    currentStepName = extractedStep

                    // Always create a new step when the name changes
                    let count = stepNameCounts[extractedStep, default: 0]
                    stepNameCounts[extractedStep] = count + 1

                    let displayName = count > 0 ? "\(extractedStep) (\(count + 1))" : extractedStep
                    steps.append(LogStep(id: stepId, name: displayName, groups: [], isExpanded: false))
                    stepId += 1
                }

                // Helper to get current step index
                let currentStepIdx = steps.isEmpty ? nil : steps.count - 1

                // Check for group markers
                if message.contains("##[group]") {
                    // Save current group
                    if let group = currentGroup, !group.lines.isEmpty, let stepIdx = currentStepIdx {
                        steps[stepIdx].groups.append(group)
                    }

                    // Extract group title
                    var title = "Output"
                    if let range = message.range(of: "##[group]") {
                        title = String(message[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                        if title.isEmpty { title = "Output" }
                    }

                    // If this is "Output", merge with previous group instead of creating new one
                    if title == "Output" && !lastGroupTitle.isEmpty {
                        // Continue using the previous group - don't create new one
                        if let stepIdx = currentStepIdx, !steps[stepIdx].groups.isEmpty {
                            let lastIdx = steps[stepIdx].groups.count - 1
                            currentGroup = steps[stepIdx].groups[lastIdx]
                            steps[stepIdx].groups.removeLast()
                        } else {
                            currentGroup = LogGroup(id: groupId, title: lastGroupTitle, lines: [], isExpanded: false)
                            groupId += 1
                        }
                    } else {
                        currentGroup = LogGroup(id: groupId, title: title, lines: [], isExpanded: false)
                        lastGroupTitle = title
                        groupId += 1
                    }
                } else if message.contains("##[endgroup]") {
                    // End current group
                    if let group = currentGroup, let stepIdx = currentStepIdx {
                        steps[stepIdx].groups.append(group)
                        currentGroup = nil
                    }
                } else if !message.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Regular log line - add to current group
                    let (attributed, newStyle) = parseLineToAttributedString(message, style: currentStyle, fontSize: fontSize)
                    currentStyle = newStyle

                    if currentGroup != nil {
                        currentGroup?.lines.append((id: lineId, raw: message, attributed: attributed))
                    } else if let stepIdx = currentStepIdx {
                        // Line outside group - create implicit group for ungrouped content
                        if steps[stepIdx].groups.isEmpty || !steps[stepIdx].groups.last!.title.isEmpty {
                            currentGroup = LogGroup(id: groupId, title: "", lines: [], isExpanded: true)
                            groupId += 1
                        } else {
                            currentGroup = steps[stepIdx].groups.removeLast()
                        }
                        currentGroup?.lines.append((id: lineId, raw: message, attributed: attributed))
                    }
                    lineId += 1
                }
            }

            // Save final group
            if let group = currentGroup, !group.lines.isEmpty, !steps.isEmpty {
                steps[steps.count - 1].groups.append(group)
            }

            // Filter out empty steps
            return steps.filter { !$0.groups.isEmpty || $0.groups.contains { !$0.lines.isEmpty } }
        }

        nonisolated private static func parseGitLabLogs(_ lines: [String], fontSize: CGFloat) -> [LogStep] {
            var groups: [LogGroup] = []
            var currentGroup: LogGroup?
            var ungroupedLines: [(id: Int, raw: String, attributed: NSAttributedString)] = []
            var groupId = 0
            var lineId = 0
            var currentStyle = ANSITextStyle()

            // Section name to display name mapping
            let sectionNames: [String: String] = [
                "prepare_executor": "Prepare Executor",
                "prepare_script": "Prepare Environment",
                "get_sources": "Get Sources",
                "step_script": "Execute Script",
                "after_script": "After Script",
                "cleanup_file_variables": "Cleanup",
                "archive_cache": "Archive Cache",
                "upload_artifacts": "Upload Artifacts",
                "download_artifacts": "Download Artifacts"
            ]

            // Regex to clean non-color ANSI codes (cursor movement, clear line, etc.)
            let controlCodePattern = try? NSRegularExpression(pattern: #"\x1B\[[0-9;]*[KJHfsu]|\[0K"#, options: [])

            for line in lines {
                // Clean ANSI control codes (keep color codes for the ANSI parser)
                var cleanLine = line.replacingOccurrences(of: "\r", with: "")
                if let regex = controlCodePattern {
                    cleanLine = regex.stringByReplacingMatches(in: cleanLine, options: [], range: NSRange(cleanLine.startIndex..., in: cleanLine), withTemplate: "")
                }

                let trimmed = cleanLine.trimmingCharacters(in: .whitespaces)

                // Check for section_start marker
                if trimmed.hasPrefix("section_start:") {
                    // Save ungrouped lines first
                    if !ungroupedLines.isEmpty {
                        let group = LogGroup(id: groupId, title: "", lines: ungroupedLines, isExpanded: true)
                        groups.append(group)
                        groupId += 1
                        ungroupedLines = []
                    }

                    // Save current group if exists
                    if let group = currentGroup, !group.lines.isEmpty {
                        groups.append(group)
                    }

                    // Parse section name: section_start:timestamp:name
                    let parts = trimmed.split(separator: ":")
                    let sectionName = parts.count >= 3 ? String(parts[2]) : "Section"
                    let displayName = sectionNames[sectionName] ?? sectionName.replacingOccurrences(of: "_", with: " ").capitalized

                    currentGroup = LogGroup(id: groupId, title: displayName, lines: [], isExpanded: false)
                    groupId += 1
                    continue
                }

                // Check for section_end marker
                if trimmed.hasPrefix("section_end:") {
                    if let group = currentGroup {
                        groups.append(group)
                        currentGroup = nil
                    }
                    continue
                }

                // Skip empty lines
                guard !trimmed.isEmpty else { continue }

                // Parse line with ANSI colors
                let (attributed, newStyle) = parseLineToAttributedString(cleanLine, style: currentStyle, fontSize: fontSize)
                currentStyle = newStyle

                if currentGroup != nil {
                    currentGroup?.lines.append((id: lineId, raw: cleanLine, attributed: attributed))
                } else {
                    ungroupedLines.append((id: lineId, raw: cleanLine, attributed: attributed))
                }
                lineId += 1
            }

            // Save remaining content
            if let group = currentGroup, !group.lines.isEmpty {
                groups.append(group)
            }
            if !ungroupedLines.isEmpty {
                let group = LogGroup(id: groupId, title: "", lines: ungroupedLines, isExpanded: true)
                groups.append(group)
            }

            if groups.isEmpty {
                return []
            }

            // Return as a single step containing all groups
            return [LogStep(id: 0, name: "Job Output", groups: groups, isExpanded: true)]
        }

        nonisolated private static func extractStepAndMessage(_ line: String) -> (step: String, message: String) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // GitHub Actions format: "job-name    step-name    timestamp message"
            // Match timestamp pattern
            let timestampPattern = #"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z)"#
            guard let regex = try? NSRegularExpression(pattern: timestampPattern, options: []) else {
                return ("", trimmed)
            }

            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
                  let timestampRange = Range(match.range, in: trimmed) else {
                return ("", trimmed)
            }

            let beforeTimestamp = String(trimmed[..<timestampRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let afterTimestamp = String(trimmed[timestampRange.upperBound...]).trimmingCharacters(in: .whitespaces)

            // Parse job and step from beforeTimestamp
            // Split by multiple whitespace
            let parts = beforeTimestamp.split(omittingEmptySubsequences: true) { $0.isWhitespace }

            var stepName = ""
            if parts.count >= 2 {
                // Step name is everything after job name
                stepName = parts[1..<parts.count].joined(separator: " ")
            }

            return (stepName, afterTimestamp)
        }

        nonisolated private static func parseLineToAttributedString(_ text: String, style: ANSITextStyle, fontSize: CGFloat) -> (NSAttributedString, ANSITextStyle) {
            let result = NSMutableAttributedString()
            var currentStyle = style

            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let defaultAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]

            let pattern = "\u{001B}\\[([0-9;]*)m"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                return (NSAttributedString(string: text, attributes: defaultAttrs), currentStyle)
            }

            var lastEnd = text.startIndex
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                if let swiftRange = Range(match.range, in: text) {
                    let textBefore = String(text[lastEnd..<swiftRange.lowerBound])
                    if !textBefore.isEmpty {
                        result.append(NSAttributedString(string: textBefore, attributes: attributesForStyle(currentStyle, fontSize: fontSize)))
                    }

                    if let codeRange = Range(match.range(at: 1), in: text) {
                        let codes = String(text[codeRange])
                        parseANSICodes(codes, style: &currentStyle)
                    }

                    lastEnd = swiftRange.upperBound
                }
            }

            let remaining = String(text[lastEnd...])
            if !remaining.isEmpty {
                result.append(NSAttributedString(string: remaining, attributes: attributesForStyle(currentStyle, fontSize: fontSize)))
            }

            if result.length == 0 {
                result.append(NSAttributedString(string: " ", attributes: defaultAttrs))
            }

            return (result, currentStyle)
        }

        nonisolated private static func attributesForStyle(_ style: ANSITextStyle, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
            var attrs: [NSAttributedString.Key: Any] = [:]

            let weight: NSFont.Weight = style.bold ? .bold : .regular
            attrs[.font] = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)

            var color = NSColor.labelColor
            switch style.foreground {
            case .red: color = NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)
            case .green: color = NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1)
            case .yellow: color = NSColor(red: 0.8, green: 0.8, blue: 0.2, alpha: 1)
            case .blue: color = NSColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
            case .magenta: color = NSColor(red: 0.8, green: 0.2, blue: 0.8, alpha: 1)
            case .cyan: color = NSColor(red: 0.2, green: 0.8, blue: 0.8, alpha: 1)
            case .brightRed: color = NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1)
            case .brightGreen: color = NSColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1)
            case .brightYellow: color = NSColor(red: 1.0, green: 1.0, blue: 0.4, alpha: 1)
            case .brightBlue: color = NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1)
            case .brightMagenta: color = NSColor(red: 1.0, green: 0.4, blue: 1.0, alpha: 1)
            case .brightCyan: color = NSColor(red: 0.4, green: 1.0, blue: 1.0, alpha: 1)
            case .white, .brightWhite: color = NSColor.white
            case .black, .brightBlack: color = NSColor(white: 0.4, alpha: 1)
            default: break
            }

            if style.dim {
                color = color.withAlphaComponent(0.6)
            }
            attrs[.foregroundColor] = color

            if style.underline {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            return attrs
        }

        nonisolated private static func parseANSICodes(_ codes: String, style: inout ANSITextStyle) {
            let parts = codes.split(separator: ";").compactMap { Int($0) }
            if parts.isEmpty { style.reset(); return }

            for code in parts {
                switch code {
                case 0: style.reset()
                case 1: style.bold = true
                case 2: style.dim = true
                case 4: style.underline = true
                case 22: style.bold = false; style.dim = false
                case 24: style.underline = false
                case 30: style.foreground = .black
                case 31: style.foreground = .red
                case 32: style.foreground = .green
                case 33: style.foreground = .yellow
                case 34: style.foreground = .blue
                case 35: style.foreground = .magenta
                case 36: style.foreground = .cyan
                case 37: style.foreground = .white
                case 39: style.foreground = .default
                case 90: style.foreground = .brightBlack
                case 91: style.foreground = .brightRed
                case 92: style.foreground = .brightGreen
                case 93: style.foreground = .brightYellow
                case 94: style.foreground = .brightBlue
                case 95: style.foreground = .brightMagenta
                case 96: style.foreground = .brightCyan
                case 97: style.foreground = .brightWhite
                default: break
                }
            }
        }

        var workflowLogFrameObserver: NSObjectProtocol?
        var workflowLogColumnObserver: NSObjectProtocol?
        var workflowLogLastTableWidth: CGFloat = 0

        deinit {
            if let observer = workflowLogFrameObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = workflowLogColumnObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        // MARK: - NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            displayRows.count
        }

        // MARK: - NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < displayRows.count else { return nil }

            switch displayRows[row] {
            case .stepHeader(let id, let name, let count, let isExpanded):
                return makeStepHeaderCell(id: id, name: name, count: count, isExpanded: isExpanded, tableView: tableView)
            case .groupHeader(let id, let stepId, let title, let count, let isExpanded):
                return makeGroupHeaderCell(id: id, stepId: stepId, title: title, count: count, isExpanded: isExpanded, tableView: tableView)
            case .logLine(_, _, let attributed):
                return makeLogLineCell(attributed: attributed, tableView: tableView)
            }
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard row < displayRows.count else { return 20 }
            switch displayRows[row] {
            case .stepHeader: return 28
            case .groupHeader: return 22
            case .logLine(_, _, let attributed):
                // Use column width for accurate calculation
                let columnWidth = tableView.tableColumns.first?.width ?? tableView.bounds.width
                let textWidth = max(columnWidth - 20, 100) // 12 leading + 8 trailing

                // Use text storage for accurate height calculation
                let textStorage = NSTextStorage(attributedString: attributed)
                let textContainer = NSTextContainer(size: NSSize(width: textWidth, height: .greatestFiniteMagnitude))
                let layoutManager = NSLayoutManager()

                textContainer.lineFragmentPadding = 0
                layoutManager.addTextContainer(textContainer)
                textStorage.addLayoutManager(layoutManager)

                layoutManager.ensureLayout(for: textContainer)
                let textHeight = layoutManager.usedRect(for: textContainer).height

                return max(ceil(textHeight) + 4, 16)
            }
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = LogRowView()
            if row < displayRows.count {
                switch displayRows[row] {
                case .stepHeader: rowView.isHeader = true; rowView.isStepHeader = true
                case .groupHeader: rowView.isHeader = true; rowView.isStepHeader = false
                case .logLine: rowView.isHeader = false
                }
            }
            return rowView
        }

    }
}

// MARK: - SwiftUI Wrapper

struct WorkflowLogView: View {
    let logs: String
    let structuredLogs: WorkflowLogs?
    let fontSize: CGFloat
    let provider: WorkflowProvider

    @State private var showTimestamps: Bool = false

    init(_ logs: String, structuredLogs: WorkflowLogs? = nil, fontSize: CGFloat = 11, provider: WorkflowProvider = .github) {
        self.logs = logs
        self.structuredLogs = structuredLogs
        self.fontSize = fontSize
        self.provider = provider
    }

    var body: some View {
        WorkflowLogTableView(logs: logs, structuredLogs: structuredLogs, fontSize: fontSize, provider: provider, showTimestamps: $showTimestamps, onCoordinatorReady: nil)
            .background(Color(nsColor: .textBackgroundColor))
    }
}
