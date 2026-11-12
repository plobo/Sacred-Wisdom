import SwiftUI

struct AskQuestionView: View {
    @State var viewModel: AskQuestionViewModel
    let makeVoiceSearch: () -> VoiceSearchViewModel

    @State private var voiceSearch: VoiceSearchViewModel?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: SWSpacing.xl) {
                    if viewModel.exchanges.isEmpty {
                        AskIntro(suggestions: viewModel.suggestedQuestions) { question in
                            Task { await viewModel.ask(question) }
                        }
                    }
                    ForEach(Array(viewModel.exchanges.enumerated()), id: \.element.id) { index, exchange in
                        ExchangeView(exchange: exchange) { Task { await viewModel.retry(exchange) } }
                            .id(exchange.id)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("ask.exchange.\(index)")
                    }
                }
                .padding(SWSpacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            // On the scroll view, not the whole screen, so the input bar keeps its own identifiers.
            .accessibilityIdentifier("screen.askQuestion")
            .onChange(of: viewModel.exchanges.last?.id) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .top) } }
            }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .swScreenBackground()
        .navigationTitle("Ask a Question")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.exchanges.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { viewModel.clear() }
                        .disabled(viewModel.isAnswering)
                        .accessibilityIdentifier("ask.clear")
                }
            }
        }
        .sheet(item: $voiceSearch) { voice in
            VoiceSearchSheet(viewModel: voice) { transcript in
                viewModel.draft = transcript
                Task { await viewModel.send() }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: SWSpacing.s) {
            TextField("Ask about a theme or teaching…", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...4)
                .font(SWTypography.body)
                .padding(.horizontal, SWSpacing.m)
                .padding(.vertical, SWSpacing.s)
                .background(SWColors.surface, in: RoundedRectangle(cornerRadius: SWRadius.field, style: .continuous))
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit { Task { await viewModel.send() } }
                .accessibilityIdentifier("ask.input")
            Button { voiceSearch = makeVoiceSearch() } label: {
                Image(systemName: "mic").font(.title3)
            }
            .accessibilityLabel(Text("Ask by Voice"))
            .accessibilityIdentifier("ask.voice")
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(!viewModel.canSend)
            .accessibilityLabel(Text("Ask"))
            .accessibilityIdentifier("ask.send")
        }
        .tint(SWColors.primary)
        .padding(.horizontal, SWSpacing.l)
        .padding(.vertical, SWSpacing.s)
        .background(.bar)
    }
}
