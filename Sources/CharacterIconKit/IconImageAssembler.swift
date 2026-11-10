import AppKit

@MainActor
public enum IconImageAssembler {
    public static func image(pngs: [Int: Data]) throws -> NSImage {
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        image.prefersColorMatch = false
        for size in IconGeometry.sizes {
            guard let data = pngs[size], let rep = NSBitmapImageRep(data: data),
                  rep.pixelsWide == size, rep.pixelsHigh == size else { throw IconError.renderFailed }
            // All representations describe the same logical image at different raster resolutions.
            rep.size = image.size
            image.addRepresentation(rep)
        }
        return image
    }
}
