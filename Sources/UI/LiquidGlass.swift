import SwiftUI

extension View {
    /// 纯原生液态玻璃圆形容器（iOS 26/27 使用官方 glassEffect，旧版本回退原生 Material，无任何自定义阴影与边框）
    @ViewBuilder
    func nativeGlassCircle() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .circle)
        } else {
            self.background(.regularMaterial, in: Circle())
        }
        #else
        self.background(.regularMaterial, in: Circle())
        #endif
    }

    /// 纯原生液态玻璃按钮样式
    @ViewBuilder
    func nativeGlassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
        #else
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
        #endif
    }
}