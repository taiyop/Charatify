# Charatify

macOSの通知バナーを読み取り、好きなキャラクター画像・動画と吹き出しを、指定したディスプレイの好きな場所に表示するメニューバーアプリです。通知がない間は非表示です。通知の処理はこのMac内で完結します。アプリの更新はGitHub Releasesから確認・インストールできます。

## ダウンロードとアップデート

[GitHub Releases](https://github.com/taiyop/Charatify/releases) で最新のリリースを開き、`Charatify-<バージョン>.dmg` または `Charatify-<バージョン>-unnotarized.dmg` から、CharatifyをApplicationsへドラッグしてください。DMGはApple Silicon / IntelのUniversal版です。未公証の版はmacOSで起動が制限される場合があります。

配布版は起動後と1日ごとにGitHub Releasesを確認します。メニューバー、または設定の「アップデート」→「アップデートを確認…」から手動確認もできます。更新が見つかったら、確認画面の「インストールして再起動」で、更新用ZIPのSHA-256とアプリのコード署名を確認してからインストールします。この通信に通知本文・キャラクターの画像・動画は含まれません。

安定版では既定で安定版の更新を確認します。設定で「Nightly版も更新対象に含める」をオンにするとNightlyも候補に加わります。Nightlyを直接インストールした場合は、保存済みの選択がなければオンになります。オフにすると、現在のビルドより新しい安定版が案内されます。

0.3.1以前の配布版からは、GitHub Releases方式に対応した最初の版のDMGを一度手動でインストールしてください。

## 開発版の起動

macOS 14以降、XcodeまたはSwiftツールチェーンが必要です。このMacのアーキテクチャ向けにビルドします。

通常のビルドは **Charatify Dev** を作成します。Dev版では更新確認を無効にします。

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
| 更新確認 | 無効 | GitHub Releasesで安定版を確認。設定でNightlyも追加可能 |
| 署名 | `DEV_CODE_SIGN_IDENTITY`、未設定ならアドホック | アドホック署名、またはDeveloper ID署名・公証 |

アクセシビリティ許可・このアプリのテスト通知の許可・ログイン項目は、それぞれのアプリで設定してください。開発版のDockアイコンにはDEVの印が付き、メニューバーのツールチップとメニューにも開発版の名前が表示されます。開発版の初回起動時は設定・メディアを新規に作成し、公開版から自動コピーしません。両方の監視が有効だと通知が二重に表示されるため、開発時は必要に応じて公開版の監視を一時停止してください。

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

メニューバーのアプリアイコンから設定・テスト・一時停止・終了を操作できます。設定画面を閉じても監視は続きます。「ログイン時に起動」はユーザーが設定から有効にした場合のみ登録します。

## 挙動

- キャラクター欄の「表示スタイル」で、自動・元の形・角丸・円形・四角を選べます。角丸の強さ、枠線の太さと色、影、枠への収め方（全体／枠いっぱい）を変更でき、設定は保存されます。左のプレビューと通知表示にすぐ反映します。
- 動画はアプリ内へコピーするため、読み込み後に元のファイルを移動しても使えます。通知の表示中と設定プレビューの表示中に再生し、通知を閉じたり設定ウインドウを隠したりすると停止・一時停止します。動画のコーデックによっては再生できません。読み込みに失敗した場合は現在のキャラクターを保持します。
- 動画の最初のフレームをアイコン用の静止画として使います。通知側の円形・角丸設定はアイコンの合成仕様を変更しません。

- メニューバーの「Dockに表示」、または設定の「表示と起動」→「Dockに表示」でDockアイコンを切り替えられます。初期値はオフです。Dockを非表示にしてもメニューバーから設定やテストを開け、通知監視は続きます。表示設定は次回起動時も引き継がれます。
- キャラクターを選ぶと、その顔を吹き出しに収めたアイコンを生成します。Visionで顔を検出し、設定の「アイコンの顔位置」でドラッグ・ピンチ・スライダーによる調整ができます。位置と拡大率は自動保存されます。顔が見つからない場合や複数ある場合は、この画面で合わせてください。
- メニューバーの既定アイコンは、Charatifyの「おしゃべりスプライト」です。設定の「表示と起動」→「メニューバーアイコンをキャラクターに変更」をオンにすると、選んだキャラクターのアイコンに切り替わります。
- 「Dockアイコンをキャラクターに変更」の初期値はオンです。メニューバーとDockのアイコン設定は個別に選べ、次回起動時も引き継がれます。キャラクター未設定時はそれぞれアプリ既定のアイコンになります。
- 64〜1024pxは吹き出し、16・32pxは白い角丸地に大きな顔を描く専用版です。「標準に戻す」でバンドル既定の「おしゃべりスプライト」アイコンに戻ります。バンドルのアイコン自体は変更しません。
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

## 自動リリース

GitHub Actionsの **Release DMG** は、安定版タグのpushでUniversal版DMG、更新用ZIP、`SHA256SUMS` をGitHub Releasesへ公開します。Appleの署名・公証を設定していない場合も、更新に対応したアドホック署名の安定版を公開します。NightlyはGitHubのプレリリースとして公開します。

### ローカル・Actionsでのインストール確認

```sh
APP_VERSION=0.2.0 make dmg
```

`build/dmg/` に `Charatify-0.2.0-unnotarized.dmg`、`Charatify-0.2.0-macos-universal-unnotarized.zip`、`SHA256SUMS` を生成します。GitHub Actionsの **Release DMG → Run workflow** で `channel=dmg` とバージョンを指定すると、同じファイルがActionsのArtifactsに保存されます。

### Developer ID署名と公証

署名・公証済みで公開する場合は、リポジトリの **Settings → Secrets and variables → Actions** に以下を設定し、Repository variable `RELEASE_NOTARIZE` を `true` にします。既存の `RELEASE_PUBLISH_ENABLED=true` も署名・公証の指定として使用できます。

| 種別 | 名前 | 内容 |
| --- | --- | --- |
| Variable | `APPLE_SIGN_IDENTITY` | `Developer ID Application: 名前 (TEAMID)` |
| Secret | `APPLE_CERTIFICATE_P12` | 秘密鍵を含むDeveloper ID証明書のp12をBase64化したもの |
| Secret | `APPLE_CERTIFICATE_PASSWORD` | p12のパスワード |
| Secret | `APPLE_ID` | Apple DeveloperのApple ID |
| Secret | `APPLE_TEAM_ID` | Team ID |
| Secret | `APPLE_APP_SPECIFIC_PASSWORD` | 公証用のアプリ用パスワード |

ローカルでは `CODE_SIGN_IDENTITY`、`APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_SPECIFIC_PASSWORD` を設定したうえで `APP_VERSION=0.2.0 make release` を実行すると、署名・公証済みのパッケージを `build/release/` に生成できます。Developer ID署名版は、そのアプリと同じ署名要件を満たすアップデートを受け取ります。初めてアドホック署名版からDeveloper ID署名版に切り替える際は、アクセシビリティなどの権限の再許可が必要になる場合があります。

### バージョンと公開

| コマンド | 最新の安定版タグが `0.2.1` の場合 |
| --- | --- |
| `make version-major` | `1.0.0` を作成 |
| `make version-minor` | `0.3.0` を作成 |
| `make version-patch` | `0.2.2` を作成 |
| `make version-nightly` | GitHub Actionsに `main` のNightly作成を依頼 |

安定版の公開は、新しいバージョンタグを確認済みのコミットに作成してpushすると始まります。タグ名だけ確認するには `python3 scripts/release_version.py tag patch --dry-run` を使用します。公開済みのファイルを差し替える必要がある場合は、新しいバージョンを使用してください。

Nightlyのタグは `<次のパッチ版>-nightly.<UTC日付>.<実行番号>` です。手動では `make version-nightly` または **Release DMG → Run workflow** の `channel=nightly` を使います。Repository variable `NIGHTLY_PUBLISH_ENABLED=true` を設定すると、毎日19:37 UTCに `main` を確認し、対象コミットのNightlyがまだなければ公開します。

公開途中で失敗した場合は、Actionsの「Re-run jobs」で再開できます。公開前のドラフトにDMG、ZIP、チェックサムがそろってから公開します。

## 検証

`swift test` は複数画面の座標（負の原点・小さな画面・相対位置の復元）、既存通知の再生抑止、同文の別通知、本文と操作ボタンの分離、複数バナーの分離を検証します。実通知の読み取りには上記の権限と手動確認が別途必要です。

`make test` は配布処理のテストに加え、公開版・Dev版のBundle IDを持つテスト用アプリで、実際の設定初期化も検証します。設定値はプロセス内だけに与え、ユーザーの設定への書き込みは行いません。

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
