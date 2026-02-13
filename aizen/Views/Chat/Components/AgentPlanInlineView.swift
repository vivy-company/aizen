//  AgentPlanInlineView.swift
//  aizen
//
//  Inline plan card for displaying agent plan progress
//

import ACP
import SwiftUI

struct AgentPlanInlineView: View {
    let plan: Plan
    @Binding var isCollapsed: Bool
    let isAttachedToComposer: Bool
    @State private var showingSheet = false

    private var completedCount: Int {
        plan.entries.filter { $0.status == .completed }.count
    }

    private var totalCount: Int {
        plan.entries.count
    }

    private var isAllDone: Bool {
        totalCount > 0 && completedCount == totalCount
    }

    private var progressLabel: String {
        "\(completedCount)/\(totalCount) completed"
    }

    private var progressColor: Color {
        if plan.entries.contains(where: { $0.status == .inProgress }) {
            return .blue
        }
        return .secondary
    }

    private var currentWorkingEntry: (index: Int, entry: PlanEntry)? {
        if let index = plan.entries.firstIndex(where: { $0.status == .inProgress }) {
            return (index: index, entry: plan.entries[index])
        }
        if let index = plan.entries.firstIndex(where: { $0.status == .pending }) {
            return (index: index, entry: plan.entries[index])
        }
        if let index = plan.entries.firstIndex(where: { $0.status != .completed }) {
            return (index: index, entry: plan.entries[index])
        }
        return nil
    }

    private var headerTodoLabel: String {
        guard let currentWorkingEntry else { return "Plan" }
        let entry = currentWorkingEntry.entry
        if entry.status == .inProgress,
           let activeForm = entry.activeForm,
           !activeForm.isEmpty {
            return "\(currentWorkingEntry.index + 1). \(activeForm)"
        }
        return "\(currentWorkingEntry.index + 1). \(entry.content)"
    }

    private var isExpanded: Bool {
        !isCollapsed
    }

    private var bottomCornerRadius: CGFloat {
        if isAttachedToComposer {
            return 0
        }
        return 16
    }

    private var cardShape: PlanCardShape {
        PlanCardShape(topCornerRadius: 16, bottomCornerRadius: bottomCornerRadius)
    }

    var body: some View {
        if !plan.entries.isEmpty && !isAllDone {
            VStack(alignment: .leading, spacing: isExpanded ? 8 : 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text(headerTodoLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(progressColor)
                            .frame(width: 8, height: 8)
                        Text(progressLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        Label(isExpanded ? "Collapse" : "Expand", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingSheet = true
                    } label: {
                        Label("Open sheet", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(plan.entries.enumerated()), id: \.offset) { index, entry in
                            PlanEntryRow(entry: entry, index: index + 1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isExpanded ? 10 : 8)
            .background { cardBackground(shape: cardShape) }
            .overlay {
                cardShape
                    .strokeBorder(.separator.opacity(0.3), lineWidth: 0.8)
            }
            .contentShape(cardShape)
            .onTapGesture {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                    isCollapsed.toggle()
                }
            }
            .sheet(isPresented: $showingSheet) {
                AgentPlanSheet(plan: plan)
                    .frame(minWidth: 920, minHeight: 740)
            }
        }
    }

    @ViewBuilder
    private func cardBackground(shape: PlanCardShape) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                shape
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular.interactive(), in: shape)
                shape
                    .fill(.white.opacity(0.03))
            }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

private struct PlanCardShape: InsettableShape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard !insetRect.isEmpty else { return Path() }

        let maxRadius = min(insetRect.width / 2, insetRect.height / 2)
        let topRadius = min(max(topCornerRadius, 0), maxRadius)
        let bottomRadius = min(max(bottomCornerRadius, 0), maxRadius)
        let minX = insetRect.minX
        let maxX = insetRect.maxX
        let minY = insetRect.minY
        let maxY = insetRect.maxY

        var path = Path()
        path.move(to: CGPoint(x: minX + topRadius, y: minY))
        path.addLine(to: CGPoint(x: maxX - topRadius, y: minY))

        if topRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: maxX, y: minY + topRadius),
                control: CGPoint(x: maxX, y: minY)
            )
        } else {
            path.addLine(to: CGPoint(x: maxX, y: minY))
        }

        path.addLine(to: CGPoint(x: maxX, y: maxY - bottomRadius))

        if bottomRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: maxX - bottomRadius, y: maxY),
                control: CGPoint(x: maxX, y: maxY)
            )
        } else {
            path.addLine(to: CGPoint(x: maxX, y: maxY))
        }

        path.addLine(to: CGPoint(x: minX + bottomRadius, y: maxY))

        if bottomRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: minX, y: maxY - bottomRadius),
                control: CGPoint(x: minX, y: maxY)
            )
        } else {
            path.addLine(to: CGPoint(x: minX, y: maxY))
        }

        path.addLine(to: CGPoint(x: minX, y: minY + topRadius))

        if topRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: minX + topRadius, y: minY),
                control: CGPoint(x: minX, y: minY)
            )
        } else {
            path.addLine(to: CGPoint(x: minX, y: minY))
        }

        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> PlanCardShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

struct AgentPlanSheet: View {
    let plan: Plan
    @Environment(\.dismiss) private var dismiss

    private var completedCount: Int {
        plan.entries.filter { $0.status == .completed }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeaderBar(showsBackground: false) {
                Text("Agent Plan")
                    .font(.title3)
                    .fontWeight(.semibold)
            } trailing: {
                HStack(spacing: 12) {
                    Text("\(completedCount)/\(plan.entries.count) completed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    DetailCloseButton { dismiss() }
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(plan.entries.enumerated()), id: \.offset) { index, entry in
                        PlanEntryRow(entry: entry, index: index + 1)
                    }
                }
                .padding()
            }
        }
        .background(.ultraThinMaterial)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlanEntryRow: View {
    let entry: PlanEntry
    var index: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                switch entry.status {
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .inProgress:
                    Image(systemName: "circle.dotted")
                        .foregroundStyle(.blue)
                case .pending:
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                case .cancelled:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .font(.system(size: 13))
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(index > 0 ? "\(index). \(entry.content)" : entry.content)
                    .font(.system(size: 12))
                    .foregroundStyle(entry.status == .completed ? .secondary : .primary)
                    .strikethrough(entry.status == .completed)

                if let activeForm = entry.activeForm, entry.status == .inProgress {
                    Text(activeForm)
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                        .italic()
                }
            }
        }
        .padding(.vertical, 2)
    }
}
