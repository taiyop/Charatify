import SwiftUI
import NotificationCore
import CharacterMediaKit

extension CharacterExpression {
    var label: String {
        switch self {
        case .normal: String(localized: "通常")
        case .done: String(localized: "にっこり")
        case .called: String(localized: "呼ばれた")
        case .waiting: String(localized: "ねえねえ")
        case .notice: String(localized: "お知らせ")
        case .trouble: String(localized: "焦り顔")
        case .hurried: String(localized: "慌て顔")
        case .sleepy: String(localized: "眠そう")
        }
    }

    var hint: String {
        switch self {
        case .normal: String(localized: "どれにも当てはまらない通知・差分が未登録のとき")
        case .done: String(localized: "AIエージェント・開発ツールの完了報告")
        case .called: String(localized: "チャット・メールなど人からの連絡")
        case .waiting: String(localized: "入力待ち・許可待ち（本文のキーワード）")
        case .notice: String(localized: "リマインダー・カレンダー・システム")
        case .trouble: String(localized: "エラー・失敗（本文のキーワード）")
        case .hurried: String(localized: "10秒以内に3件以上届いたとき")
        case .sleepy: String(localized: "深夜0時から5時前までの通知")
        }
    }
}

/// Optional per-expression media. Unregistered slots fall back to the main character.
struct ExpressionSettings: View {
    @ObservedObject var settings: SettingsStore
    let overlay: OverlayController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("通知の種類で表情を切り替える", isOn: $settings.expressionsEnabled).font(.caption)
            Text("登録した表情だけを使い、未登録の種類は通常のキャラクターで表示します。判定はこのMac内で行い、本文は保存しません。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(CharacterExpression.variants, id: \.self) { expression in
                    row(expression)
                }
            }.opacity(settings.expressionsEnabled ? 1 : 0.55)
            Text("表情はエラー、連続、深夜、種類別の順に優先します。深夜のDMで「眠そう」が未登録なら「呼ばれた」が使われます。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .disabled(settings.isImporting)
    }

    private func row(_ expression: CharacterExpression) -> some View {
        HStack(spacing: 10) {
            Group {
                if let image = settings.expressionImages[expression] {
                    CharacterView(image: image, size: 40, appearance: settings.appearance)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3]))
                        .overlay(Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(.secondary))
                        .frame(width: 40, height: 40)
                }
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(expression.label).font(.system(size: 12, weight: .semibold))
                    if settings.expressionMedia[expression]?.kind == .video {
                        Image(systemName: "video.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Text(expression.hint).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Menu(settings.expressionMedia[expression] == nil ? String(localized: "登録") : String(localized: "変更")) {
                Button("画像を選ぶ…") { settings.chooseExpressionImage(expression) }
                Button("動画を選ぶ…") { settings.chooseExpressionVideo(expression) }
                if settings.expressionMedia[expression] != nil {
                    Divider()
                    Button("表示をテスト") { overlay.preview(expression: expression) }
                    Button("削除", role: .destructive) { settings.resetExpression(expression) }
                }
            }
            .menuStyle(.borderlessButton).fixedSize().font(.caption)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(expression.label)の表情")
    }
}
