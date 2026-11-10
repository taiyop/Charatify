import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit
@testable import CharacterIconKit

final class CharacterIconKitTests: XCTestCase {
    private func fixture(blue: CGFloat = 0.8) throws -> Data {
        let c = try XCTUnwrap(CGContext(data: nil, width: 160, height: 320, bitsPerComponent: 8, bytesPerRow: 640,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        c.setFillColor(CGColor(srgbRed: 0.1, green: 0.4, blue: blue, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 160, height: 320))
        c.setFillColor(CGColor(srgbRed: 0.9, green: 0.8, blue: 0.2, alpha: 1)); c.fill(CGRect(x: 0, y: 160, width: 160, height: 160))
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try XCTUnwrap(c.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    func testAspectFillPreservesRatioAndCoversClipAtEdges() {
        for crop in [IconCrop(), IconCrop(x: 0, y: 1, scale: 4), IconCrop(x: 1, y: 0)] {
            let r = IconGeometry.imageRect(source: CGSize(width: 160, height: 320), target: IconGeometry.bubbleBounds, crop: crop)
            XCTAssertEqual(r.width / r.height, 0.5, accuracy: 0.0001)
            XCTAssertTrue(r.contains(IconGeometry.bubbleBounds))
        }
        XCTAssertEqual(IconGeometry.topLeftRect(fromVision: CGRect(x: 0.2, y: 0.7, width: 0.2, height: 0.1)).minY, 0.2, accuracy: 0.0001)
        XCTAssertEqual(IconCrop(x: .nan, y: -1, scale: .infinity).clamped, IconCrop(x: 0.5, y: 0, scale: 1))
    }

    func testRepresentationsCacheAndCropInvalidation() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = CharacterIconService(cacheRoot: directory)
        let data = try fixture()
        let first = try await service.prepare(data: data, configuration: nil, detector: { _ in [] })
        XCTAssertFalse(first.cacheHit)
        XCTAssertEqual(first.configuration.estimate, .noFace)
        XCTAssertEqual(Set(first.pngs.keys), Set(IconGeometry.sizes))
        for (size, png) in first.pngs {
            let image = try IconComposer.decode(png)
            XCTAssertEqual(image.width, size); XCTAssertEqual(image.height, size)
        }
        let second = try await service.prepare(data: data, configuration: first.configuration, detector: { _ in XCTFail("Must reuse stored crop"); return [] })
        XCTAssertTrue(second.cacheHit)
        XCTAssertEqual(second.pngs, first.pngs)
        let adjusted = CharacterIconConfiguration(sourceHash: first.configuration.sourceHash, crop: IconCrop(x: 0.7, y: 0.2, scale: 2), estimate: .manual)
        let third = try await service.prepare(data: data, configuration: adjusted)
        XCTAssertFalse(third.cacheHit)
        XCTAssertNotEqual(first.pngs[64], third.pngs[64])
        let changed = try await service.prepare(data: fixture(blue: 0.5), configuration: adjusted, detector: { _ in [] })
        XCTAssertFalse(changed.cacheHit)
        XCTAssertEqual(changed.configuration.crop, IconCrop())
    }

    func testFaceDetectionFallbacksAndCorruptCacheRecovery() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = CharacterIconService(cacheRoot: directory)
        let data = try fixture()
        let face = CGRect(x: 0.3, y: 0.1, width: 0.2, height: 0.1)
        let detected = try await service.prepare(data: data, configuration: nil, detector: { _ in [face] })
        XCTAssertEqual(detected.configuration.estimate, .detected)
        XCTAssertGreaterThan(detected.configuration.crop.scale, 1)
        let multiple = try await service.prepare(data: data, configuration: nil, detector: { _ in [face, face] })
        XCTAssertEqual(multiple.configuration.estimate, .multipleFaces)
        XCTAssertEqual(multiple.configuration.crop, IconCrop())
        let failed = try await service.prepare(data: data, configuration: nil, detector: { _ in throw IconError.invalidImage })
        XCTAssertEqual(failed.configuration.estimate, .detectionFailed)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for folder in files { try Data("broken".utf8).write(to: folder.appendingPathComponent("icon-16.png")) }
        let recovered = try await service.prepare(data: data, configuration: failed.configuration)
        XCTAssertFalse(recovered.cacheHit)
        XCTAssertEqual(try IconComposer.decode(XCTUnwrap(recovered.pngs[16])).width, 16)
    }

    func testSmallIconUsesWhiteBaseAndLargeUsesPastel() throws {
        let source = try IconComposer.decode(fixture())
        func pixel(_ size: Int, x: Double, y: Double) throws -> [UInt8] {
            let image = try IconComposer.decode(IconComposer.compose(image: source, crop: IconCrop(), size: size))
            let c = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            c.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            let pointer = try XCTUnwrap(c.data).assumingMemoryBound(to: UInt8.self)
            let offset = (Int(y * Double(size)) * size + Int(x * Double(size))) * 4
            return Array(UnsafeBufferPointer(start: pointer + offset, count: 4))
        }
        let small = try pixel(32, x: 0.5, y: 0.11)
        XCTAssertGreaterThan(small[0], 245); XCTAssertGreaterThan(small[1], 245)
        let large = try pixel(64, x: 0.5, y: 0.1)
        XCTAssertLessThan(large[0], 240)
        XCTAssertEqual(try pixel(16, x: 0, y: 0)[3], 0)
        // The source has a yellow top and blue bottom: rendering must preserve orientation.
        let top = try pixel(128, x: 0.5, y: 0.3)
        let bottom = try pixel(128, x: 0.5, y: 0.65)
        XCTAssertGreaterThan(top[0], bottom[0])
    }

    @MainActor
    func testAppKitSelectsDedicatedSmallRepresentations() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let service = CharacterIconService(cacheRoot: directory)
        let rendered = try await service.prepare(data: fixture(), configuration: nil, detector: { _ in [] })
        let image = try IconImageAssembler.image(pngs: rendered.pngs)
        XCTAssertEqual(image.representations.count, 7)
        for size in IconGeometry.sizes {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
            let chosen = try XCTUnwrap(image.bestRepresentation(for: CGRect(x: 0, y: 0, width: size, height: size), context: context, hints: nil))
            XCTAssertEqual(chosen.pixelsWide, size, "AppKit must select the actual \(size)px artwork")
        }
    }
}
