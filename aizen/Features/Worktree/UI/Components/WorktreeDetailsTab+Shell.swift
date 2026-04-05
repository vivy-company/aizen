import SwiftUI

extension DetailsTabView {
    var body: some View {
        detailsContent
            .modifier(detailsTabLifecycle())
    }
}
