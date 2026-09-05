import AppKit
import SwiftUI

/// One asset across the Dock, sidebar, menu popover and About screen.
struct AppBrandIcon: View {
    let size: CGFloat
    private static let image: NSImage? = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "circle.lefthalf.filled").resizable().scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
