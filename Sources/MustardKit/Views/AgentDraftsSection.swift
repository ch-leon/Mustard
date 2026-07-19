import SwiftUI
import SwiftData

/// The task's agent drafts, shown and edited in place (the task detail opens over the
/// board, so nothing navigates away). Each draft is a vault markdown file read live; the
/// expanded editor is the shared MarkdownTextView, autosaving back to the file.
public struct AgentDraftsSection: View {
    let run: AgentRun
    public init(run: AgentRun) { self.run = run }

    private var drafts: [AgentDraft] {
        (run.drafts ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    public var body: some View {
        if !drafts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("DRAFTS")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.06)
                    .foregroundStyle(Theme.Palette.textTertiary)
                ForEach(drafts, id: \.uid) { draft in
                    AgentDraftCard(draft: draft, workingDirectory: run.workingDirectory)
                }
            }
        }
    }
}

private struct AgentDraftCard: View {
    let draft: AgentDraft
    let workingDirectory: String
    @State private var expanded = false
    @State private var text: String = ""
    @State private var loaded = false

    private var io: FileVaultIO { FileVaultIO(rootPath: workingDirectory) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if expanded {
                if loaded {
                    MarkdownTextView(text: $text)
                        .frame(minHeight: 160, maxHeight: 420)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Palette.hairline, lineWidth: 0.5))
                        .onChange(of: text) { _, newValue in try? io.write(draft.relativePath, newValue) }
                } else {
                    Text("Draft file not found — it may have been moved.")
                        .font(Theme.Fonts.meta).foregroundStyle(Theme.Palette.warnText)
                }
                actions
            } else {
                Text(snippet).font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(3)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.Palette.hairline).frame(width: 2) }
                actions
            }
        }
        .padding(12)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.Palette.hairline, lineWidth: 0.5))
        .task(id: draft.uid) { load() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(Theme.Fonts.body).foregroundStyle(Theme.Palette.agent)
            Text(draft.title).font(Theme.Fonts.body).fontWeight(.medium)
            Spacer(minLength: 8)
            Text(draft.kind.rawValue)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.Palette.agentText)
                .padding(.horizontal, 7).padding(.vertical, 1)
                .background(Theme.Palette.agentTintLight, in: Capsule())
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { expanded.toggle() } label: {
                Label(expanded ? "Collapse" : "Expand",
                      systemImage: expanded ? "chevron.up" : "chevron.down")
            }.controlSize(.small)
            Button {
                #if canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                #endif
            } label: { Label("Copy", systemImage: "doc.on.doc") }
                .controlSize(.small).disabled(!loaded)
            Spacer(minLength: 0)
        }
    }

    private var snippet: String {
        loaded ? text : "Loading…"
    }

    private var icon: String {
        switch draft.kind {
        case .email: return "envelope"
        case .message: return "message"
        case .comment: return "text.bubble"
        case .note, .other: return "doc.text"
        }
    }

    private func load() {
        if let contents = io.read(draft.relativePath) {
            text = contents; loaded = true
        } else {
            loaded = false
        }
    }
}
