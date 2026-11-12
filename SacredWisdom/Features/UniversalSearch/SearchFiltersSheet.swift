import SwiftUI

/// Language and translation filters. Tradition filters live in the chip bar on the search screen.
struct SearchFiltersSheet: View {
    let viewModel: SearchViewModel
    let options: SearchFilterOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Language") {
                    ForEach(options.languageCodes, id: \.self) { code in
                        toggleRow(LanguageInfo.displayName(code), isOn: viewModel.filters.languageCodes.contains(code)) {
                            await viewModel.toggleLanguage(code)
                        }
                        .accessibilityIdentifier("filter.language.\(code)")
                    }
                }
                Section("Translation") {
                    ForEach(options.translations) { translation in
                        toggleRow(translation.name, isOn: viewModel.filters.translationIDs.contains(translation.id)) {
                            await viewModel.toggleTranslation(translation.id)
                        }
                        .accessibilityIdentifier("filter.translation.\(translation.id)")
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear All") { Task { await viewModel.clearFilters() } }
                        .disabled(viewModel.filters.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("filters.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggleRow(_ title: String, isOn: Bool, action: @escaping @MainActor () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack {
                Text(title).foregroundStyle(SWColors.textPrimary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark").foregroundStyle(SWColors.primary)
                }
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
