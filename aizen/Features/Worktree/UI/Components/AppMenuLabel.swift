import SwiftUI

struct AppMenuLabel: View {
    let app: DetectedApp

    private func resizedIcon(_ image: NSImage, size: CGSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = app.icon {
                Image(nsImage: resizedIcon(icon, size: CGSize(width: 16, height: 16)))
                    .renderingMode(.original)
            }
            Text(app.name)
        }
    }
}
