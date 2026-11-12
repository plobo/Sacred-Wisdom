import SwiftUI

/// Settings → Offline Content: available and installed packages, progress, removal, storage.
struct OfflineContentView: View {
    let manager: DownloadManager?

    @State private var removing: ManifestEntry?

    var body: some View {
        List {
            if let manager {
                content(manager)
            } else {
                Text("Offline content can’t be managed because the scripture library couldn’t be opened.")
                    .font(SWTypography.caption)
            }
        }
        .scrollContentBackground(.hidden)
        .swScreenBackground()
        .navigationTitle("Offline Content")
        .accessibilityIdentifier("screen.offlineContent")
        .task { await manager?.refresh() }
        .refreshable { await manager?.refresh() }
        .confirmationDialog(
            "Remove downloaded content?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { entry in
            Button("Remove “\(entry.title)”", role: .destructive) {
                Task { await manager?.remove(entry.id) }
            }
            .accessibilityIdentifier("offline.confirmRemove")
        } message: { _ in
            Text("The collection returns to the built-in sample. Bookmarks and notes are kept; bookmarks on passages outside the sample show as unavailable until you download it again.")
        }
    }

    @ViewBuilder
    private func content(_ manager: DownloadManager) -> some View {
        Section {
            if manager.storage.databaseBytes > 0 {
                LabeledContent("Scripture library", value: Self.bytes(manager.storage.databaseBytes))
            }
            LabeledContent("Downloaded packages", value: Self.bytes(manager.storage.packageBytes))
                .accessibilityIdentifier("offline.packageBytes")
            LabeledContent("Total", value: Self.bytes(manager.storage.totalBytes))
        } header: {
            Text("Storage")
                .foregroundStyle(SWColors.textSecondary)
        } footer: {
            Text("The built-in sample of every collection is always available offline.")
                .foregroundStyle(SWColors.textSecondary)
        }

        Section {
            switch manager.catalog {
            case .notConfigured:
                notice("No content server is configured for this version, so there is nothing new to download.", icon: "icloud.slash")
            case .unavailable(let message):
                notice(message, icon: "wifi.slash")
            case .loading where manager.items.isEmpty:
                ProgressView()
            default:
                EmptyView()
            }
            ForEach(manager.items) { item in
                PackageRow(item: item,
                           onDownload: { Task { await manager.download(item.id) } },
                           onPause: { Task { await manager.pause(item.id) } },
                           onRemove: { removing = item.entry })
            }
        } header: {
            Text("Collections")
                .foregroundStyle(SWColors.textSecondary)
        } footer: {
            Text("Downloads replace a collection’s sample with the complete chapter and work without internet. Only content is downloaded; nothing about you is sent.")
                .foregroundStyle(SWColors.textSecondary)
        }
    }

    private func notice(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(SWTypography.caption)
            .foregroundStyle(SWColors.textSecondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("offline.notice")
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

private struct PackageRow: View {
    let item: DownloadManager.Item
    let onDownload: () -> Void
    let onPause: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SWSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: SWSpacing.xs) {
                    Text(item.entry.title).font(SWTypography.headline).foregroundStyle(SWColors.textPrimary)
                    Text(details).font(SWTypography.caption).foregroundStyle(SWColors.textSecondary)
                }
                Spacer()
                action
            }
            Text(item.entry.license)
                .font(SWTypography.caption)
                .foregroundStyle(SWColors.textSecondary)
            statusLine
        }
        .padding(.vertical, SWSpacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("package.\(item.id)")
    }

    private var details: String {
        let languages = item.entry.languages.map { LanguageInfo.displayName($0) }.joined(separator: ", ")
        return "\(item.entry.passageCount) passages · \(OfflineContentView.bytes(Int64(item.entry.fileSize))) · \(languages)"
    }

    @ViewBuilder
    private var action: some View {
        switch item.status {
        case .notInstalled, .failed:
            button("Download", systemImage: "arrow.down.circle", id: "download", action: onDownload)
        case .downloading:
            button("Pause", systemImage: "pause.circle", id: "pause", action: onPause)
        case .paused:
            button("Resume", systemImage: "arrow.down.circle", id: "resume", action: onDownload)
        case .installing:
            ProgressView()
        case .installed:
            button("Remove", systemImage: "trash", id: "remove", role: .destructive, action: onRemove)
        case .updateAvailable:
            button("Update", systemImage: "arrow.triangle.2.circlepath", id: "download", action: onDownload)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch item.status {
        case .downloading(let fraction), .paused(let fraction):
            ProgressView(value: fraction)
                .tint(SWColors.primary)
                .accessibilityLabel(Text("Download progress"))
                .accessibilityValue(Text("\(Int(fraction * 100)) percent"))
                .accessibilityIdentifier("package.\(item.id).progress")
        case .installing:
            statusText("Verifying and installing…")
        case .installed(let version):
            statusText(String(localized: "Installed · version \(version) · available offline"), icon: "checkmark.circle.fill")
        case .updateAvailable(let installed):
            statusText(String(localized: "Version \(installed) installed · update available"))
        case .failed(let message):
            statusText(message, icon: "exclamationmark.triangle")
        case .notInstalled:
            EmptyView()
        }
    }

    private func statusText(_ text: String, icon: String? = nil) -> some View {
        Group {
            if let icon { Label(text, systemImage: icon) } else { Text(text) }
        }
        .font(SWTypography.caption.weight(.semibold))
        .foregroundStyle(SWColors.textSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("package.\(item.id).status")
    }

    private func button(_ title: LocalizedStringKey, systemImage: String, id: String, role: ButtonRole? = nil,
                        action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .tint(role == .destructive ? .red : SWColors.primary)
        .font(SWTypography.caption.weight(.semibold))
        .accessibilityIdentifier("package.\(item.id).\(id)")
    }
}
