import SwiftUI

/// 글자만 있는 링크 버튼 — **강조색**으로 (2026-09-29 시안 `a{color:#26407A}` · 누르면 #1E3362).
/// `.buttonStyle(.link)` 는 시스템 링크 파랑이라 강조색(남색)과 따로 논다.
struct AccentLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Tokens.Palette.accentPressed : Tokens.Palette.accent)
            .contentShape(.rect)
    }
}

extension ButtonStyle where Self == AccentLinkStyle {
    static var accentLink: AccentLinkStyle { AccentLinkStyle() }
}
