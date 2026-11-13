import AppKit
import Combine
import UniformTypeIdentifiers
import CharacterIconKit
import CharacterMediaKit
import AppConfiguration

@MainActor
final class SettingsStore: ObservableObject {
    @Published var enabled: Bool { didSet { save() } }
    @Published var displayID: String { didSet { save() } }
    @Published var x: Double { didSet { save() } }
    @Published var y: Double { didSet { save() } }
    @Published var duration: Double { didSet { save() } }
    @Published var characterSize: Double { didSet { save() } }
    @Published var showInDock: Bool { didSet { save() } }
    @Published var showAppIcon: Bool { didSet { save() } }
    @Published var iconConfiguration: CharacterIconConfiguration? { didSet {
        defaults.set(try? JSONEncoder().encode(iconConfiguration), forKey: "iconConfiguration")
    } }
    @Published var appearance: CharacterAppearance { didSet { save() } }
    @Published private(set) var media: StoredCharacterMedia?
    @Published private(set) var isImporting = false
    @Published var image: NSImage?
    @Published var imageError: String?
    @Published var screens: [NSScreen] = NSScreen.screens
    private let defaults: UserDefaults
    private lazy var mediaStore = CharacterMediaStore(root: Self.mediaRoot)

    init() {
        // The app's own bundle ID is invalid as a suite name. Standard defaults
        // already use that ID, keeping release and Dev settings separate.
        let d = UserDefaults.standard
        defaults = d
        enabled = d.object(forKey: "enabled") as? Bool ?? true
        displayID = d.string(forKey: "displayID") ?? "main"
        x = d.object(forKey: "x") as? Double ?? 0.5
        y = d.object(forKey: "y") as? Double ?? 0.0
        duration = min(30, max(3, d.object(forKey: "duration") as? Double ?? 8))
        characterSize = min(200, max(80, d.object(forKey: "characterSize") as? Double ?? 140))
        showInDock = d.bool(forKey: "showInDock")
        showAppIcon = d.object(forKey: "showAppIcon") as? Bool ?? true
        iconConfiguration = d.data(forKey: "iconConfiguration").flatMap { try? JSONDecoder().decode(CharacterIconConfiguration.self, from: $0) }
        appearance = (d.data(forKey: "characterAppearance").flatMap { try? JSONDecoder().decode(CharacterAppearance.self, from: $0) } ?? CharacterAppearance()).clamped
        media = try? CharacterMediaStore.load(in: Self.mediaRoot)
        image = NSImage(contentsOf: media?.posterURL(in: Self.mediaRoot) ?? Self.imageURL)
        if FileManager.default.fileExists(atPath: Self.mediaRoot.appendingPathComponent("media.json").path), media == nil {
            imageError = CharacterMediaError.invalidSavedMedia.localizedDescription
        }
    }

    static var imageURL: URL {
        mediaRoot.appendingPathComponent("character.png")
    }

    static var mediaRoot: URL {
        AppIdentity.current.mediaRoot(in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }
    var currentImageURL: URL { media?.posterURL(in: Self.mediaRoot) ?? Self.imageURL }
    var videoURL: URL? { media?.videoURL(in: Self.mediaRoot) }

    static func id(for screen: NSScreen) -> String {
        // UUID survives display reordering/reconnects; an index does not.
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return "unknown" }
        if let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return number.stringValue
    }

    var selectedScreen: NSScreen? {
        // NSScreen.screens.first is the designated primary display, unlike NSScreen.main
        // which follows the key window (often on the side display).
        screens.first(where: { Self.id(for: $0) == displayID }) ?? screens.first
    }

    var missingDisplay: Bool {
        displayID != "main" && !screens.contains(where: { Self.id(for: $0) == displayID })
    }

    func refreshScreens() { screens = NSScreen.screens }

    func chooseImage() { chooseMedia(.image) }
    func chooseVideo() { chooseMedia(.video) }

    private func chooseMedia(_ kind: CharacterMediaKind) {
        guard !isImporting else { return }
        let picker = NSOpenPanel()
        picker.allowedContentTypes = kind == .video ? [.mpeg4Movie, .quickTimeMovie, UTType(filenameExtension: "m4v") ?? .movie] : [.png, .jpeg, .tiff, .heic]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        picker.message = kind == .video ? "キャラクター動画を選択してください。200MB以下のMP4・MOV・M4Vに対応します。" : "キャラクター画像を選択してください。透過PNGがおすすめです。"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        isImporting = true
        imageError = nil
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() }; isImporting = false }
            do {
                let imported = try await mediaStore.importFile(url, kind: kind)
                media = imported
                image = NSImage(contentsOf: imported.posterURL(in: Self.mediaRoot))
            } catch { imageError = error.localizedDescription }
        }
    }

    func resetImage() {
        guard !isImporting else { return }
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                try await mediaStore.reset()
                media = nil
                image = nil
                iconConfiguration = nil
                imageError = nil
            } catch { imageError = error.localizedDescription }
        }
    }

    private func save() {
        defaults.set(enabled, forKey: "enabled")
        defaults.set(displayID, forKey: "displayID")
        defaults.set(x, forKey: "x"); defaults.set(y, forKey: "y")
        defaults.set(duration, forKey: "duration")
        defaults.set(characterSize, forKey: "characterSize")
        defaults.set(showInDock, forKey: "showInDock")
        defaults.set(showAppIcon, forKey: "showAppIcon")
        defaults.set(try? JSONEncoder().encode(appearance.clamped), forKey: "characterAppearance")
    }
}

