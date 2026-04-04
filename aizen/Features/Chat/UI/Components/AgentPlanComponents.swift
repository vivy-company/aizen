import ACP
import SwiftUI

struct PlanCardShape: InsettableShape {
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
