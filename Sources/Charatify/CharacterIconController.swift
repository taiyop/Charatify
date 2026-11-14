import AppKit
import Combine
import CharacterIconKit
import AppConfiguration

@MainActor
final class CharacterIconController: ObservableObject {
    @Published private(set) var previews: [Int: NSImage] = [:]
    @Published private(set) var status = ""
    @Published private(set) var hasTransparency = false
    @Published private(set) var currentIcon: NSImage?
    private let settings: SettingsStore
    private let service: CharacterIconService
    private var subscriptions = Set<AnyCancellable>()
    private var task: Task<Void, Never>?
    private var generation = 0
    private var persistingResult = false

    init(settings: SettingsStore) {
        self.settings = settings
        service = CharacterIconService(cacheRoot: SettingsStore.imageURL.deletingLastPathComponent().appendingPathComponent("CharacterIcon", isDirectory: true))
    }

    func start() {
        settings.$image.dropFirst().sink { [weak self] image in
            // @Published emits before storage changes. Invalidate synchronously, then read on next main turn.
            self?.invalidate()
            if image == nil { self?.restoreDefault() }
            Task { @MainActor [weak self] in self?.refresh() }
        }.store(in: &subscriptions)
        settings.$iconConfiguration.dropFirst().removeDuplicates().sink { [weak self] _ in
            guard let self, !self.persistingResult else { return }
            self.invalidate()
            Task { @MainActor [weak self] in self?.refresh(debounce: true) }
        }.store(in: &subscriptions)
        settings.$showInDock.sink { [weak self] visible in
            NSApp.setActivationPolicy(visible ? .regular : .accessory)
            NSApp.dockTile.badgeLabel = AppIdentity.current.isDevelopment ? "DEV" : nil
            if let image = self?.currentIcon { NSApp.applicationIconImage = image }
        }.store(in: &subscriptions)
        refresh()
    }

    func updateCrop(_ crop: IconCrop) {
        guard let config = settings.iconConfiguration else { return }
        settings.iconConfiguration = CharacterIconConfiguration(sourceHash: config.sourceHash, crop: crop, estimate: .manual)
    }

    func detectAgain() { settings.iconConfiguration = nil }

    private func invalidate() { generation += 1; task?.cancel() }

    private func restoreDefault() {
        currentIcon = nil; previews = [:]; status = ""; hasTransparency = false
        NSApp.applicationIconImage = nil
        NSApp.dockTile.badgeLabel = AppIdentity.current.isDevelopment ? "DEV" : nil
    }

    private func refresh(debounce: Bool = false) {
        invalidate()
        guard settings.image != nil else {
            restoreDefault()
            let service = service
            task = Task { await service.clearCache() }
            return
        }
        let expected = generation
        let config = settings.iconConfiguration
        let sourceURL = settings.currentImageURL
        status = "アイコンを生成しています…"
        task = Task { [weak self, service] in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(180)) }
                let result = try await service.prepare(sourceURL: sourceURL, configuration: config)
                try Task.checkCancellation()
                guard let self, self.generation == expected, self.settings.image != nil else { return }
                let icon = try IconImageAssembler.image(pngs: result.pngs)
                var previews: [Int: NSImage] = [:]
                for size in IconGeometry.sizes {
                    guard let data = result.pngs[size] else { throw IconError.renderFailed }
                    previews[size] = NSImage(data: data)
                }
                self.persistingResult = true
                self.settings.iconConfiguration = result.configuration
                self.persistingResult = false
                self.previews = previews; self.hasTransparency = result.hasTransparency
                self.currentIcon = icon
                NSApp.applicationIconImage = icon
                self.status = result.configuration.estimate.explanation
            } catch is CancellationError { }
            catch {
                guard let self, self.generation == expected else { return }
                self.status = error.localizedDescription
            }
        }
    }
}
