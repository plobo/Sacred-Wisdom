import SwiftUI

/// Toolbar bookmark toggle for the passage a `PassageBookmarkController` is showing.
struct BookmarkToggleButton: View {
    let controller: PassageBookmarkController
    let identifier: String

    var body: some View {
        Button {
            Task { await controller.toggle() }
        } label: {
            Image(systemName: controller.isBookmarked ? "bookmark.fill" : "bookmark")
        }
        .accessibilityLabel(controller.isBookmarked ? Text("Remove Bookmark") : Text("Bookmark"))
        .accessibilityAddTraits(controller.isBookmarked ? .isSelected : [])
        .accessibilityIdentifier(identifier)
        .disabled(controller.passageID == nil)
    }
}

extension View {
    /// Confirmation before removing a bookmark that has a note, an alert for failed writes, and a refresh
    /// whenever bookmarks change elsewhere in the app.
    func bookmarkAlerts(_ controller: PassageBookmarkController) -> some View {
        modifier(BookmarkAlertsModifier(controller: controller))
    }
}

private struct BookmarkAlertsModifier: ViewModifier {
    @Bindable var controller: PassageBookmarkController

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Remove bookmark and note?",
                isPresented: Binding(get: { controller.isConfirmingRemoval }, set: { if !$0 { controller.cancelRemoval() } }),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) { Task { await controller.confirmRemoval() } }
                    .accessibilityIdentifier("bookmark.confirmRemove")
            } message: {
                Text("Your note on this passage will be deleted too.")
            }
            .alert(
                "Couldn’t Save",
                isPresented: Binding(get: { controller.actionError != nil }, set: { if !$0 { controller.actionError = nil } }),
                presenting: controller.actionError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .task(id: controller.revision) { await controller.refresh() }
    }
}

/// Edits the personal note saved with a bookmark.
struct NoteEditorSheet: View {
    let reference: String
    let initialText: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SWSpacing.s) {
                TextEditor(text: $text)
                    .font(SWTypography.body)
                    .scrollContentBackground(.hidden)
                    .padding(SWSpacing.s)
                    .background(SWColors.surface, in: RoundedRectangle(cornerRadius: SWRadius.field, style: .continuous))
                    .focused($isFocused)
                    .accessibilityLabel(Text("Note"))
                    .accessibilityIdentifier("noteEditor.text")
                Text("Notes are private and saved with your bookmark. Leave empty to delete the note.")
                    .font(SWTypography.caption)
                    .foregroundStyle(SWColors.textSecondary)
            }
            .padding(SWSpacing.l)
            .swScreenBackground()
            .navigationTitle(Text("Note · \(reference)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("noteEditor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .accessibilityIdentifier("noteEditor.save")
                }
            }
        }
        .onAppear {
            text = initialText
            isFocused = true
        }
    }
}
