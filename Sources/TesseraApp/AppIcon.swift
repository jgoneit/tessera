import AppKit

@MainActor
enum AppIcon {
    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "Tessera")
            ?? NSImage(size: NSSize(width: 32, height: 32))
    }()

    static let menuImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            for rect in [
                NSRect(x: 1, y: 2, width: 7, height: 14),
                NSRect(x: 10, y: 2, width: 7, height: 6),
                NSRect(x: 10, y: 10, width: 7, height: 6)
            ] {
                NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
