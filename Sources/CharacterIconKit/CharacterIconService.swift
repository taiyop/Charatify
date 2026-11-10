import Foundation
import CryptoKit
import Vision
import ImageIO
import CoreGraphics

public struct PreparedCharacterIcon: Sendable {
    public let configuration: CharacterIconConfiguration
    public let pngs: [Int: Data]
    public let cacheHit: Bool
    public let hasTransparency: Bool
}

public enum FaceDetector {
    public static func detect(in data: Data) throws -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(data: data, options: [:]).perform([request])
        return (request.results ?? []).map { IconGeometry.topLeftRect(fromVision: $0.boundingBox) }
    }
}

/// Serial worker: rendering, Vision, hashing and all disk access happen off MainActor.
public actor CharacterIconService {
    public static let rendererVersion = 1
    public let cacheRoot: URL

    public init(cacheRoot: URL) { self.cacheRoot = cacheRoot }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public func prepare(sourceURL: URL, configuration: CharacterIconConfiguration?) throws -> PreparedCharacterIcon {
        try prepare(data: Data(contentsOf: sourceURL), configuration: configuration)
    }

    public func prepare(data: Data, configuration: CharacterIconConfiguration?,
                        detector: @Sendable (Data) throws -> [CGRect] = { try FaceDetector.detect(in: $0) }) throws -> PreparedCharacterIcon {
        try Task.checkCancellation()
        let hash = Self.sha256(data)
        let image = try IconComposer.decode(data)
        let config: CharacterIconConfiguration
        if let configuration, configuration.sourceHash == hash {
            config = CharacterIconConfiguration(sourceHash: hash, crop: configuration.crop, estimate: configuration.estimate)
        } else {
            do {
                let faces = try detector(data)
                if faces.count == 1, let face = faces.first, face.width > 0, face.height > 0 {
                    config = CharacterIconConfiguration(sourceHash: hash,
                        crop: IconGeometry.crop(forTopLeftFace: face, imageSize: CGSize(width: image.width, height: image.height)), estimate: .detected)
                } else {
                    config = CharacterIconConfiguration(sourceHash: hash, crop: IconCrop(), estimate: faces.isEmpty ? .noFace : .multipleFaces)
                }
            } catch {
                config = CharacterIconConfiguration(sourceHash: hash, crop: IconCrop(), estimate: .detectionFailed)
            }
        }
        try Task.checkCancellation()
        let key = try cacheKey(configuration: config)
        if let pngs = load(key: key, configuration: config) {
            return PreparedCharacterIcon(configuration: config, pngs: pngs, cacheHit: true, hasTransparency: IconComposer.hasTransparency(image))
        }
        var pngs: [Int: Data] = [:]
        for size in IconGeometry.sizes {
            try Task.checkCancellation()
            pngs[size] = try IconComposer.compose(image: image, crop: config.crop, size: size)
        }
        try Task.checkCancellation()
        // Cache failures must not stop a successfully rendered icon from being shown.
        try? save(pngs, key: key, configuration: config)
        return PreparedCharacterIcon(configuration: config, pngs: pngs, cacheHit: false, hasTransparency: IconComposer.hasTransparency(image))
    }

    public func clearCache() {
        guard !Task.isCancelled else { return }
        // Only this feature's dedicated directory, never the original character image.
        try? FileManager.default.removeItem(at: cacheRoot)
    }

    private struct Manifest: Codable {
        let rendererVersion: Int
        let sourceHash: String
        let crop: IconCrop
        let pngHashes: [Int: String]
    }

    private func cacheKey(configuration: CharacterIconConfiguration) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        struct Identity: Encodable { let version: Int; let sourceHash: String; let crop: IconCrop }
        return Self.sha256(try encoder.encode(Identity(version: Self.rendererVersion, sourceHash: configuration.sourceHash, crop: configuration.crop)))
    }

    private func load(key: String, configuration: CharacterIconConfiguration) -> [Int: Data]? {
        let directory = cacheRoot.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.rendererVersion == Self.rendererVersion, manifest.sourceHash == configuration.sourceHash,
              manifest.crop == configuration.crop else { return nil }
        var pngs: [Int: Data] = [:]
        for size in IconGeometry.sizes {
            guard let png = try? Data(contentsOf: directory.appendingPathComponent("icon-\(size).png")),
                  Self.sha256(png) == manifest.pngHashes[size],
                  let source = CGImageSourceCreateWithData(png as CFData, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  props[kCGImagePropertyPixelWidth] as? Int == size, props[kCGImagePropertyPixelHeight] as? Int == size else { return nil }
            pngs[size] = png
        }
        return pngs
    }

    private func save(_ pngs: [Int: Data], key: String, configuration: CharacterIconConfiguration) throws {
        let fm = FileManager.default
        let directory = cacheRoot.appendingPathComponent(key)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for (size, png) in pngs { try png.write(to: directory.appendingPathComponent("icon-\(size).png"), options: .atomic) }
        let manifest = Manifest(rendererVersion: Self.rendererVersion, sourceHash: configuration.sourceHash,
                                crop: configuration.crop, pngHashes: pngs.mapValues(Self.sha256))
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        // Bound disk use during repeated crop edits. All entries are feature-owned, hashed directories.
        let entries = (try? fm.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let old = entries.filter { $0.lastPathComponent != key && $0.lastPathComponent.count == 64 }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for entry in old.dropFirst(7) { try? fm.removeItem(at: entry) }
    }
}
