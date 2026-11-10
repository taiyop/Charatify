import XCTest
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
@testable import CharacterMediaKit

final class CharacterMediaKitTests: XCTestCase {
    private func workspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func image(at url: URL) throws {
        let c = try XCTUnwrap(CGContext(data: nil, width: 120, height: 200, bitsPerComponent: 8, bytesPerRow: 480,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        c.setFillColor(CGColor(srgbRed: 0.2, green: 0.7, blue: 0.8, alpha: 1))
        c.fill(CGRect(x: 0, y: 0, width: 120, height: 200))
        let output = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(output, try XCTUnwrap(c.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(output))
    }

    /// Generates local footage, without downloading or depending on user media.
    private func video(at url: URL, rotated: Bool = false) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 96])
        if rotated { input.transform = CGAffineTransform(rotationAngle: .pi / 2).translatedBy(x: 0, y: -96) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 96,
            kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        writer.add(input)
        guard writer.startWriting() else { throw try XCTUnwrap(writer.error) }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            var attempts = 0
            while !input.isReadyForMoreMediaData {
                attempts += 1
                guard attempts < 1000 else { throw CharacterMediaError.invalidVideo }
                try await Task.sleep(for: .milliseconds(5))
            }
            var optionalBuffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &optionalBuffer), kCVReturnSuccess)
            let buffer = try XCTUnwrap(optionalBuffer)
            CVPixelBufferLockBaseAddress(buffer, [])
            let c = try XCTUnwrap(CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 160, height: 96, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue))
            c.setFillColor(CGColor(srgbRed: 0.15, green: 0.65, blue: 0.7, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 160, height: 96))
            c.setFillColor(CGColor(srgbRed: 1, green: 0.8, blue: 0.3, alpha: 1)); c.fillEllipse(in: CGRect(x: 8 + frame * 3, y: 25, width: 36, height: 36))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 15)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }

    func testVideoImportPersistsPosterAndSurvivesOriginalRemoval() async throws {
        let dir = try workspace(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.mov")
        try await video(at: source, rotated: true)
        let root = dir.appendingPathComponent("saved")
        let store = CharacterMediaStore(root: root)
        let media = try await store.importFile(source, kind: .video)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try CharacterMediaStore.load(in: root), media)
        let asset = AVURLAsset(url: try XCTUnwrap(media.videoURL(in: root)))
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
        let sourceImage = try XCTUnwrap(CGImageSourceCreateWithURL(media.posterURL(in: root) as CFURL, nil))
        let poster = try XCTUnwrap(CGImageSourceCreateImageAtIndex(sourceImage, 0, nil))
        XCTAssertEqual(poster.width, 96); XCTAssertEqual(poster.height, 160, "Poster must honor video rotation")
        try await store.reset()
        XCTAssertNil(try CharacterMediaStore.load(in: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: media.directory(in: root).path))
    }

    func testInvalidImportPreservesPreviousImageAndReplacementCleansUp() async throws {
        let dir = try workspace(); defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appendingPathComponent("saved")
        let store = CharacterMediaStore(root: root)
        let source = dir.appendingPathComponent("source.png")
        try image(at: source)
        let first = try await store.importFile(source, kind: .image)
        let broken = dir.appendingPathComponent("broken.mp4")
        try Data("not a video".utf8).write(to: broken)
        do { _ = try await store.importFile(broken, kind: .video); XCTFail("Must reject invalid footage") }
        catch { XCTAssertEqual(error as? CharacterMediaError, .invalidVideo) }
        XCTAssertEqual(try CharacterMediaStore.load(in: root), first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.posterURL(in: root).path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "character" }.count, 1)
        let second = try await store.importFile(source, kind: .image)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.directory(in: root).path))
        XCTAssertNil(second.videoURL(in: root))
        XCTAssertEqual(try CharacterMediaStore.load(in: root), second)
        // Reset must not resurrect the legacy PNG on the following launch.
        try image(at: root.appendingPathComponent("character.png"))
        try await store.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("character.png").path))
    }

    func testOversizedVideoIsRejectedBeforeDecoding() async throws {
        let dir = try workspace(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("large.mp4")
        FileManager.default.createFile(atPath: source.path, contents: Data())
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: 200 * 1024 * 1024 + 1); try handle.close()
        let store = CharacterMediaStore(root: dir.appendingPathComponent("saved"))
        do { _ = try await store.importFile(source, kind: .video); XCTFail("Must enforce video size limit") }
        catch { XCTAssertEqual(error as? CharacterMediaError, .videoTooLarge) }
    }

    func testAppearanceRoundTripAndGeometry() throws {
        var style = CharacterAppearance()
        XCTAssertEqual(style.frame(source: CGSize(width: 120, height: 200), size: 100), CGSize(width: 60, height: 100))
        style.shape = .circle; style.borderColor = .pink; style.borderWidth = 5; style.fit = .fit
        XCTAssertEqual(style.frame(source: CGSize(width: 120, height: 200), size: 100), CGSize(width: 100, height: 100))
        XCTAssertEqual(try JSONDecoder().decode(CharacterAppearance.self, from: JSONEncoder().encode(style)), style)
        style.cornerRadius = .nan; style.borderWidth = 50
        XCTAssertEqual(style.clamped.cornerRadius, 0.12); XCTAssertEqual(style.clamped.borderWidth, 8)
    }
}

