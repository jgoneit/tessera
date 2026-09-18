import SwiftUI

enum TesseraDesign {
    static let radius: CGFloat = 16
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
}

/// Opaque semantic surfaces remain readable with either appearance and
/// Reduce Transparency. The content owns its accessibility grouping.
struct TesseraSurface<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let padding: CGFloat
    let content: Content

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: TesseraDesign.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TesseraDesign.radius, style: .continuous)
                    .strokeBorder(TesseraDesign.border.opacity(contrast == .increased ? 1 : 0.65), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct TesseraKeycap: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(TesseraDesign.border, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .fixedSize()
    }
}
