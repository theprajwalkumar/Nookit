import SwiftUI
import AppKit

struct ClipboardModuleView: View {
    @ObservedObject private var service = ClipboardService.shared
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleTitle(
                title: "Clipboard",
                subtitle: "\(service.items.count) item\(service.items.count == 1 ? "" : "s")",
                trailing: AnyView(
                    HStack(spacing: 6) {
                        Text("↩ to copy")
                            .font(.system(size: 9))
                            .foregroundStyle(NotchPalette.tertiary)
                        Button {
                            service.clear()
                        } label: {
                            Text("Clear")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(NotchPalette.secondary)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.delete, modifiers: [.command, .shift])
                        .help("Clear clipboard history (⌘⇧⌫)")
                    }
                )
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if service.items.isEmpty {
                NotchEmpty(symbol: "doc.on.clipboard", text: "Copy something and it shows up here. Password managers are skipped automatically.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(service.items.prefix(30)) { item in
                            Button {
                                service.copy(item)
                                copiedID = item.id
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(1.1))
                                    if copiedID == item.id { copiedID = nil }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: copiedID == item.id ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(copiedID == item.id ? Theme.mint : NotchPalette.tertiary)
                                        .frame(width: 14)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.preview)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(NotchPalette.primary)
                                            .lineLimit(1)
                                        Text("\(item.source) · \(Fmt.timeAgo(item.date))")
                                            .font(.system(size: 8.5))
                                            .foregroundStyle(NotchPalette.tertiary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Copy") { service.copy(item) }
                                Button("Delete", role: .destructive) { service.delete(item) }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
        }
    }
}

// MARK: - Notes

struct NotesModuleView: View {
    @ObservedObject private var store = NotesStore.shared
    @State private var draft = ""
    @State private var loadedID: UUID?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                HStack {
                    Text("Notes")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(NotchPalette.secondary)
                    Spacer()
                    NotchIconButton(symbol: "plus", tint: Theme.emberSoft, help: "New note") {
                        let note = store.create()
                        load(note.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 7)

                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(store.notes) { note in
                            Button {
                                load(note.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(note.title)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(NotchPalette.primary)
                                        .lineLimit(1)
                                    Text(note.preview.isEmpty ? "Empty" : note.preview)
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(NotchPalette.tertiary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(
                                    (loadedID == note.id ? Color.white.opacity(0.09) : Color.clear),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    if loadedID == note.id { loadedID = nil; draft = "" }
                                    store.delete(note.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 5)
                }
            }
            .frame(width: 154)

            Rectangle().fill(NotchPalette.line).frame(width: 1)
                .padding(.vertical, 6)

            VStack(spacing: 0) {
                if loadedID == nil {
                    NotchEmpty(symbol: "note.text", text: "Pick a note, or start a new one. Files live in Application Support/Nookit/Notes.")
                } else {
                    TextEditor(text: $draft)
                        .font(.system(size: 11.5))
                        .foregroundStyle(NotchPalette.primary)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .onChange(of: draft) { _, newValue in
                            scheduleSave(newValue)
                        }
                    HStack {
                        Text("Markdown · autosaved")
                            .font(.system(size: 8.5))
                            .foregroundStyle(NotchPalette.tertiary)
                        Spacer()
                        if let id = loadedID {
                            Button("Delete") {
                                store.delete(id)
                                loadedID = nil
                                draft = ""
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 9))
                            .foregroundStyle(NotchPalette.tertiary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            }
        }
        .onAppear {
            if loadedID == nil { load(store.selectedID ?? store.notes.first?.id) }
        }
    }

    private func load(_ id: UUID?) {
        guard let id, let note = store.note(id) else {
            loadedID = nil
            draft = ""
            return
        }
        loadedID = id
        draft = note.content
        store.selectedID = id
    }

    private func scheduleSave(_ value: String) {
        guard let id = loadedID else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            store.update(id, content: value)
        }
    }
}

// MARK: - Tasks

struct TasksModuleView: View {
    @ObservedObject private var store = TaskStore.shared
    @State private var newTask = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleTitle(
                title: "Tasks",
                subtitle: store.openCount == 0 ? "All clear" : "\(store.openCount) open",
                trailing: AnyView(
                    Button("Clear done") { store.clearDone() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9))
                        .foregroundStyle(NotchPalette.tertiary)
                )
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack(spacing: 6) {
                TextField("Add a one-line task", text: $newTask)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .onSubmit { add() }
                Button { add() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.emberSoft)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)

            if store.tasks.isEmpty {
                NotchEmpty(symbol: "checklist", text: "One line at a time. Tasks stay on this Mac and survive restarts.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.tasks) { task in
                            HStack(spacing: 8) {
                                Button {
                                    store.toggle(task.id)
                                } label: {
                                    Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(task.done ? Theme.mint : NotchPalette.tertiary)
                                }
                                .buttonStyle(.plain)
                                Text(task.title)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(task.done ? NotchPalette.tertiary : NotchPalette.primary)
                                    .strikethrough(task.done, color: NotchPalette.tertiary)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    store.delete(task.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(NotchPalette.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func add() {
        store.add(newTask)
        newTask = ""
    }
}
