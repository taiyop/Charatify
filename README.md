# Charatify

macOSの通知バナーを読み取り、好きなキャラクター画像・動画と吹き出しを、指定したディスプレイの好きな場所に表示するメニューバーアプリです。通知がない間は非表示です。通知の処理はこのMac内で完結します。アプリの更新確認・インストールにはSparkle 2を使用します。

## ダウンロードとアップデート

[GitHub Releases](https://github.com/taiyop/Charatify/releases/latest) の `Charatify-<バージョン>.dmg` を開き、CharatifyをApplicationsへドラッグして起動してください。配布DMGはApple Silicon / IntelのUniversal版です。公開リリースにはDeveloper ID署名・Appleの公証を必須としています。

配布版は1日ごとに更新フィードを確認します。メニューバー、または設定の「アップデート」→「アップデートを確認…」で手動確認もできます。「アップデートを自動で確認」は設定でオフにできます。更新のダウンロードとインストールにはユーザーの操作が必要です。署名の一致を確認してから展開します。

更新フィードは `https://raw.githubusercontent.com/taiyop/Charatify/updates/appcast.xml`、DMGはGitHub Releasesから取得します。この通信に通知本文・キャラクターの画像・動画は含まれません。初回リリース成功時に `updates` ブランチとフィードが作成されます。Sparkle未搭載の旧版からは、一度DMGを使って手動で更新してください。

## 開発版の起動

macOS 14以降、XcodeまたはSwiftツールチェーンが必要です。このMacのアーキテクチャ向けにビルドします。

初回ビルドはSparkle 2をダウンロードします。通常のビルドは **Charatify Dev** を作成します。公開用の鍵が環境変数に設定されていても、Dev版では更新確認を無効にします。

```sh
make test
make build
open "build/Charatify Dev.app"
```

`make dev` または `make run` でもビルドして起動できます。DMG経由のインストールを試す場合は `make dmg-dev` を実行し、`build/dev-dmg/Charatify-Dev.dmg` を使ってください。このDMGにもDev版が入ります。

| 項目 | 開発版 | 公開版 |
| --- | --- | --- |
| アプリ | `Charatify Dev.app` | `Charatify.app` |
| Bundle ID・設定ドメイン | `dev.local.CharacterNotification.dev` | `dev.local.CharacterNotification` |
| Application Support | `CharacterNotification-Dev/` | `CharacterNotification/` |
| 更新確認 | 無効 | Sparkleで安定版を確認 |
| 署名 | `DEV_CODE_SIGN_IDENTITY`、未設定ならアドホック | Developer ID署名・公証が必須 |

アクセシビリティ許可・このアプリのテスト通知の許可・ログイン項目は、それぞれのアプリで設定してください。開発版のメニューバーはハンマーで、DockアイコンにはDEVの印が付きます。開発版の初回起動時は設定・メディアを新規に作成し、公開版から自動コピーしません。両方の監視が有効だと通知が二重に表示されるため、開発時は必要に応じて公開版の監視を一時停止してください。

再ビルド後の権限を保持しやすくするため、開発版にもApple Development署名を推奨します。証明書名は `security find-identity -v -p codesigning` で確認できます。

```sh
DEV_CODE_SIGN_IDENTITY='Apple Development: 名前 (識別子)' make dev
```

未設定でも開発できますが、アドホック署名では再ビルド後に権限の再登録が必要になる場合があります。Dev版を同じ場所で使い続けてください。開発から公開までの手順は [開発・配布方針](docs/development.md) に記載しています。

公開版は、旧名のCharacter NotificationのBundle ID `dev.local.CharacterNotification`、データ保存先 `~/Library/Application Support/CharacterNotification/` を維持しています。以前ローカルビルドで使っていたデータもこの保存先に残ります。旧アプリを終了してから公開版Charatifyを起動してください。署名方式が変わる初回の移行時には、権限の再許可が必要になる場合があります。「ログイン時に起動」を使っている場合は、公開版を固定の場所に移してから設定を確認してください。

1. アプリの「アクセシビリティ設定を開く」を押します。
2. システム設定 → プライバシーとセキュリティ → アクセシビリティ（macOS 27では「デバイスの制御とデータへのアクセス」）で、使うアプリの **Charatify Dev** または **Charatify** を許可します。見つからなければ「＋」から対象のアプリを追加します。オンでも認識されない場合は、対象のアプリの登録だけを「−」で削除して「＋」から追加し直してください。
3. アプリに戻り、状態が「監視中」になることを確認します。
4. 「画像を選ぶ…」でキャラクター画像を指定します。透過PNG推奨。JPEG / TIFF / HEICも使用でき、25MB・8192px以下に対応します。「動画を選ぶ…」では200MB以下のMP4 / MOV / M4Vを指定できます。動画は無音でループ再生します。
5. 表示先ディスプレイを選び、9つの位置から配置を決めます。自由に配置する場合は「ドラッグで位置を調整」を押し、別表示されるプレビューの「ここをつかんで移動」をマウスで押したまま動かします。移動先で離し、「ここに保存」で確定します。
6. 「表示をテスト」は権限なしで見た目を確認できます。「macOS通知で確認」はこのアプリ自身のローカル通知を3秒後に発行します（初回のみ別途通知の許可が必要）。**標準バナーと同じ本文がキャラクター側にも表示されること**が、実際の読み取りの確認になります。

メニューバーの吹き出しアイコンから設定・テスト・一時停止・終了を操作できます。設定画面を閉じても監視は続きます。「ログイン時に起動」はユーザーが設定から有効にした場合のみ登録します。

## 挙動

- キャラクター欄の「表示スタイル」で、自動・元の形・角丸・円形・四角を選べます。角丸の強さ、枠線の太さと色、影、枠への収め方（全体／枠いっぱい）を変更でき、設定は保存されます。左のプレビューと通知表示にすぐ反映します。
- 動画はアプリ内へコピーするため、読み込み後に元のファイルを移動しても使えます。通知の表示中と設定プレビューの表示中に再生し、通知を閉じたり設定ウインドウを隠したりすると停止・一時停止します。動画のコーデックによっては再生できません。読み込みに失敗した場合は現在のキャラクターを保持します。
- 動画の最初のフレームをDock用の静止画として使います。通知側の円形・角丸設定はDockアイコンの合成仕様を変更しません。

- 設定の「表示と起動」→「Dockに表示」でDockアイコンを切り替えられます。初期値はオフです。オフでもメニューバーと通知監視は動き続けます。
- キャラクターを選ぶと、その顔を吹き出しに収めたDockアイコンを生成します。Visionで顔を検出し、設定の「Dockアイコンの顔位置」でドラッグ・ピンチ・スライダーによる調整ができます。位置と拡大率は自動保存されます。顔が見つからない場合や複数ある場合は、この画面で合わせてください。
- 64〜1024pxは吹き出し、16・32pxは白い角丸地に大きな顔を描く専用版です。「標準に戻す」でバンドル既定のアイコンに戻ります。バンドルのアイコン自体は変更しません。
- 合成と顔検出はバックグラウンドで処理します。画像のSHA-256と顔位置をキーに、7サイズのPNGを `~/Library/Application Support/CharacterNotification/CharacterIcon/` に保存して再利用します。キャラクター削除時にキャッシュも削除します。
- 既存の未読カウンタがないため、Dockの未読バッジは表示しません。Dev版には識別用の「DEV」バッジを表示します。通知の累計や待機件数を未読数として流用しません。

- 吹き出しの名札に通知元アプリのアイコンを表示します（「表示と起動」でオフにできます）。バナーにはアプリ名しか含まれないため、名前を起動中・インストール済みアプリ（`/Applications`、`/System/Applications`、`~/Applications` など）の表示名と照合して推定します。一致しない名前・同名の別アプリが複数ある名前・Webサイトの通知ではアイコンを出さず、従来の記号を表示します。画面キャプチャは行いません。
- 通知時だけキャラクターとメッセージを表示。3〜30秒で消え、カーソルを重ねるとタイマーを停止します。
- 通知が連続したら順番に表示。待機は最大20件で、超過時は古い待機通知から除きます。
- モニターはUUIDと相対位置で記憶。指定モニターが未接続ならメイン画面に表示し、再接続で元に戻ります。
- 「メインディスプレイ」はmacOSがプライマリに指定した画面です。フォーカスのある画面には追従しません。
- 起動直後・一時停止解除後・通知センター再起動時の既存バナーは再生しません。
- 画面ロック・セッション切替・スリープの通知を受けると、表示と待機キューを消します。
- メッセージはメモリ上だけで処理し、ディスクへの保存・本文のログ出力・ネットワーク送信は行いません。キャラクターの画像・動画・サムネイルと設定のみApplication Support / UserDefaultsに保存します。

## 読み取りの制約

macOSの公開通知APIでは他アプリの通知を購読できません。このアプリは、アクセシビリティAPIで **Notification Centerの画面上のバナーとして認識できた通知**を読み取ります。通常のアプリに全通知の配信を保証する仕組みはありません。

- **標準バナーは残ります。** 元の通知を消したり、アプリごとの通知設定を書き換えたりしません。
- 元アプリのバナーをオフにすると読み取れなくなります。集中モードで抑制された通知・通知センターだけに届く通知・非表示のプレビュー本文も取得できません。
- キャラクターをクリックして元アプリに返信・遷移する機能はありません。
- OSによってアクセシビリティの構造が変わります。認識できるバナーのサブロールを限定し、ウィジェットを拾わない設計です。個別の通知要素を公開しないスタック形式は、複数メッセージの混同を避けるため読み取らず、状態欄に未対応と表示します。
- 履歴表示で認識できるコンテナは読み取りを停止しますが、macOSの全バージョンの履歴構造は検証できていません。通知センターを閉じた状態で利用してください。
- 検出はAXイベントと0.8秒間隔の補助ポーリングで行います。短時間で消えるバナーなど、取りこぼす場合があります。
- Dev版の署名が未設定の場合はアドホック署名です。Dev版は公開用のDeveloper ID署名・公証の対象にしません。

## 自動リリースの初期設定

GitHub Actionsの `.github/workflows/release.yml` は、`0.1.0` のようなタグのpushでテスト、Universalビルド、DMG生成、Ed25519署名検証、GitHub Releases公開、`updates` ブランチのappcast更新を実行します。フィードはDMG公開後に更新します。安定版の `数字.数字.数字`（先頭の `v` は任意）に対応し、公開済み以下のバージョンは拒否します。タグにはこのワークフローと実装を含むコミットを指定してください。

最初に一度、リポジトリの Settings → Secrets and variables → Actions に署名用の設定が必要です。

```sh
swift package resolve
# 専用の署名鍵をログインキーチェーンに作成（既存なら再利用）
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account Charatify
```

表示された公開鍵を、Repository **variable** の `SPARKLE_PUBLIC_ED_KEY` に登録します。秘密鍵は以下のように一時ファイルからRepository **secret** の `SPARKLE_PRIVATE_KEY` に登録し、画面やログに表示しないでください。GitHub CLIへのログインが必要です。

```sh
(
  set -e
  umask 077
  key_file="$(mktemp)"
  trap 'rm -f "$key_file"' EXIT
  .build/artifacts/sparkle/Sparkle/bin/generate_keys --account Charatify -x "$key_file"
  gh secret set SPARKLE_PRIVATE_KEY --repo taiyop/Charatify < "$key_file"
)
```

秘密鍵はリポジトリにコミットせず、キーチェーンと安全なバックアップで保持してください。同じ鍵を継続利用し、既存利用者のいる公開鍵を不用意に変更しないでください。鍵の設定がない場合、リリース処理は公開前に失敗します。GitHub Actionsによるリポジトリへの書き込みが組織ポリシーやブランチルールで禁止されている場合は、`updates` ブランチへのbotの書き込みを許可してください。GitHub Pagesの有効化やPATの登録は不要です。

### Developer ID署名と公証（必須）

以下をすべて設定してください。アプリ・Sparkleのヘルパー・DMGをDeveloper ID署名し、アプリとDMGの公証・staple・Gatekeeper検証が通ってから公開します。未設定・一部不足・署名または公証失敗の場合は公開を停止します。

| 種別 | 名前 | 内容 |
| --- | --- | --- |
| Variable | `APPLE_SIGN_IDENTITY` | `Developer ID Application: 名前 (TEAMID)` |
| Secret | `APPLE_CERTIFICATE_P12` | 秘密鍵を含むDeveloper ID証明書のp12をBase64化したもの |
| Secret | `APPLE_CERTIFICATE_PASSWORD` | p12のパスワード |
| Secret | `APPLE_ID` | Apple DeveloperのApple ID |
| Secret | `APPLE_TEAM_ID` | Team ID |
| Secret | `APPLE_APP_SPECIFIC_PASSWORD` | 公証用のアプリ用パスワード |

```sh
# 初期設定を完了し、実装をmainへ反映した後
git tag 0.1.0
git push origin 0.1.0
```

ローカルで公開前の最終確認用DMGとappcastを作る場合は、`CODE_SIGN_IDENTITY`、`APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_SPECIFIC_PASSWORD` を環境変数に設定してから以下を実行します。秘密鍵は `Charatify` アカウントのキーチェーンから取得します。CIではSecretを標準入力でSparkleへ渡します。

```sh
APP_VERSION=0.2.0 \
SPARKLE_PUBLIC_ED_KEY='<公開鍵>' \
RELEASE_DOWNLOAD_URL='https://github.com/taiyop/Charatify/releases/download/v0.2.0/' \
make release
```

出力は `build/Charatify.app`、`build/updates/Charatify-0.2.0.dmg` と `build/updates/appcast.xml` です。`make release` はローカル生成までで、アップロードは行いません。公開用のビルド設定・保存先を使用するため、テスト用macOSユーザーでの確認を推奨します。`APP_BUILD_VERSION` 未指定時は `APP_VERSION` を `CFBundleVersion` にも使います。署名・検証・公証後にDMGを変更すると署名が無効になります。公開フィードを手編集せず、リリース手順で生成してください。

公開途中のエラーはActionsの「Re-run jobs」で再開できます。DMGがすでに公開されていれば、そのDMGとappcastを取得・署名検証してフィードの公開を再開し、公開済みの資産は上書きしません。同一のフィードが公開済みなら成功として終了します。複数タグの処理はキューに入れて順番に実行します。

公式資料: [Sparkleの導入](https://sparkle-project.org/documentation/)、[更新の公開](https://sparkle-project.org/documentation/publishing/)。

## 検証

`swift test` は複数画面の座標（負の原点・小さな画面・相対位置の復元）、既存通知の再生抑止、同文の別通知、本文と操作ボタンの分離、複数バナーの分離を検証します。実通知の読み取りには上記の権限と手動確認が別途必要です。

動的アイコンは7サイズの出力、縦横比と向き、顔検出の失敗・複数顔、キャッシュ再利用・破損復旧・画像や位置の変更による再生成も検証します。

動画の取り込み・回転情報に沿ったサムネイル・元ファイル削除後の再生可能性・サイズ上限・取り込み失敗時の既存画像保持・表示設定の保存も `swift test` で検証します。

主要ファイル:

- `Sources/Charatify/NotificationMonitor.swift`: Notification CenterのAX監視
- `Sources/Charatify/Overlay.swift`: キャラクター・吹き出し・待機キュー
- `Sources/Charatify/SettingsView.swift`: 設定画面
- `Sources/NotificationCore/NotificationCore.swift`: 座標計算・検出状態・バナー解析
- `Sources/NotificationCore/AppMatcher.swift` / `Sources/Charatify/AppIconResolver.swift`: 通知元アプリ名からのアイコン推定

- `Sources/CharacterMediaKit/`: メディアの取り込み・保存・表示スタイル
- `Sources/Charatify/LoopingCharacterVideo.swift`: 表示中だけ再生する動画ビュー
