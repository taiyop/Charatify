import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public enum CharacterMediaKind: String, Codable, Sendable { case image, video }

public struct StoredCharacterMedia: Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: CharacterMediaKind
    public let videoExtension: String?
    public func directory(in root: URL) -> URL { root.appendingPathComponent(id.uuidString + ".character", isDirectory: true) }
    public func posterURL(in root: URL) -> URL { directory(in: root).appendingPathComponent("poster.png") }
    public func videoURL(in root: URL) -> URL? {
        guard kind == .video, let ext = videoExtension, ["mp4", "mov", "m4v"].contains(ext) else { return nil }
        return directory(in: root).appendingPathComponent("video.\(ext)")
    }
}

public enum CharacterMediaError: LocalizedError, Equatable {
    case invalidImage, imageTooLarge, videoTooLarge, invalidVideo, invalidSavedMedia
    public var errorDescription: String? {
        switch self {
        case .invalidImage: "画像を読み込めません。8192px以下のPNG・JPEG・TIFF・HEICを選んでください。"
        case .imageTooLarge: "画像は25MB以下のファイルを選んでください。"
        case .videoTooLarge: "動画は200MB以下のファイルを選んでください。"
        case .invalidVideo: "動画を再生できません。映像の入ったMP4・MOV・M4Vを選んでください。"
        case .invalidSavedMedia: "保存したキャラクターを読み込めません。画像・動画を選び直してください。"
        }
    }
}

/// Imports are staged in a new owned directory. The manifest is committed last, so a
/// failed import never replaces the previous character. All media I/O is off MainActor.
public actor CharacterMediaStore {
    public let root: URL
    public init(root: URL) { self.root = root }

    public static func load(in root: URL) throws -> StoredCharacterMedia? {
        let manifest = root.appendingPathComponent("media.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
        let media = try JSONDecoder().decode(StoredCharacterMedia.self, from: Data(contentsOf: manifest))
        guard FileManager.default.fileExists(atPath: media.posterURL(in: root).path),
              media.kind != .video || media.videoURL(in: root).map({ FileManager.default.fileExists(atPath: $0.path) }) == true else {
            throw CharacterMediaError.invalidSavedMedia
        }
        return media
    }

    public func importFile(_ source: URL, kind: CharacterMediaKind) async throws -> StoredCharacterMedia {
        let fm = FileManager.default
        let fileSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize <= (kind == .video ? 200 : 25) * 1024 * 1024 else {
            throw kind == .video ? CharacterMediaError.videoTooLarge : .imageTooLarge
        }
        let ext = source.pathExtension.lowercased()
        if kind == .video, !["mp4", "mov", "m4v"].contains(ext) { throw CharacterMediaError.invalidVideo }
        let media = StoredCharacterMedia(id: UUID(), kind: kind, videoExtension: kind == .video ? ext : nil)
        let directory = media.directory(in: root)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var committed = false
        defer { if !committed { try? fm.removeItem(at: directory) } }
        let poster: CGImage
        if kind == .video, let destination = media.videoURL(in: root) {
            try fm.copyItem(at: source, to: destination)
            let asset = AVURLAsset(url: destination)
            do {
                let playable = try await asset.load(.isPlayable)
                let duration = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard playable, duration.seconds.isFinite, duration.seconds > 0, !tracks.isEmpty else { throw CharacterMediaError.invalidVideo }
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 2048, height: 2048)
                poster = try await generator.image(at: .zero).image
            } catch is CancellationError { throw CancellationError() }
            catch { throw CharacterMediaError.invalidVideo }
        } else {
            guard let sourceImage = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(sourceImage, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 8192, height <= 8192,
                  let image = CGImageSourceCreateThumbnailAtIndex(sourceImage, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 8192
                  ] as CFDictionary) else { throw CharacterMediaError.invalidImage }
            poster = image
        }
        try Task.checkCancellation()
        guard let output = CGImageDestinationCreateWithURL(media.posterURL(in: root) as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CharacterMediaError.invalidImage }
        CGImageDestinationAddImage(output, poster, nil)
        guard CGImageDestinationFinalize(output) else { throw CharacterMediaError.invalidImage }
        try Task.checkCancellation()
        let previous = try? Self.load(in: root)
        try JSONEncoder().encode(media).write(to: root.appendingPathComponent("media.json"), options: .atomic)
        committed = true
        if let previous { try? fm.removeItem(at: previous.directory(in: root)) }
        return media
    }

    public func reset() throws {
        let fm = FileManager.default
        let previous = try? Self.load(in: root)
        let legacy = root.appendingPathComponent("character.png")
        if fm.fileExists(atPath: legacy.path) { try fm.removeItem(at: legacy) }
        let manifest = root.appendingPathComponent("media.json")
        if fm.fileExists(atPath: manifest.path) { try fm.removeItem(at: manifest) }
        if let previous { try? fm.removeItem(at: previous.directory(in: root)) }
    }
}
