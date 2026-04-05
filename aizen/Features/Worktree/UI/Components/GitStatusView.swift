import SwiftUI

struct GitStatusView: View {
    let additions: Int
    let deletions: Int
    let untrackedFiles: Int

    var body: some View {
        HStack(spacing: 8) {
            if additions > 0 {
                Text("+\(additions)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            }

            if deletions > 0 {
                Text("-\(deletions)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
            }

            if untrackedFiles > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 10))
                    Text("\(untrackedFiles)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
    }
}
