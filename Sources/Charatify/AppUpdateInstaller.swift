import Darwin
import Foundation
import Security

struct AppUpdateInstaller {
    let github: GitHubUpdates

    func install(_ update: GitHubUpdate, over installed: URL, currentVersion: String, bundleIdentifier: String,
                 requiresDeveloperID: Bool) async throws {
        var installed = installed.resolvingSymlinksInPath()
        let manager = FileManager.default
        guard manager.isWritableFile(atPath: installed.deletingLastPathComponent().path) else {
            throw UpdateError.replacementFailed
        }
        let original = try installed.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        let staging = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                      appropriateFor: installed, create: true)
        var relaunchOwnsStaging = false
        defer { if !relaunchOwnsStaging { try? manager.removeItem(at: staging) } }

        let archive = staging.appendingPathComponent(update.archiveName)
        try await github.download(update, to: archive)

        let extraction = staging.appendingPathComponent("extracted", isDirectory: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, extraction.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw UpdateError.extractFailed }

        let replacement = extraction.appendingPathComponent("Charatify.app", isDirectory: true)
        try Self.validate(replacement, over: installed, update: update, bundleIdentifier: bundleIdentifier,
                          requiresDeveloperID: requiresDeveloperID)
        installed.removeAllCachedResourceValues()
        let current = try installed.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        guard let original, original.isEqual(current), Self.version(in: try Self.metadata(in: installed)) == currentVersion
        else { throw UpdateError.appChanged }

        try Self.swap(replacement, installed)
        do {
            try relaunch(installed, cleanup: staging)
            relaunchOwnsStaging = true
        } catch {
            // Keep the old bundle available if the filesystem cannot roll back the swap.
            do { try Self.swap(replacement, installed) }
            catch { relaunchOwnsStaging = true }
            throw error
        }
    }

    static func validate(_ replacement: URL, over installed: URL, update: GitHubUpdate, bundleIdentifier: String,
                         requiresDeveloperID: Bool) throws {
        let values = try replacement.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw UpdateError.invalidApp }
        let info = try metadata(in: replacement)
        guard info["CFBundleIdentifier"] as? String == bundleIdentifier,
              info["CFBundleExecutable"] as? String == "Charatify",
              version(in: info) == update.versionLabel,
              info["CharatifyUpdateRequiresDeveloperID"] as? Bool == update.developerSigned
        else { throw UpdateError.invalidApp }

        var requirement: SecRequirement?
        if requiresDeveloperID {
            guard update.developerSigned,
                  SecCodeCopyDesignatedRequirement(try code(at: installed), [], &requirement) == errSecSuccess,
                  requirement != nil
            else { throw UpdateError.invalidApp }
        } else if update.developerSigned {
            let developerID = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            guard SecRequirementCreateWithString(developerID as CFString, [], &requirement) == errSecSuccess else {
                throw UpdateError.invalidApp
            }
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(try code(at: replacement), flags, requirement) == errSecSuccess else {
            throw UpdateError.invalidApp
        }
    }

    private static func version(in info: [String: Any]) -> String? {
        (info["CharatifyNightlyVersion"] ?? info["CFBundleShortVersionString"]) as? String
    }

    private static func metadata(in app: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw UpdateError.invalidApp
        }
        return info
    }

    private static func code(at url: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateError.invalidApp
        }
        return code
    }

    static func swap(_ first: URL, _ second: URL) throws {
        let result = first.withUnsafeFileSystemRepresentation { from in
            second.withUnsafeFileSystemRepresentation { to in
                renameatx_np(AT_FDCWD, from, AT_FDCWD, to, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else { throw UpdateError.replacementFailed }
    }

    private func relaunch(_ app: URL, cleanup: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Keep the old bundle until the running process exits and Launch Services opens the replacement.
        process.arguments = ["-c", """
            for attempt in $(/usr/bin/seq 1 150); do
                if ! kill -0 "$1" 2>/dev/null; then
                    /usr/bin/open -n "$2" && /bin/rm -rf -- "$3"
                    exit
                fi
                /bin/sleep 0.1
            done
            """, "charatify-relaunch", String(ProcessInfo.processInfo.processIdentifier), app.path, cleanup.path]
        try process.run()
    }
}
