import SwiftUI
import SwiftData
import AppKit

/// Presentation state for the single companion draft panel. Owned by whichever host
/// presents the task detail (the docked drawer, the console sheet) and injected into
/// the environment so AgentDraftsSection can open a draft beside the task panel.
@MainActor
@Observable
public final class AgentDraftPanelState {
    public var draft: AgentDraft?
    public var workingDirectory: String = ""
    public init() {}

    public func open(_ draft: AgentDraft, workingDirectory: String) {
        self.draft = draft
        self.workingDirectory = workingDirectory
    }

    public func close() { draft = nil }
}

/// Full-height companion editor for one agent draft — real reading width beside the
/// task panel, never a navigation away. Edits autosave to the vault file; nothing is
/// ever sent.
public struct AgentDraftPanelView: View {
    @Bindable var state: AgentDraftPanelState
    @State private var text: String = ""
    @State private var loaded = false
    @State private var showSaved = false

    public init(state: AgentDraftPanelState) { self.state = state }

    private var io: FileVaultIO { FileVaultIO(rootPath: state.workingDirectory) }

    public var body: some View {
        if let draft = state.draft {
            VStack(alignment: .leading, spacing: 0) {
                header(draft)
                Divider().overlay(Theme.Palette.hairline)
                if loaded {
                    MarkdownTextView(text: $text)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: text) { _, newValue in
                            try? io.write(draft.relativePath, newValue)
                            showSaved = true
                        }
                } else {
                    Text("Draft file not found — it may have been moved.")
                        .font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.warnText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(16)
                }
                Divider().overlay(Theme.Palette.hairline)
                footer
            }
            .background(Theme.Palette.bg)
            .task(id: draft.uid) { load(draft) }
        }
    }

    private func header(_ draft: AgentDraft) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon(draft.kind)).font(Theme.Fonts.body)
                .foregroundStyle(Theme.Palette.agent)
            Text(draft.title).font(Theme.Fonts.body).fontWeight(.medium).lineLimit(2)
            Spacer(minLength: 8)
            Text(draft.kind.rawValue)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.Palette.agentText)
                .padding(.horizontal, 7).padding(.vertical, 1)
                .background(Theme.Palette.agentTintLight, in: Capsule())
            if showSaved {
                Label("saved", systemImage: "checkmark")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
            Button { state.close() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Theme.Palette.textSecondary)
                .help("Close draft")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: { Label("Copy", systemImage: "doc.on.doc") }
                .controlSize(.small).disabled(!loaded)
            Text("editing in place · autosaves · never sent")
                .font(Theme.Fonts.caption).foregroundStyle(Theme.Palette.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func icon(_ kind: AgentDraftKind) -> String {
        switch kind {
        case .email: return "envelope"
        case .message: return "message"
        case .comment: return "text.bubble"
        case .note, .other: return "doc.text"
        }
    }

    private func load(_ draft: AgentDraft) {
        showSaved = false
        if let contents = io.read(draft.relativePath) {
            text = contents; loaded = true
        } else {
            text = ""; loaded = false
        }
    }
}
