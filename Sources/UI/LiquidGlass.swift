import SwiftUI

struct LiquidGlassShapeBackground<S: InsettableShape>: View {
    let shape: S
    var accentTint: Color? = nil

    var body: some View {
        ZStack {
            // 底层原生自适应分组基底，确保浅色与深色模式下的通透层次
            shape
                .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.55))

            // iOS 液态玻璃半透明毛玻璃层
            shape
                .fill(.ultraThinMaterial)

            // 顶部斜向光线折射高光层
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.42),
                            Color.white.opacity(0.08),
                            Color.clear,
                            (accentTint ?? Color.white).opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            // 液态玻璃镜面边缘流光描边
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.75),
                            Color(uiColor: .separator).opacity(0.35),
                            Color.white.opacity(0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

struct LiquidGlassCardButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 20
    var tint: Color = .blue

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .background {
                LiquidGlassShapeBackground(shape: shape, accentTint: tint)
            }
            .overlay {
                if configuration.isPressed {
                    shape.fill(Color.primary.opacity(0.06))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}