import AppKit
import SwiftUI

// 색 고르기 — iOS 색상 격자처럼 **버튼 밑 말풍선**으로 뜬다 (개발이 넣은 파일, viewdata-map ⑭).
// macOS `ColorPicker` 는 색상 패널을 따로 창으로 띄워서 쓰기 어색했다.
// 말풍선 아래에 "자주 쓰는 색" 3칸 — 누르면 그 칸이 지금 색으로 바뀐다 (사람이 자기 3색을 만든다).

/// 0...1 sRGB 색 하나. 화면에 숫자로 나오지 않는다.
struct PickedColor: Hashable {
    var red: Double, green: Double, blue: Double

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    /// 8비트로 저장되므로 반 칸 안이면 같은 색이다.
    func same(_ o: PickedColor) -> Bool {
        abs(red - o.red) < 0.5 / 255 + 1e-6 && abs(green - o.green) < 0.5 / 255 + 1e-6 && abs(blue - o.blue) < 0.5 / 255 + 1e-6
    }

    init(red: Double, green: Double, blue: Double) { self.red = red; self.green = green; self.blue = blue }

    init(_ s: CaptionLook.Swatch) { self.init(red: s.red, green: s.green, blue: s.blue) }

    init(hue: Double, saturation: Double, brightness: Double) {
        let c = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1).usingColorSpace(.sRGB)!
        // 저장(8비트)과 같은 값으로 맞춰 둔다 — 골랐던 칸이 다시 열었을 때도 골라진 채로 보이게
        func q(_ x: CGFloat) -> Double { (Double(x) * 255).rounded() / 255 }
        self.init(red: q(c.redComponent), green: q(c.greenComponent), blue: q(c.blueComponent))
    }

    init(white: Double) {
        let q = (white * 255).rounded() / 255
        self.init(red: q, green: q, blue: q)
    }
}

/// 색 격자 — 맨 윗줄은 흰색에서 검정, 아래 9줄은 색상 12개 × 어두운 것에서 옅은 것 (iOS 격자와 같은 짜임).
enum ColorGrid {
    static let hues: [Double] = [0.55, 0.60, 0.67, 0.75, 0.83, 0.95, 0.0, 0.05, 0.09, 0.13, 0.16, 0.30]

    static let rows: [[PickedColor]] = {
        var rows: [[PickedColor]] = [(0..<12).map { PickedColor(white: 1 - Double($0) / 11) }]
        let shades: [(s: Double, b: Double)] = [
            (1, 0.35), (1, 0.51), (1, 0.67), (1, 0.83), (1, 1), (0.8, 1), (0.6, 1), (0.4, 1), (0.2, 1),
        ]
        for shade in shades {
            rows.append(hues.map { PickedColor(hue: $0, saturation: shade.s, brightness: shade.b) })
        }
        return rows
    }()
}

/// 색 버튼 (무지개 테두리 동그라미) + 누르면 말풍선.
struct ColorGridPicker: View {
    /// 지금 색.
    var current: PickedColor
    /// 자주 쓰는 색 3칸.
    var favorites: [PickedColor]
    /// 지금 색이 견본에 없는 색이면 버튼에 고른 표시를 한다.
    var isCustom: Bool
    var onPick: (PickedColor) -> Void
    /// 자주 쓰는 색 칸(index)을 지금 색으로 바꾼다.
    var onSetFavorite: (Int) -> Void

    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            Circle()
                .strokeBorder(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                              center: .center), lineWidth: 3)
                .background(Circle().fill(isCustom ? current.color : .clear).padding(5))
                .frame(width: 22, height: 22)
                .overlay {
                    Circle()
                        .strokeBorder(Tokens.Palette.accent, lineWidth: 2)
                        .padding(-4)
                        .opacity(isCustom ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .help(Copy.Look.pickColor)
        .accessibilityLabel(Copy.Look.pickColor)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ColorGridPanel(current: current, favorites: favorites, onPick: onPick, onSetFavorite: onSetFavorite)
        }
    }
}

/// 말풍선 안 — 격자 + 자주 쓰는 색 3칸.
struct ColorGridPanel: View {
    var current: PickedColor
    var favorites: [PickedColor]
    var onPick: (PickedColor) -> Void
    var onSetFavorite: (Int) -> Void

    var body: some View { panel }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.between) {
            // 격자 — 칸 사이 틈 없이, 바깥 모서리만 둥글게 (iOS 와 같다). 흰 칸이 바탕에 묻히지 않게 옅은 테두리
            VStack(spacing: 6) {
                block(ColorGrid.rows.prefix(1))
                block(ColorGrid.rows.dropFirst())
            }

            Divider()

            VStack(alignment: .leading, spacing: Tokens.Space.tight) {
                Text(Copy.Look.favorites)
                    .font(.caption.weight(.semibold))
                HStack(spacing: Tokens.Space.inner) {
                    ForEach(favorites.indices, id: \.self) { i in
                        Button { onSetFavorite(i) } label: {
                            Circle()
                                .fill(favorites[i].color)
                                .frame(width: 22, height: 22)
                                .overlay { Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1) }
                                .overlay {
                                    Circle()
                                        .strokeBorder(Tokens.Palette.accent, lineWidth: 2)
                                        .padding(-4)
                                        .opacity(favorites[i].same(current) ? 1 : 0)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(Copy.Look.setFavorite)
                    }
                }
                Text(Copy.Look.setFavoriteHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Tokens.Space.between)
    }

    private func block(_ rows: ArraySlice<[PickedColor]>) -> some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(rows[r].indices, id: \.self) { c in cell(rows[r][c]) }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.black.opacity(0.15), lineWidth: 1) }
    }

    private func cell(_ color: PickedColor) -> some View {
        Rectangle()
            .fill(color.color)
            .frame(width: 20, height: 20)
            .overlay {
                if color.same(current) {
                    Rectangle().strokeBorder(.white, lineWidth: 2)
                    Rectangle().strokeBorder(.black.opacity(0.6), lineWidth: 1).padding(2)
                }
            }
            .contentShape(.rect)
            .onTapGesture { onPick(color) }
    }
}


#Preview("색 격자") {
    ColorGridPicker(
        current: PickedColor(white: 1),
        favorites: [PickedColor(white: 1), PickedColor(red: 1, green: 0.89, blue: 0.45), PickedColor(red: 0.55, green: 0.82, blue: 1)],
        isCustom: false, onPick: { _ in }, onSetFavorite: { _ in }
    )
    .padding(40)
}
