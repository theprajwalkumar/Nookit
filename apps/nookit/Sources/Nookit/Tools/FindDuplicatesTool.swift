import SwiftUI
import AppKit
import CryptoKit

// MARK: - Duplicate scanning

struct DuplicateGroup: Identifiable {
    let id = UUID()
    var size: Int64
    var files: [URL]
    var keeper: URL
}

enum DuplicateScanner {
    struct Candidate {
        let url: URL
        let size: Int64
        let modified: Date
    }

    static func files(in folders: [URL], includeSmall: Bool) -> [Candidate] {
        var result: [Candidate] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        for folder in folders {
            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let size = values.fileSize, size > 0 else { continue }
                if !includeSmall && size < 4096 { continue }
                result.append(Candidate(url: url, size: Int64(size), modified: values.contentModificationDate ?? .distantPast))
            }
        }
        return result
    }

    static func hash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func find(in folders: [URL], includeSmall: Bool, status: @escaping (String) -> Void) -> [DuplicateGroup] {
        status("Listing files…")
        let candidates = files(in: folders, includeSmall: includeSmall)
        status("Comparing \(candidates.count) files…")
        let bySize = Dictionary(grouping: candidates.filter { $0.size > 0 }, by: \.size)
        let possible = bySize.values.filter { $0.count > 1 }
        let total = possible.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }

        var buckets: [String: [Candidate]] = [:]
        var processed = 0
        for group in possible {
            for candidate in group {
                processed += 1
                if processed % 12 == 0 || processed == total {
                    status("Hashing \(processed) of \(total) same-size files…")
                }
                guard let digest = hash(candidate.url) else { continue }
                let key = "\(candidate.size)-\(digest)"
                buckets[key, default: []].append(candidate)
            }
        }

        var groups: [DuplicateGroup] = []
        for (_, matches) in buckets where matches.count > 1 {
            let sorted = matches.sorted { $0.modified < $1.modified }
            guard let keeper = sorted.first else { continue }
            groups.append(DuplicateGroup(
                size: keeper.size,
                files: sorted.map(\.url),
                keeper: keeper.url
            ))
        }
        return groups.sorted { $0.size * Int64($0.files.count - 1) > $1.size * Int64($1.files.count - 1) }
    }
}

// MARK: - Find Duplicates

struct FindDuplicatesTool: View {
    @StateObject private var job = JobState()
    @State private var folders: [URL] = []
    @State private var groups: [DuplicateGroup] = []
    @State private var includeSmall = false
    @State private var confirmTrash = false
    @EnvironmentObject private var store: ResultStore

    private var extras: [(URL, DuplicateGroup)] {
        groups.flatMap { group in group.files.filter { $0 != group.keeper }.map { ($0, group) } }
    }

    private var reclaimable: Int64 {
        extras.reduce(0) { $0 + $1.1.size }
    }

