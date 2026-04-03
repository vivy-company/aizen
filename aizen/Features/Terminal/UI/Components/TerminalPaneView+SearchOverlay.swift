import GhosttyKit
import SwiftUI

struct AizenSurfaceSearchOverlay: View {
    let surfaceView: AizenTerminalSurfaceView
    @ObservedObject var searchState: SearchState
    let onClose: () -> Void

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            searchField

            Button {
                navigateSearch("navigate_search:next")
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(AizenSearchButtonStyle())

            Button {
                navigateSearch("navigate_search:previous")
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(AizenSearchButtonStyle())

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(AizenSearchButtonStyle())
        }
        .padding(8)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .onAppear {
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .ghosttySearchFocus)) { notification in
            guard notification.object as? AizenTerminalSurfaceView === surfaceView else { return }
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
    }

    private var searchField: some View {
        TextField("Search", text: $searchState.needle)
            .textFieldStyle(.plain)
            .frame(width: 180)
            .padding(.leading, 8)
            .padding(.trailing, 50)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.1))
            .cornerRadius(6)
            .focused($isSearchFieldFocused)
            .overlay(alignment: .trailing) {
                resultLabel
            }
            .onSubmit {
                navigateSearch("navigate_search:next")
            }
    }

    @ViewBuilder
    private var resultLabel: some View {
        if let selected = searchState.selected {
            Text("\(selected + 1)/\(searchState.total ?? 0)")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .padding(.trailing, 8)
        } else if let total = searchState.total {
            Text("-/\(total)")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .padding(.trailing, 8)
        }
    }

    private func navigateSearch(_ action: String) {
        guard let surface = surfaceView.surface else { return }
        ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
    }
}

struct AizenSearchButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered || configuration.isPressed ? .primary : .secondary)
            .padding(.horizontal, 2)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.primary.opacity(0.2)
        } else if isHovered {
            return Color.primary.opacity(0.1)
        } else {
            return Color.clear
        }
    }
}
