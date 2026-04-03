import SwiftUI

extension WorkflowSidebarView {
    var sidebarHeader: some View {
        HStack(spacing: 12) {
            Text(service.provider.displayName)
                .font(.headline)

            if totalItemsCount > 0 {
                TagBadge(text: "\(totalItemsCount)", color: .secondary, cornerRadius: 6)
            }

            Spacer()

            if service.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }

            Button {
                Task {
                    await service.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(chipBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(service.isLoading)
            .help(String(localized: "general.refresh"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    var chipBackground: some ShapeStyle {
        Color.white.opacity(0.08)
    }

    var initializingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "git.workflow.checkingCLI"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var noProviderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text(String(localized: "git.workflow.noProvider"))
                .font(.subheadline)
                .fontWeight(.medium)

            Text(String(localized: "git.workflow.addFiles"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    var cliNotInstalledView: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text(String(localized: "git.workflow.cliNotInstalled \(service.provider.cliCommand)"))
                .font(.subheadline)
                .fontWeight(.medium)

            CodePill(
                text: "brew install \(service.provider.cliCommand)",
                backgroundColor: Color(nsColor: .controlBackgroundColor),
                horizontalPadding: 6,
                verticalPadding: 6
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    var notAuthenticatedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text(String(localized: "git.workflow.notAuthenticated"))
                .font(.subheadline)
                .fontWeight(.medium)

            CodePill(
                text: "\(service.provider.cliCommand) auth login",
                backgroundColor: Color(nsColor: .controlBackgroundColor),
                horizontalPadding: 6,
                verticalPadding: 6
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    func errorBanner(_ error: WorkflowError) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)

            Text(error.localizedDescription)
                .font(.caption2)
                .lineLimit(2)

            Spacer()

            Button {
                service.error = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .padding(6)
        .background(Color.yellow.opacity(0.1))
    }
}
