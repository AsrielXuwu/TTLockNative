import SwiftUI

struct LiquidGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.45), lineWidth: 0.5)
            }
    }
}

extension View {
    func liquidGlassSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(LiquidGlassSurface(cornerRadius: cornerRadius))
    }
}