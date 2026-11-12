import Foundation
import Observation

/// §10 DownloadManager: lists packages, downloads with progress, pauses/resumes, verifies, installs, removes,
/// and reports storage. Installed content never needs the network; only the manifest and new downloads do.
@Observable
@MainActor
final class DownloadManager {
    enum PackageStatus: Equatable {
        case notInstalled
        case downloading(Double)
        case paused(Double)
        case installing
        case installed(version: Int)
        case updateAvailable(installed: Int)
        case failed(String)
    }

    enum CatalogState: Equatable {
        case idle
        case loading
        case loaded
        /// No content server configured for this build.
        case notConfigured
        /// The manifest couldn't be fetched; installed packages are still listed and usable.
        case unavailable(String)
    }

    struct Item: Identifiable, Equatable {
        let entry: ManifestEntry
        var status: PackageStatus
        var id: String { entry.id }
    }

    struct Storage: Equatable {
        let databaseBytes: Int64
        let packageBytes: Int64
        var totalBytes: Int64 { databaseBytes + packageBytes }
    }

    private(set) var catalog: CatalogState = .idle
    private(set) var items: [Item] = []
    private(set) var storage = Storage(databaseBytes: 0, packageBytes: 0)

    private let manifestURL: URL?
    private let transport: any PackageTransport
    private let installer: PackageInstaller
    private let changes: UserDataChanges
    private var resumeData: [String: Data] = [:]
    private var available: [String: ManifestEntry] = [:]

    init(manifestURL: URL?, transport: any PackageTransport, installer: PackageInstaller, changes: UserDataChanges) {
        self.manifestURL = manifestURL
        self.transport = transport
        self.installer = installer
        self.changes = changes
    }

    // MARK: Catalog

    func refresh() async {
        if case .loading = catalog { return }
        rebuildItems()
        await updateStorage()
        guard let manifestURL else {
            catalog = .notConfigured
            return
        }
        catalog = .loading
        do {
            let manifest = try ContentManifest.decode(try await fetchManifest(manifestURL))
            available = Dictionary(uniqueKeysWithValues: manifest.packages.map { ($0.id, $0) })
            catalog = .loaded
        } catch let failure as DownloadFailure {
            catalog = .unavailable(Self.message(for: failure))
        } catch {
            catalog = .unavailable(String(localized: "The list of available content couldn’t be read."))
        }
        rebuildItems()
    }

    private func fetchManifest(_ url: URL) async throws -> Data {
        try await transport.fetch(url)
    }

    /// Merges installed packages (always shown, even offline) with the manifest's, preserving in-flight states.
    private func rebuildItems() {
        let installed = Dictionary(uniqueKeysWithValues: installer.store.installed().map { ($0.entry.id, $0.entry) })
        let ids = (Array(available.keys) + Array(installed.keys)).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let previous = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.status) })
        items = ids.compactMap { id -> Item? in
            guard let entry = available[id] ?? installed[id] else { return nil }
            let status: PackageStatus
            switch previous[id] {
            case .downloading(let p)?: status = .downloading(p)
            case .paused(let p)?: status = .paused(p)
            case .installing?: status = .installing
            case .failed(let message)? where installed[id] == nil: status = .failed(message)
            default:
                if let local = installed[id] {
                    status = (available[id]?.version ?? 0) > local.version ? .updateAvailable(installed: local.version)
                                                                            : .installed(version: local.version)
                } else {
                    status = .notInstalled
                }
            }
            return Item(entry: available[id] ?? entry, status: status)
        }
        .sorted { $0.entry.title < $1.entry.title }
    }

    func status(of id: String) -> PackageStatus? { items.first { $0.id == id }?.status }

    // MARK: Download

    func download(_ id: String) async {
        guard let manifestURL, let entry = available[id] else { return }
        switch status(of: id) {
        case .downloading?, .installing?: return
        default: break
        }
        let start: DownloadStart = resumeData[id].map { .resume($0, entry.url(relativeTo: manifestURL)) }
            ?? .fresh(entry.url(relativeTo: manifestURL))
        resumeData[id] = nil
        let initial: Double = if case .paused(let p)? = status(of: id) { p } else { 0 }
        set(id, .downloading(initial))
        do {
            let file = try await transport.download(id, start) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .downloading? = self.status(of: id) else { return }
                    self.set(id, .downloading(min(max(fraction, 0), 1)))
                }
            }
            set(id, .installing)
            try await installer.install(fileAt: file, entry: entry)
            set(id, .installed(version: entry.version))
            changes.contentChanged()
        } catch DownloadFailure.paused(let data) {
            resumeData[id] = data
            if case .downloading(let p)? = status(of: id) { set(id, .paused(p)) } else { set(id, .paused(0)) }
        } catch let failure as DownloadFailure {
            Log.downloads.error("Download \(id, privacy: .public) failed: \(String(describing: failure), privacy: .public)")
            set(id, .failed(Self.message(for: failure)))
        } catch let rejection as PackageInstaller.Rejection {
            Log.downloads.error("Package \(id, privacy: .public) rejected: \(String(describing: rejection), privacy: .public)")
            set(id, .failed(rejection.userMessage))
        } catch {
            Log.downloads.error("Installing \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            set(id, .failed(String(localized: "The package couldn’t be installed.")))
        }
        await updateStorage()
    }

    func pause(_ id: String) async {
        guard case .downloading? = status(of: id) else { return }
        await transport.pause(id)
    }

    /// Removes an installed package; its collection reverts to the bundled sample.
    func remove(_ id: String) async {
        do {
            try await installer.uninstall(id: id)
            set(id, .notInstalled)
            changes.contentChanged()
        } catch {
            set(id, .failed(error.userMessage))
        }
        rebuildItems()
        await updateStorage()
    }

    private func set(_ id: String, _ status: PackageStatus) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = status
    }

    private func updateStorage() async {
        storage = Storage(databaseBytes: await installer.database.databaseSize(), packageBytes: installer.store.totalBytes)
    }

    private static func message(for failure: DownloadFailure) -> String {
        switch failure {
        case .offline: String(localized: "You’re offline. Installed content is still available.")
        case .server(let status): String(localized: "The content server returned an error (\(status)).")
        case .paused: String(localized: "Paused.")
        case .other: String(localized: "The download failed. Please try again.")
        }
    }
}