    var body: some View {
        ToolPage(symbol: "doc.on.doc.fill", title: "Find Duplicates", subtitle: "Compare files by size and SHA-256 content, keep one copy and send the extras to the Trash. Nothing is deleted permanently.") {
            ToolCard(title: "Where to look") {
                HStack(spacing: 10) {
                    Button("Add folder…") {
                        if let folder = FilePicker.folder(title: "Choose a folder to scan") {
                            if !folders.contains(folder) { folders.append(folder) }
                            groups = []
                            job.clear()
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Clear") { folders = []; groups = []; job.clear() }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(folders.isEmpty && groups.isEmpty)
                    Spacer()
                    Toggle("Include files under 4 KB", isOn: $includeSmall)
                        .toggleStyle(.switch)
                        .font(Theme.body)
                }
                if folders.isEmpty {
                    Text("Add Downloads, a photo library export or any folder. Nookit only reads files while scanning; it does not modify them until you confirm.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    VStack(spacing: 1) {
                        ForEach(folders, id: \.path) { folder in
                            HStack(spacing: 8) {
                                Image(systemName: "folder").foregroundStyle(Theme.ember).frame(width: 18)
                                Text(folder.path).font(.system(size: 11.5)).lineLimit(1)
                                Spacer()
                                Button("Remove") { folders.removeAll { $0 == folder } ; groups = [] }
                                    .buttonStyle(QuietButtonStyle())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Theme.raised.opacity(0.4))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                HStack(spacing: 10) {
                    Button(job.working ? "Scanning…" : "Find duplicates") { scan() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(folders.isEmpty || job.working)
                    if !job.status.isEmpty {
                        Text(job.status).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                if let error = job.error { InlineError(message: error) }
            }

            if !groups.isEmpty {
                ToolCard(title: "Duplicates", subtitle: "\(groups.count) group\(groups.count == 1 ? "" : "s") · \(Fmt.bytes(reclaimable)) can be reclaimed", trailing: AnyView(
                    Button("Save report") { saveReport() }
                        .buttonStyle(QuietButtonStyle())
                )) {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text("\(group.files.count) copies · \(Fmt.bytes(group.size)) each")
                                            .font(.system(size: 10.5, weight: .semibold))
                                            .foregroundStyle(Theme.textSecondary)
                                        Spacer()
                                        Text("Keep the radio-marked copy")
                                            .font(Theme.caption)
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                    ForEach(group.files, id: \.path) { url in
                                        HStack(spacing: 8) {
                                            Button {
                                                groups[index].keeper = url
                                            } label: {
                                                Image(systemName: group.keeper == url ? "largecircle.fill.circle" : "circle")
                                                    .foregroundStyle(group.keeper == url ? Theme.mint : Theme.textTertiary)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Keep this copy")

                                            Image(systemName: icon(for: url))
                                                .font(.system(size: 11))
                                                .foregroundStyle(Theme.ember)
                                                .frame(width: 16)
                                            Text(url.lastPathComponent)
                                                .font(.system(size: 11.5, weight: group.keeper == url ? .semibold : .regular))
                                                .lineLimit(1)
                                            Text(shortPath(url))
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(Theme.textTertiary)
                                                .lineLimit(1)
                                            Spacer()
                                            Button("Reveal") { store.reveal(url) }
                                                .buttonStyle(QuietButtonStyle())
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(group.keeper == url ? Theme.mint.opacity(0.08) : Theme.raised.opacity(0.32), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                }
                                .padding(8)
                                .background(Theme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                        }
                    }
                    .frame(maxHeight: 420)
                    Button("Move \(extras.count) duplicate\(extras.count == 1 ? "" : "s") to Trash") {
                        confirmTrash = true
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.danger))
                    .disabled(extras.isEmpty)
                }
            } else if !folders.isEmpty && !job.working && job.error == nil && job.status.hasPrefix("No") {
                ToolCard(title: "No duplicates") {
                    Text("No two files matched by size and content. Try adding another folder, or include small files.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .alert("Move \(extras.count) files to the Trash?", isPresented: $confirmTrash) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) { trashExtras() }
        } message: {
            Text("The keeper in each group always stays. Files go to the Trash and can be put back with ⌘Z until you empty it.")
        }
    }

    private func icon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "tiff": return "photo"
        case "mp4", "mov", "m4v", "mkv": return "film"
        case "mp3", "m4a", "wav", "flac": return "waveform"
        case "pdf": return "doc.richtext"
        case "zip", "dmg", "pkg": return "shippingbox"
        default: return "doc"
        }
    }

    private func shortPath(_ url: URL) -> String {
        let parent = url.deletingLastPathComponent().path
        return parent.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private func scan() {
        let folders = self.folders
        let includeSmall = self.includeSmall
        groups = []
        job.begin("Listing files…")
        Task.detached(priority: .userInitiated) {
            let found = DuplicateScanner.find(in: folders, includeSmall: includeSmall) { text in
                Task { @MainActor in job.note(text) }
            }
            await MainActor.run {
                groups = found
                if found.isEmpty {
                    job.finish([], "No duplicates found.")
                } else {
                    job.finish([], "Found \(found.count) group\(found.count == 1 ? "" : "s").")
                }
            }
        }
    }

    private func trashExtras() {
        let items = extras
        var failed = 0
        for (url, _) in items {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failed += 1
            }
        }
        // Drop removed files and shrink groups that no longer have duplicates.
        var updated: [DuplicateGroup] = []
        for var group in groups {
            group.files.removeAll { url in !FileManager.default.fileExists(atPath: url.path) }
            if group.files.count > 1 {
                if !group.files.contains(group.keeper), let first = group.files.first {
                    group.keeper = first
                }
                updated.append(group)
            }
        }
        groups = updated
        job.finish([], failed == 0 ? "Moved \(items.count) file\(items.count == 1 ? "" : "s") to the Trash." : "Moved \(items.count - failed) files; \(failed) could not be moved.")
        if failed == 0 { NSSound(named: "Trash").map { _ = $0 } }
    }

    private func saveReport() {
        var body = "Nookit duplicate report\n\(Fmt.stamp.string(from: Date()))\n\n"
        for group in groups {
            body += "\(group.files.count) copies · \(Fmt.bytes(group.size))\n"
            for url in group.files {
                body += "  \(url == group.keeper ? "[keep] " : "       ")\(url.path)\n"
            }
            body += "\n"
        }
        do {
            let folder = store.datedFolder(for: "Find Duplicates")
            let target = try store.write(string: body, to: folder, filename: "duplicates-\(Fmt.stampTime.string(from: Date())).txt")
            job.finish([target], "Saved \(target.lastPathComponent).")
        } catch {
            job.fail(error)
        }
    }
}
