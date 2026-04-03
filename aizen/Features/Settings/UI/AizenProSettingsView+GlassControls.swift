import SwiftUI

struct GlassPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .modifier(GlassBackground(cornerRadius: 12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

struct GlassSegmentedTabs<Value: Hashable>: View {
    struct Option: Identifiable {
        let id = UUID()
        let title: String
        let value: Value
        let badge: String?

        init(title: String, value: Value, badge: String? = nil) {
            self.title = title
            self.value = value
            self.badge = badge
        }
    }

    let options: [Option]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Text(option.title)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selection == option.value ? Color.white.opacity(0.16) : Color.clear)
                            )

                        if let badge = option.badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(.white)
                                .background(
                                    Capsule()
                                        .fill(LinearGradient(
                                            colors: [Color.orange, Color.pink],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                )
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .modifier(GlassBackground(cornerRadius: 12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }
}

struct GlassBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
        }
    }
}
