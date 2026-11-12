import SwiftUI
import CharacterMediaKit

struct CharacterAppearanceSettings: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("表示スタイル").font(.caption.weight(.medium))
            Picker("形", selection: $settings.appearance.shape) {
                ForEach(CharacterShape.allCases, id: \.self) { Text($0.label).tag($0) }
            }.font(.caption)
            if settings.appearance.shape.usesSquareFrame {
                Picker("収め方", selection: $settings.appearance.fit) {
                    ForEach(CharacterFit.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).font(.caption)
            }
            if settings.appearance.shape == .rounded {
                HStack {
                    Text("角丸").font(.caption).frame(width: 40, alignment: .leading)
                    Slider(value: $settings.appearance.cornerRadius, in: 0...0.5).accessibilityLabel("角丸の強さ")
                    Text("\(Int(settings.appearance.cornerRadius * 100))%")
                        .font(.caption.monospacedDigit()).frame(width: 36)
                }
            }
            if settings.appearance.shape != .original {
                HStack {
                    Text("枠線").font(.caption).frame(width: 40, alignment: .leading)
                    Slider(value: $settings.appearance.borderWidth, in: 0...8, step: 1).accessibilityLabel("枠線の太さ")
                    Text("\(Int(settings.appearance.borderWidth))pt").font(.caption.monospacedDigit()).frame(width: 36)
                }
                Picker("枠の色", selection: $settings.appearance.borderColor) {
                    ForEach(CharacterBorderColor.allCases, id: \.self) { Text($0.label).tag($0) }
                }.font(.caption)
            }
            Toggle("影を表示", isOn: $settings.appearance.shadow).font(.caption)
            Text("左のプレビューと通知に反映します。Dockアイコンの形は変わりません。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Button("表示スタイルを初期値に戻す") { settings.appearance = CharacterAppearance() }.font(.caption)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
