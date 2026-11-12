import SwiftUI
import ServiceManagement
import CharacterMediaKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var monitor: NotificationMonitor
    @ObservedObject var overlay: OverlayController
    @ObservedObject var notificationTest: NotificationTest
    @ObservedObject var characterIcon: CharacterIconController
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(.teal)
                    Text("CHARACTER\nNOTIFICATION").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2)
                }
                Spacer()
                CharacterView(image: settings.image, size: 150, videoURL: settings.videoURL, appearance: settings.appearance)
                    .frame(maxWidth: .infinity)
                Text("いつもの通知を、\n好きなキャラクターから。")
                    .font(.system(size: 23, weight: .semibold)).lineSpacing(6)
                Text("通知があるときだけ登場。\nいつも目に入る場所に置けます。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                Button("表示をテスト", systemImage: "play.fill") { overlay.preview() }
                    .buttonStyle(.borderedProminent).tint(.teal).controlSize(.large)
                Spacer()
                Label("画像も通知も、このMacの中だけに。", systemImage: "lock.shield")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(28).frame(width: 265)
            .background(Color.teal.opacity(0.07))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("通知のある場所").font(.system(size: 24, weight: .bold))
                            Text("キャラクターと、登場する場所を選びましょう。")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("通知を表示", isOn: $settings.enabled).toggleStyle(.switch).labelsHidden().help("通知の表示を一時停止")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label(monitor.status, systemImage: monitor.trusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(monitor.trusted ? Color.teal : .orange)
                        if !monitor.trusted {
                            Text("macOS全体の通知を読み取るには、アクセシビリティでこのアプリを許可してください。")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("アクセシビリティ設定を開く") { monitor.requestPermission() }
                        } else {
                            Button("macOS通知で確認") { notificationTest.send() }.font(.caption)
                        }
                        if let message = notificationTest.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.teal.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                    section("01", "キャラクター") {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(settings.image == nil ? "標準のねこ" : (settings.videoURL == nil ? "カスタム画像" : "カスタム動画")).font(.system(size: 13, weight: .medium))
                                Text("画像25MB以下 · 動画200MB以下").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Button("画像を選ぶ…") { settings.chooseImage() }
                                Button("動画を選ぶ…") { settings.chooseVideo() }
                            }.disabled(settings.isImporting)
                        }
                        if settings.isImporting {
                            HStack { ProgressView().controlSize(.small); Text("読み込み中…").font(.caption) }
                        }
                        if settings.videoURL != nil {
                            Text("MP4 / MOV / M4V · 無音でループ再生。Dockには最初のフレームを使います。")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        if settings.image != nil {
                            Button("標準に戻す") { settings.resetImage() }.font(.caption).disabled(settings.isImporting)
                            CharacterAppearanceSettings(settings: settings)
                        }
                        if settings.image != nil { IconAdjustmentView(settings: settings, controller: characterIcon) }
                        if let error = settings.imageError { Text(error).font(.caption).foregroundStyle(.red) }
                        HStack {
                            Text("大きさ").font(.caption).frame(width: 48, alignment: .leading)
                            Slider(value: $settings.characterSize, in: 80...200, step: 10)
                            Text("\(Int(settings.characterSize)) pt").font(.caption.monospacedDigit()).frame(width: 44)
                        }
                    }

                    section("02", "表示する場所") {
                        Picker("ディスプレイ", selection: $settings.displayID) {
                            Text("メインディスプレイ").tag("main")
                            ForEach(settings.screens, id: \.self) { screen in
                                Text(screen.localizedName).tag(SettingsStore.id(for: screen))
                            }
                            if settings.missingDisplay { Text("未接続のディスプレイ").tag(settings.displayID) }
                        }.font(.caption)
                        if settings.missingDisplay {
                            Text("指定した画面が未接続のため、メイン画面に表示します。")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        HStack(spacing: 16) {
                            VStack(spacing: 5) {
                                ForEach([1.0, 0.5, 0.0], id: \.self) { y in
                                    HStack(spacing: 5) {
                                        ForEach([0.0, 0.5, 1.0], id: \.self) { x in
                                            Button {
                                                settings.x = x; settings.y = y
                                                overlay.preview()
                                            } label: {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(abs(settings.x - x) < 0.01 && abs(settings.y - y) < 0.01 ? Color.teal : Color.secondary.opacity(0.15))
                                                    .frame(width: 32, height: 18)
                                            }.buttonStyle(.plain).accessibilityLabel(positionName(x: x, y: y))
                                        }
                                    }
                                }
                            }.padding(9).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 8) {
                                Text("下のボタンで配置用プレビューを表示。\n「ここをつかんで移動」をドラッグし、\n「ここに保存」で確定します。")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("ドラッグで位置を調整") { overlay.preview(positioning: true) }.font(.caption)
                            }
                        }
                    }

                    section("03", "表示と起動") {
                        Toggle("Dockに表示", isOn: $settings.showInDock).font(.caption)
                        Text("キャラクターを設定すると、Dockアイコンもその顔に変わります。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        HStack {
                            Text("表示時間").font(.caption)
                            Slider(value: $settings.duration, in: 3...30, step: 1)
                            Text("\(Int(settings.duration))秒").font(.caption.monospacedDigit()).frame(width: 35)
                        }
                        Text("カーソルを重ねている間は消えません。連続した通知は順番に表示します。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Toggle("通知元アプリのアイコンを表示", isOn: $settings.showAppIcon).font(.caption)
                        Text("バナーのアプリ名からインストール済みアプリを探します。名前が一致しない場合やWebサイトの通知では表示されません。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Toggle("ログイン時に起動", isOn: $loginEnabled).font(.caption)
                            .onChange(of: loginEnabled) { _, enabled in updateLogin(enabled) }
                        if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
                    }
                    Text("画面に出た通知バナーを読み取ります。標準バナーも表示されます。集中モードで抑制された通知や、非表示の本文は取得できません。OSの変更により読み取れない場合があります。")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(28)
            }.frame(width: 495)
        }
        .frame(height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: settings.enabled) { _, enabled in if !enabled { overlay.clear() }; monitor.scan() }
        .onChange(of: settings.displayID) { _, _ in overlay.reposition() }
        .onChange(of: settings.characterSize) { _, _ in overlay.reposition() }
    }

    private func positionName(x: Double, y: Double) -> String {
        let vertical = y == 1 ? "上" : y == 0 ? "下" : "中央"
        let horizontal = x == 0 ? "左" : x == 1 ? "右" : "中央"
        return "\(vertical)・\(horizontal)に表示"
    }

    private func section<Content: View>(_ number: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Text(number).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.teal)
                Text(title).font(.system(size: 13, weight: .semibold))
                Rectangle().fill(.quaternary).frame(height: 1)
            }
            content()
        }
    }

    private func updateLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = SMAppService.mainApp.status == .requiresApproval ? "システム設定の「ログイン項目」で起動を許可してください。" : nil
        } catch {
            loginError = "起動設定を変更できません: \(error.localizedDescription)"
            loginEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
