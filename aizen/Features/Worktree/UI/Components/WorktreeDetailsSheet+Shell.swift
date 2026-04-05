import SwiftUI

extension WorktreeDetailsSheet {
    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    branchStatus
                    informationSection
                    errorSection
                }
                .padding()
            }
        }
        .frame(width: 500, height: 400)
        .settingsSheetChrome()
        .onAppear {
            refreshStatus()
        }
    }
}
