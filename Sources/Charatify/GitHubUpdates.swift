import CryptoKit
import Foundation

struct UpdateVersion: Comparable {
    let number: [Int]
    let nightly: [Int]

    init?(_ label: String) {
        let parts = label.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let components = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } })
        else { return nil }
        let number = components.compactMap { Int($0) }
        guard number.count == 3 else { return nil }
        self.number = number

        if parts.count == 1 {
            nightly = []
        } else {
            let suffix = parts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard suffix.count == 3, suffix[0] == "nightly", suffix[1].count == 8,
                  suffix.dropFirst().allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
                  let date = Int(suffix[1]), let run = Int(suffix[2]), run > 0
            else { return nil }
            nightly = [date, run]
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.number != rhs.number { return lhs.number.lexicographicallyPrecedes(rhs.number) }
        if rhs.nightly.isEmpty { return !lhs.nightly.isEmpty }
        return !lhs.nightly.isEmpty && lhs.nightly.lexicographicallyPrecedes(rhs.nightly)
    }
}

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let state: String
    }

    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    var versionLabel: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
}

struct GitHubUpdate {
    let tag: String
    let versionLabel: String
    let version: UpdateVersion
    let archiveName: String
    let developerSigned: Bool

    var releaseURL: URL { GitHubUpdates.releasesURL.appendingPathComponent("tag").appendingPathComponent(tag) }

    func downloadURL(for name: String) -> URL {
        GitHubUpdates.releasesURL.appendingPathComponent("download")
            .appendingPathComponent(tag).appendingPathComponent(name)
    }

    init?(release: GitHubRelease, includesNightly: Bool, requiresDeveloperID: Bool) {
        let label = release.versionLabel
        guard !release.draft, let version = UpdateVersion(label),
              release.prerelease == !version.nightly.isEmpty,
              !release.prerelease || includesNightly
        else { return nil }

        let assets = Set(release.assets.filter { $0.state == "uploaded" }.map(\.name))
        let prefix = "Charatify-\(label)-macos-universal"
        let developerSigned = assets.contains("\(prefix).zip")
        let archiveName = developerSigned ? "\(prefix).zip" : "\(prefix)-unnotarized.zip"
        guard assets.contains("SHA256SUMS"), assets.contains(archiveName),
              developerSigned || !requiresDeveloperID
        else { return nil }

        self.tag = release.tagName
        self.versionLabel = label
        self.version = version
        self.archiveName = archiveName
        self.developerSigned = developerSigned
    }
}

struct GitHubUpdates {
    static let releasesURL = URL(string: "https://github.com/taiyop/Charatify/releases")!
    private static let api = URL(string: "https://api.github.com/repos/taiyop/Charatify/releases")!
    var session: URLSession = .shared

    func latest(after current: UpdateVersion, includesNightly: Bool, requiresDeveloperID: Bool) async throws -> GitHubUpdate? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var best: GitHubUpdate?
        var page = 1
        while true {
            var endpoint = URLComponents(url: Self.api, resolvingAgainstBaseURL: false)!
            endpoint.queryItems = [URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "page", value: String(page))]
            var request = URLRequest(url: endpoint.url!, timeoutInterval: 30)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            let http = try checked(response)
            for release in try decoder.decode([GitHubRelease].self, from: data) {
                guard let candidate = GitHubUpdate(release: release, includesNightly: includesNightly,
                                                   requiresDeveloperID: requiresDeveloperID),
                      candidate.version > (best?.version ?? current)
                else { continue }
                best = candidate
            }
            guard http.value(forHTTPHeaderField: "Link")?.contains("rel=\"next\"") == true else { return best }
            page += 1
        }
    }

    func download(_ update: GitHubUpdate, to archive: URL) async throws {
        let (manifest, response) = try await session.data(from: update.downloadURL(for: "SHA256SUMS"))
        _ = try checked(response)
        let expected = try Self.checksum(in: manifest, for: update.archiveName)
        let (temporary, archiveResponse) = try await session.download(from: update.downloadURL(for: update.archiveName))
        defer { try? FileManager.default.removeItem(at: temporary) }
        _ = try checked(archiveResponse)

        let file = try FileHandle(forReadingFrom: temporary)
        defer { try? file.close() }
        var sha256 = SHA256()
        while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            sha256.update(data: chunk)
        }
        let actual = sha256.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw UpdateError.invalidChecksum }
        try FileManager.default.moveItem(at: temporary, to: archive)
    }

    static func checksum(in data: Data, for name: String) throws -> String {
        guard data.count <= 64 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw UpdateError.invalidChecksum
        }
        let matches = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields[1] == name || fields[1] == "*\(name)" else { return nil }
            return fields[0].lowercased()
        }
        guard matches.count == 1, let hash = matches.first, hash.utf8.count == 64,
              hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { throw UpdateError.invalidChecksum }
        return hash
    }

    private func checked(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse, http.url?.scheme == "https" else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else { throw UpdateError.http(http.statusCode) }
        return http
    }
}

enum UpdateError: LocalizedError {
    case http(Int)
    case invalidChecksum
    case invalidApp
    case extractFailed
    case appChanged
    case replacementFailed

    var errorDescription: String? {
        switch self {
        case .http(let status): return String(localized: "GitHubから応答エラーが返されました（HTTP \(status)）。")
        case .invalidChecksum: return String(localized: "アップデートファイルのSHA-256を確認できませんでした。")
        case .invalidApp: return String(localized: "アップデートのアプリ情報またはコード署名を検証できませんでした。")
        case .extractFailed: return String(localized: "アップデートファイルを展開できませんでした。")
        case .appChanged: return String(localized: "インストール済みのアプリが変更されました。Charatifyを再起動してください。")
        case .replacementFailed: return String(localized: "アプリを置き換えられませんでした。書き込み可能な場所にインストールしてください。")
        }
    }
}
