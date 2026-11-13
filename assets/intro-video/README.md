# Charatify 紹介動画

「通知に、あなたらしさを。」をテーマにした日本語紹介動画です。

- **完成動画**: [Charatify-intro-ja.mp4](Charatify-intro-ja.mp4)
- **ナレーションのみ**: [Charatify-narration-r1.wav](Charatify-narration-r1.wav)
- **台本**: [narration.txt](narration.txt)
- **要約字幕**: [Charatify-intro-ja.srt](Charatify-intro-ja.srt)
- **絵コンテ**: [storyboard.jpg](storyboard.jpg)
- **ブラウザで確認**: [preview.html](preview.html)

51.03秒 / 1920×1080 / 30fps / H.264 + AAC / MP4。
字幕は動画内にも表示しています。BGMと通知音はプログラムで合成したオリジナルです。

## 内容

1. 通知に、あなたらしさを。
2. 通知バナーをキャラクターと吹き出しで表示
3. 画像・動画の対応と表示スタイル
4. ディスプレイ選択と配置
5. 通知本文のローカル処理
6. 権限許可 → キャラクター選択 → 表示テスト

画面は説明用の動作イメージです。実アプリの画面収録ではありません。
キャラクター例には `../icon-candidates/v1/` の既存画像を使っています。
アプリの機能と制約は制作時のリポジトリの README に基づきます。

## 音声

ユーザー指定の `http://voice-builder.devportal.localhost` で生成しました。
**「お姉さんの声 — Canonical r1」**を6つの音声すべてのreferenceに指定しています。
サービスのアクティブなr2は使用していません。

- Reference ID: `canonical:09d08b35-dd8e-43b4-9563-d1a80675d18b:r001`
- モデル: Irodori-TTS v4.1 Small MF
- Seed: 12345
- 設定: `voice-settings.json`
- 個別音声と生成メタデータ: `audio/00.wav`〜`05.wav` と同名JSON

## 再生成

macOS、Python（Pillow・NumPy）、ffmpeg / ffprobe が必要です。

```sh
# 既存の6本の音声から動画を再出力
python3 assets/intro-video/render.py

# 絵コンテの出力
python3 assets/intro-video/render.py --preview

# 音声がない場合に指定のVoice Builderで生成
python3 assets/intro-video/generate_audio.py
```

映像は `render.py`、台本と要約字幕は `script.json` から編集できます。

## 確認済み

- 全編のデコード、映像・音声の長さ、H.264/AACストリーム
- 各シーンのレイアウトと書き出し動画の通知画面
- 全6音声のメタデータでr1の一致
- 音量: Integrated -16.02 LUFS / True peak -3.91 dBTP
