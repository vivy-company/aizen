//
//  ChatMessageList+SummaryCards.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import AppKit
import SwiftUI
import VVChatTimeline
import VVCode
import VVMetalPrimitives

extension ChatMessageList {
    func summaryPayloadCard(_ summary: TurnSummary) -> PayloadSummaryCard {
        let rows = summary.fileChanges.map { change in
            let filePath = resolveSummaryFilePath(change.path)
            return PayloadSummaryRow(
                id: change.id,
                title: compactDisplayPath(change.path),
                subtitle: nil,
                iconURL: summaryFileIconURL(path: change.path),
                actionURL: fileOpenURLString(path: filePath),
                additionsText: "+\(change.linesAdded)",
                deletionsText: "-\(change.linesRemoved)"
            )
        }

        let subtitle: String
        if rows.isEmpty {
            subtitle = "\(summary.toolCallCount) tool call\(summary.toolCallCount == 1 ? "" : "s") • \(summary.formattedDuration) • no files modified"
        } else {
            subtitle = "\(summary.toolCallCount) tool call\(summary.toolCallCount == 1 ? "" : "s") • \(summary.formattedDuration)"
        }

        return PayloadSummaryCard(
            title: "Turn Summary",
            subtitle: subtitle,
            rows: rows
        )
    }

    func makeSummaryCard(from payload: PayloadSummaryCard) -> VVChatSummaryCard {
        let rows = payload.rows.map { row in
            VVChatSummaryCardRow(
                id: row.id,
                title: row.title,
                subtitle: row.subtitle,
                iconURL: row.iconURL,
                actionURL: row.actionURL,
                titleColor: summaryRowTitleColor,
                subtitleColor: summaryRowSubtitleColor,
                additionsText: row.additionsText,
                additionsColor: summaryAdditionsColor,
                deletionsText: row.deletionsText,
                deletionsColor: summaryDeletionsColor,
                hoverFillColor: summaryRowHoverColor
            )
        }

        return VVChatSummaryCard(
            title: payload.title,
            iconURL: symbolIconURL(
                "checklist",
                fallbackID: "turn-summary",
                tintColor: headerIconTintColor,
                pointSize: 12
            ),
            subtitle: payload.subtitle,
            rows: rows,
            titleColor: summaryTitleColor,
            subtitleColor: summarySubtitleColor,
            dividerColor: summaryDividerColor,
            rowDividerColor: summaryRowDividerColor
        )
    }

    var summaryTitleColor: SIMD4<Float> {
        if let theme = activeTerminalVVTheme {
            return simdColor(from: theme.textColor)
        }
        return colorScheme == .dark ? .rgba(0.96, 0.97, 0.99, 1) : .rgba(0.12, 0.14, 0.18, 1)
    }

    var summarySubtitleColor: SIMD4<Float> {
        if let theme = activeTerminalVVTheme {
            return simdColor(from: theme.textColor).withOpacity(0.74)
        }
        return colorScheme == .dark ? .rgba(0.83, 0.85, 0.90, 0.92) : .rgba(0.34, 0.38, 0.46, 0.92)
    }

    var summaryDividerColor: SIMD4<Float> {
        simdColor(from: GhosttyThemeParser.loadDividerColor(named: effectiveTerminalThemeName))
            .withOpacity(colorScheme == .dark ? 0.9 : 0.7)
    }

    var summaryRowDividerColor: SIMD4<Float> {
        summaryDividerColor.withOpacity(colorScheme == .dark ? 0.45 : 0.35)
    }

    var summaryRowTitleColor: SIMD4<Float> {
        summaryTitleColor.withOpacity(0.96)
    }

    var summaryRowSubtitleColor: SIMD4<Float> {
        summarySubtitleColor.withOpacity(0.9)
    }

    var summaryAdditionsColor: SIMD4<Float> {
        if let theme = activeTerminalVVTheme {
            return simdColor(from: theme.gitAddedColor)
        }
        return colorScheme == .dark ? .rgba(0.50, 0.86, 0.62, 1) : .rgba(0.11, 0.60, 0.25, 1)
    }

    var summaryDeletionsColor: SIMD4<Float> {
        if let theme = activeTerminalVVTheme {
            return simdColor(from: theme.gitDeletedColor)
        }
        return colorScheme == .dark ? .rgba(0.94, 0.69, 0.48, 1) : .rgba(0.78, 0.36, 0.08, 1)
    }

    var summaryRowHoverColor: SIMD4<Float> {
        if let theme = activeTerminalVVTheme {
            return simdColor(from: theme.currentLineColor).withOpacity(colorScheme == .dark ? 0.18 : 0.10)
        }
        return colorScheme == .dark ? .rgba(0.86, 0.90, 0.98, 0.035) : .rgba(0.14, 0.20, 0.30, 0.03)
    }

    func summaryFileIconURL(path: String) -> String? {
        let iconPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let iconName = FileIconMapper.iconName(for: iconPath) ?? "file_default"
        guard let image = NSImage(named: iconName),
              let data = image.tiffRepresentation else {
            return nil
        }
        let cacheKey = "turn-summary-file-\(iconName)-\(revisionKey(iconPath))"
        return ChatTimelineHeaderIconStore.urlString(
            for: .customImage(data),
            fallbackAgentId: cacheKey,
            tintColor: nil,
            targetPointSize: 16,
            backingScale: timelineBackingScale
        )
    }
}
