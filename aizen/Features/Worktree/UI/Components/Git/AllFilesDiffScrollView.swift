import SwiftUI

struct AllFilesDiffEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green.opacity(0.6))

            Text(String(localized: "git.diff.noChanges"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Text(String(localized: "git.diff.cleanWorkingTree"))
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
