# アプリアイコン候補 v1

内蔵の image_gen ツールで生成した候補です。B「おしゃべりスプライト」をデフォルトに採用しています。組み込み用画像は [`Resources/Charatify.png`](../../../Resources/Charatify.png) に原本をコピーしています。ビルド時に角丸の輪郭でクリップして外周を透過し、各サイズの `.icns` を生成します。開発版にはDEVの印を付けます。

- **A｜ふきだしねこ**: [PNG](01-bubble-cat.png)
- **B｜おしゃべりスプライト**: [PNG](02-bubble-sprite.png)
- **C｜ことりのメッセンジャー**: [PNG](03-messenger-bird.png)
- **D｜ミニマルな通知フェイス**: [PNG](04-ping-face.png)

## 比較画像

[4案を並べた画像](comparison.png)。内蔵 image_gen の合成機能で作成した比較用イメージです。採用する原本は上記の各PNGを使用します。

### 比較画像のプロンプト

```text
Use case: compositing. Asset type: a single visual comparison board of four already-generated macOS application icon candidates. Input images 1, 2, 3, 4 are the exact icon artwork to place, not style references. Compose these four supplied icons onto one clean compact 2x2 board, square or slightly portrait, on a very light neutral warm gray background. Preserve the original icon designs, their colors, proportions, faces, silhouettes and existing details exactly; do not redesign, recolor, decorate, or add anything to the icon artworks. Display all four at identical size, with consistent narrow margins and substantial icon size. Top left: image 1 (green cat) with the simple label 'A' beneath. Top right: image 2 (purple sprite) with label 'B' beneath. Bottom left: image 3 (orange bird) with label 'C' beneath. Bottom right: image 4 (navy speech bubble face) with label 'D' beneath. Labels must be dark charcoal, clean modern sans-serif, and easy to read. Only text is A, B, C, D. No title, descriptions, captions, rankings, scorecards, mockups, watermarks, device frames, additional graphics, gradients outside the supplied artwork, or extra variants. This board is for the user to visually compare the four exact existing candidates.
```

## 使用したプロンプト

### A｜ふきだしねこ

```text
Use case: logo-brand. Asset type: macOS desktop app icon concept, one square 1024x1024 icon. Product: a utility that shows a chosen character with a speech bubble when a system notification arrives. Primary request: a premium, friendly icon of a tiny white cat mascot fused with a speech bubble. The speech bubble itself is the cat's softly rounded face: two subtle cat ears at top, simple dark eyes, a small smile, and a single speech-tail at lower right. A tiny coral notification dot at upper right. Style: restrained, beautifully crafted tactile 3D macOS icon, rounded sculptural forms, soft enamel finish, subtle material depth, very legible silhouette at 32px. Background: one rounded-square jade-teal app tile, elegant soft lighting and subtle gradient, straight-on centered view with generous safe margin. Full square image with pale neutral surround outside the rounded tile. Constraints: a single icon, no mockup, no comparison grid, no text, no letters, no numbers, no watermark, no excessive detail, no hardware, no existing brand marks.
```

### B｜おしゃべりスプライト

```text
Use case: logo-brand. Asset type: macOS desktop app icon concept, one square 1024x1024 icon. Product: a utility where a character appears only when a system notification arrives, with its message in a speech bubble. Primary request: a small friendly white floating sprite, its body shaped like a chat bubble with two tiny rounded feet and two simple dark eyes, holding a smaller lavender chat bubble. A single warm amber notification dot. Style: premium soft clay 3D macOS icon, joyful yet calm, simple sculptural shapes, excellent small-size readability, gentle shadow. Composition: large centered sprite filling about 70 percent of a rounded-square soft periwinkle-indigo app tile, straight-on, carefully balanced proportions, generous safe margin. Full square image, pale neutral surround outside rounded tile. Constraints: one icon only; no text, letters, numerals, wordmarks, screenshots, interface panels, scene background, watermark, recognizable copyrighted characters, comparison grid, glossy toy clutter.
```

### C｜ことりのメッセンジャー

```text
Use case: logo-brand. Asset type: macOS desktop app icon concept, one square 1024x1024 icon. Product: a utility that delivers system notifications through a small chosen character and a speech bubble. Primary request: an original small round apricot-orange messenger bird with a cream face, tiny dark eyes, a small beak, and one simple cream speech bubble next to its head, as if speaking. A warm, welcoming character-based app identity. Style: exceptionally polished minimal illustrated 3D macOS icon, matte ceramic finish, plump simple shapes, not photorealistic, bold uncluttered silhouette recognizable at 32px. Composition: the bird and speech bubble form one compact centered emblem on an ivory rounded-square tile with a delicate peach tint and subtle dimensional edge; soft warm lighting, straight-on, generous safe margin. Full square image, pale neutral surround outside tile. Constraints: only one icon; no text, letters, numbers, detailed feathers, landscape, paper envelope, badge counts, grid, watermarks, or known franchise characters.
```

### D｜ミニマルな通知フェイス

```text
Use case: logo-brand. Asset type: macOS desktop app icon concept, one square 1024x1024 icon. Product: a notification utility that makes a chosen character appear and speak a message. Primary request: a highly reduced white rounded speech bubble with two pill-shaped dark eyes, with one small coral-red notification dot hovering near its upper right corner. The bubble feels like a subtle friendly character without animal anatomy. Style: sophisticated macOS productivity app icon, restrained high-quality 3D frosted glass and porcelain, clear crisp silhouette, gentle depth and shadow, minimal and professional, readable at tiny sizes. Composition: large simple centered white bubble on a rich dark navy rounded-square app tile, subtle teal rim lighting, straight-on, generous safe margin. Full square image, pale neutral surround outside tile. Constraints: one icon only; no text, wordmarks, letters, numbers, grid, mockup, extra symbols, busy reflections, scenery, watermark, or existing brand designs.
```

