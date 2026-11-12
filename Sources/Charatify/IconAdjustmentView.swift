import SwiftUI
import CharacterIconKit

private struct IconBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var transform = CGAffineTransform(scaleX: rect.width, y: rect.height)
        transform = transform.concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return Path(IconGeometry.bubblePath().copy(using: &transform)!)
    }
}

struct IconAdjustmentView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: CharacterIconController
    @State private var dragStart: IconCrop?
    @State private var pinchStart: IconCrop?
    private var crop: IconCrop { settings.iconConfiguration?.crop ?? IconCrop() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dockアイコンの顔位置").font(.caption.weight(.medium))
            HStack(alignment: .center, spacing: 18) {
                preview.frame(width: 144, height: 144)
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { value in
                        if dragStart == nil { dragStart = crop }
                        guard let start = dragStart, let image = settings.image else { return }
                        let rect = IconGeometry.imageRect(source: image.size, target: IconGeometry.bubbleBounds, crop: start)
                        controller.updateCrop(IconCrop(x: start.x - value.translation.width / (144 * rect.width),
                                                      y: start.y - value.translation.height / (144 * rect.height), scale: start.scale))
                    }.onEnded { _ in dragStart = nil })
                    .simultaneousGesture(MagnificationGesture().onChanged { value in
                        if pinchStart == nil { pinchStart = crop }
                        guard let start = pinchStart else { return }
                        controller.updateCrop(IconCrop(x: start.x, y: start.y, scale: start.scale * value))
                    }.onEnded { _ in pinchStart = nil })
                    .accessibilityLabel("顔位置プレビュー。ドラッグで位置を調整")
                VStack(alignment: .leading, spacing: 10) {
                    Text("左のアイコン内をドラッグして顔を移動\nピンチか下のスライダーで拡大\n変更は自動保存されます")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach([16, 32, 64], id: \.self) { size in
                            if let image = controller.previews[size] {
                                VStack(spacing: 4) {
                                    Image(nsImage: image).resizable().frame(width: CGFloat(size), height: CGFloat(size))
                                    Text("\(size)px").font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.accessibilityLabel("サイズ別アイコン")
                }
            }
            HStack {
                Text("拡大").font(.caption)
                Slider(value: Binding(get: { crop.scale }, set: {
                    controller.updateCrop(IconCrop(x: crop.x, y: crop.y, scale: $0))
                }), in: 1...12).accessibilityLabel("顔の拡大率")
                Text(String(format: "%.1f×", crop.scale)).font(.caption.monospacedDigit()).frame(width: 38)
            }.disabled(settings.iconConfiguration == nil)
            Text(controller.status).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("顔位置を自動検出し直す") { controller.detectAgain() }
                Button("中央に戻す") { controller.updateCrop(IconCrop()) }
                    .disabled(settings.iconConfiguration == nil)
            }.font(.caption)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var preview: some View {
        Canvas { context, size in
            let side = size.width
            // Canvas uses the same top-left geometry as IconComposer; no image layout transforms.
            let tile = Path(roundedRect: CGRect(x: side * 0.04, y: side * 0.04, width: side * 0.92, height: side * 0.92), cornerRadius: side * 0.205)
            context.fill(tile, with: .linearGradient(Gradient(colors: [Color(red: 220/255, green: 233/255, blue: 1), Color(red: 217/255, green: 200/255, blue: 245/255)]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: side)))
            let bubble = IconBubbleShape().path(in: CGRect(origin: .zero, size: size))
            context.fill(bubble, with: .color(controller.hasTransparency ? Color(red: 233/255, green: 223/255, blue: 247/255) : .white))
            var clipped = context
            clipped.clip(to: bubble)
            if let image = settings.image {
                let r = IconGeometry.imageRect(source: image.size, target: IconGeometry.bubbleBounds, crop: crop)
                clipped.draw(Image(nsImage: image), in: CGRect(x: r.minX * side, y: r.minY * side, width: r.width * side, height: r.height * side))
            }
            clipped.stroke(bubble, with: .color(Color(red: 92/255, green: 64/255, blue: 56/255).opacity(0.55)), lineWidth: side * 5/1024)
        }
    }
}
