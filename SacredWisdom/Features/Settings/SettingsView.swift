import SwiftUI

struct SettingsView: View {
    let configuration: AppConfiguration
    @State var viewModel: SettingsViewModel

    @State private var isConfirmingClear = false

    var body: some View {
        List {
            Section {
                Picker("Appearance", selection: Binding(get: { viewModel.display.appearance },
                                                        set: { viewModel.display.appearance = $0 })) {
                    ForEach(AppPreferences.Appearance.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings.appearance")
                // One visible label that includes the value, so what VoiceOver reads matches what is shown.
                Stepper {
                    Text("Scripture Text Size: \(viewModel.textScalePercent)%")
                } onIncrement: {
                    viewModel.changeTextScale(by: 1)
                } onDecrement: {
                    viewModel.changeTextScale(by: -1)
                }
                .accessibilityIdentifier("settings.textSize")
                // Sample wording only: scripture is never hardcoded in views.
                Text("Passages will appear at this size in the reader.")
                    .font(.system(size: 18 * viewModel.display.readerTextScale, design: .serif))
                    .foregroundStyle(SWColors.textPrimary)
                    .accessibilityIdentifier("settings.textSizePreview")
                ForEach(viewModel.translationChoices) { choice in
                    Picker(choice.collection.name, selection: Binding(
                        get: { choice.selectedID },
                        set: { id in Task { await viewModel.selectTranslation(id, for: choice.collection.id) } }
                    )) {
                        ForEach(choice.translations) { Text($0.name).tag($0.id) }
                    }
                    .accessibilityIdentifier("settings.translation.\(choice.collection.id)")
                }
            } header: {
                Text("Reading")
                    .foregroundStyle(SWColors.textSecondary)
            } footer: {
                Text("Text size adds to your system Dynamic Type setting. Translation choices apply in the reader and passage details.")
                    .foregroundStyle(SWColors.textSecondary)
            }
            Section {
                NavigationLink(value: AppRoute.offlineContent) {
                    Label("Offline Content", systemImage: "arrow.down.circle")
                }
                .accessibilityIdentifier("settings.offlineContent")
            } header: {
                Text("Library")
                    .foregroundStyle(SWColors.textSecondary)
            }
            Section {
                Toggle("AI Explanations", isOn: Binding(
                    get: { viewModel.isAIEnabled },
                    set: { value in Task { await viewModel.setAIEnabled(value) } }
                ))
                .accessibilityIdentifier("settings.aiToggle")
                if !viewModel.aiStatusText.isEmpty {
                    Text(viewModel.aiStatusText)
                        .font(SWTypography.caption)
                        .foregroundStyle(SWColors.textSecondary)
                        .accessibilityIdentifier("settings.aiStatus")
                }
            } header: {
                Text("Ask a Question")
                    .foregroundStyle(SWColors.textSecondary)
            } footer: {
                Text("Passages always come from the verified library. Search works without AI.")
                    .foregroundStyle(SWColors.textSecondary)
            }
            Section {
                Button("Clear Reading History", role: .destructive) { isConfirmingClear = true }
                    .accessibilityIdentifier("settings.clearHistory")
                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(SWTypography.caption)
                        .foregroundStyle(SWColors.textSecondary)
                        .accessibilityIdentifier("settings.status")
                }
            } header: {
                Text("Privacy")
                    .foregroundStyle(SWColors.textSecondary)
            } footer: {
                Text("Sacred Wisdom does not send your bookmarks, notes or history anywhere.")
                    .foregroundStyle(SWColors.textSecondary)
            }
            Section {
                LabeledContent("Version", value: configuration.appVersion)
                NavigationLink(value: AppRoute.attributions) {
                    Label("Sources & Licenses", systemImage: "books.vertical")
                }
                .accessibilityIdentifier("settings.attributions")
                Text("Scripture is shown only from verified sources with attribution. Any AI-generated explanation will always be labeled as such.")
                    .font(SWTypography.caption)
                    .foregroundStyle(SWColors.textSecondary)
            } header: {
                Text("About")
                    .foregroundStyle(SWColors.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .swScreenBackground()
        .navigationTitle("Settings")
        .accessibilityIdentifier("screen.settings")
        .task { await viewModel.load() }
        .confirmationDialog("Clear reading history?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { Task { await viewModel.clearReadingHistory() } }
                .accessibilityIdentifier("settings.clearHistory.confirm")
        } message: {
            Text("Recently viewed passages will be removed. Bookmarks and notes are kept.")
        }
    }
}
