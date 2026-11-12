import SwiftUI

/// Settings → Sources & Licenses: who produced each text and the terms it is used under.
struct AttributionsView: View {
    let load: LoadAttributionsUseCase

    @State private var state: LoadState = .loading

    enum LoadState: Equatable {
        case loading
        case loaded([CollectionAttribution])
        case failed(String)
    }

    var body: some View {
        List {
            switch state {
            case .loading:
                LoadingStateView()
            case .failed(let message):
                ErrorStateView(message: message) { Task { await reload() } }
            case .loaded(let items):
                Section {
                    Text("Scripture is shown verbatim from these sources. Themes linking passages are editorial; AI explanations are labeled and never quoted as scripture.")
                        .font(SWTypography.caption)
                        .foregroundStyle(SWColors.textSecondary)
                }
                ForEach(items) { item in
                    Section {
                        ForEach(item.sources, id: \.id) { source in
                            VStack(alignment: .leading, spacing: SWSpacing.xs) {
                                Text(source.name).font(SWTypography.body.weight(.semibold))
                                Text(source.attribution).font(SWTypography.caption)
                                Text(source.license).font(SWTypography.caption).foregroundStyle(SWColors.textSecondary)
                                if let url = source.url {
                                    Link(url.host() ?? url.absoluteString, destination: url).font(SWTypography.caption)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("attribution.\(item.collection.id).\(source.id)")
                        }
                    } header: {
                        Text("\(item.religion.name) · \(item.collection.name)")
                            .foregroundStyle(SWColors.textSecondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .swScreenBackground()
        .navigationTitle("Sources & Licenses")
        .accessibilityIdentifier("screen.attributions")
        .task { await reload() }
    }

    private func reload() async {
        do {
            state = .loaded(try await load.execute())
        } catch {
            state = .failed(error.userMessage)
        }
    }
}
