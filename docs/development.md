# 開発・配布方針

日常の変更はCharatify Devで確認し、公開版は普段使いのために保持します。コードは共通にし、ビルド時にアプリの識別情報・署名・更新設定を切り替えます。

## 日常の開発

- `make test` でテスト、`make dev` で開発版を起動します。`make build` はDev版の生成、`make run` は `make dev` と同じです。
- Dev版は別のBundle ID、UserDefaults、Application Support、画像・動画・アイコンキャッシュを使用します。公開版のデータを自動移行・削除しません。
- 権限はCharatify Devに個別に許可します。署名には `DEV_CODE_SIGN_IDENTITY` でApple Development証明書を指定することを推奨します。
- ログイン時起動は各アプリで明示的に有効化します。Dev版に公開版のログイン項目を引き継がせません。
- 公開版とDev版は同時起動できます。通知の重複表示を避けたいときは、片方の監視を一時停止してください。
- `make dmg-dev` は `build/dev-dmg/Charatify-Dev.dmg` を作成します。これはDev版のインストール確認用で、GitHub Releasesの更新対象外です。

## ローカライズ

UIは日本語と英語に対応し、それ以外の言語のmacOSでは英語で表示します。ソース中の日本語文字列をそのままキーとして使います。

- SwiftUIの `Text("…")`・`Button("…")` などのリテラルは自動で翻訳対象になります。`String` として扱う文字列（メニュー項目、エラー文、状態表示、三項演算子の結果など）は `String(localized: "…")` で書きます。
- 文字列を追加・変更したら `Resources/en.lproj/Localizable.strings` に英訳を、`Resources/ja.lproj/Localizable.strings` に同じキーを値にした行を追加します。補間した値は整数が `%lld`、文字列が `%@` になります。
- `make test` の `tests-localization` が英訳の漏れ・不要なキー・書式指定子の不一致を検出します。
- 英語表示の確認は `open "build/Charatify Dev.app" --args -AppleLanguages '(en)'` で行えます。

## PRとmain

PRとmainのCIでテストとUniversal版Devアプリのビルドを行います。mainへのpushでは公開しません。mainを公開可能な状態に保ち、新機能・バグ修正はPRで確認してから取り込みます。

設定・データ形式を変更するときは、旧形式を読めるようにして移行をテストします。公開版のBundle IDと保存先は継続利用し、変更が必要な場合は移行方法を先に決めてください。

## 公開前の確認

`APP_VERSION=0.2.0 make dmg` でUniversal版DMGと更新用ZIP、`SHA256SUMS` を作成できます。GitHub Actionsの **Release DMG → Run workflow** の `channel=dmg` でも同じファイルを生成し、Artifactsに保存します。Developer ID署名と公証を確認する場合は、署名設定を済ませて `make release` を実行します。

生成した公開版DMGで次を確認してください。

1. 新規ユーザーでDMGを開き、Applicationsへコピーして起動できること。
2. 初回のアクセシビリティ許可、テスト通知、実通知の読み取りが動作すること。
3. ログイン起動、Dock表示、画像・動画の保存と再起動後の復元が動作すること。
4. 現行公開版から上書き更新し、設定・メディアが引き継がれること。
5. GitHub Releasesに必要なファイルがそろった版を、書き込み可能な場所にインストールした旧版から更新できること。Nightlyを含める設定のオン・オフで更新候補が変わり、Nightlyより新しい安定版へ更新できることも確認します。
6. 更新確認をオフにした場合に自動確認しないこと、Dev版で公開版の設定・メディアが変わっていないこと。

公開版のDMGは公開版の保存先を使用します。日常利用のデータを守るため、最終確認はテスト用macOSユーザーで行ってください。署名方式の初回切り替えやOSの変更による再許可は、通常の更新による権限引き継ぎと分けて確認します。

## 公開

確認済みのコミットをmainへ反映してから安定版タグをpushすると、GitHub ActionsがDMGと更新用ZIP、`SHA256SUMS` を作成してGitHub Releasesに公開します。Nightlyは `make version-nightly` から手動実行できます。`NIGHTLY_PUBLISH_ENABLED=true` を設定すると定期実行します。

署名・公証済みで公開する場合は、Appleの設定とRepository variable `RELEASE_NOTARIZE=true` が必要です。公開済みのDMGやZIPの修正は新しいバージョンで公開します。CIは安定版とNightlyで共通の実行番号から `CFBundleVersion` を決めます。公開前に失敗した場合は同じActions実行を再実行できます。

初期設定と必要なGitHub Secrets / Variablesは [README](../README.md#自動リリース) を参照してください。
