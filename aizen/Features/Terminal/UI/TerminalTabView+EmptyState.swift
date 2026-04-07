import SwiftUI

extension TerminalTabView {
    var terminalEmptyState: some View {
        let visiblePresets = Array(presetManager.presets.prefix(visiblePresetsLimit))

        return VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 24) {
                terminalHeader
                newTerminalButton

                if !visiblePresets.isEmpty {
                    launchPresetSeparator
                    presetButtons(for: visiblePresets)
                }
            }
            .frame(maxWidth: emptyStateMaxWidth)
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppSurfaceTheme.backgroundColor())
    }

    var terminalHeader: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("terminal.noSessions", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("terminal.openInWorktree", bundle: .main)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var newTerminalButton: some View {
        if #available(macOS 26.0, *) {
            Button {
                createNewSession()
            } label: {
                Label("terminal.new", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        } else {
            Button {
                createNewSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("terminal.new", bundle: .main)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.blue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    var launchPresetSeparator: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
            Text("Or launch a preset")
                .font(.caption)
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        }
        .frame(maxWidth: 460)
    }

    @ViewBuilder
    func presetButtons(for presets: [TerminalPreset]) -> some View {
        VStack(spacing: 8) {
            ForEach(presets) { preset in
                presetButton(for: preset)
            }
        }
        .frame(maxWidth: 460)
    }

    func presetButton(for preset: TerminalPreset) -> some View {
        let trimmedCommand = preset.command.trimmingCharacters(in: .whitespacesAndNewlines)

        return Button {
            createNewSession(withPreset: preset)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: preset.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !trimmedCommand.isEmpty {
                        Text(trimmedCommand)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                emptyStateItemBackground(cornerRadius: 12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(emptyStateItemStrokeColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func emptyStateItemBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            shape
                .fill(.white.opacity(0.001))
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            shape.fill(.thinMaterial)
        }
    }

    var emptyStateItemStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08)
    }
}
