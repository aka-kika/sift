import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// The uninstall sweep panel: the app bundle plus every discovered leftover,
/// each pre-checked with a reason and size. Everything goes to the Trash —
/// recoverable by design. The AppRecord (license keys, notes, marks) is
/// never touched; the vault keeps gone apps under "No longer installed".
struct UninstallSheet: View {
    let app: AppInfo
    /// Called on close; `removedBundle` is true when the .app left the disk.
    let onFinished: (_ removedBundle: Bool) -> Void

    private enum Phase {
        case scanning
        case list
        case working(current: String)
        case done(failures: [String], removedBundle: Bool)
    }

    @State private var phase: Phase = .scanning
    @State private var items: [LeftoverItem] = []
    @State private var checked: Set<String> = []
    @State private var isRunning = false
    @State private var brewOutput: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch phase {
            case .scanning:
                HStack {
                    Spacer()
                    ProgressView("Finding everything that belongs to \(app.name)…")
                        .controlSize(.small)
                    Spacer()
                }
                .frame(minHeight: 120)
            case .list:
                if isRunning { runningBanner }
                if app.homebrewCaskToken != nil { brewNote }
                itemList
                footer
            case .working(let current):
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Moving to Trash… \(current)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(minHeight: 80)
            case .done(let failures, let removedBundle):
                doneView(failures: failures, removedBundle: removedBundle)
            }
        }
        .padding(16)
        .frame(width: 460)
        .task {
            await scan()
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            #if canImport(AppKit)
            if let icon = app.icon {
                Image(nsImage: icon.image)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(8)
            }
            #endif
            VStack(alignment: .leading, spacing: 2) {
                Text("Uninstall \(app.name)")
                    .font(.headline)
                if case .list = phase {
                    Text("\(items.count) item\(items.count == 1 ? "" : "s") · \(totalText) reclaimable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var runningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("\(app.name) is running")
                .font(.caption)
            Spacer()
            Button("Quit & Continue") {
                quitApp()
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var brewNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text(brewOutput == nil
                 ? "Installed with Homebrew — you can let brew remove the app instead"
                 : "Homebrew finished; leftovers below can still be swept")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if brewOutput == nil {
                Button("brew uninstall") {
                    runBrewUninstall()
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var itemList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { checked.contains(item.id) },
                            set: { on in
                                if on { checked.insert(item.id) } else { checked.remove(item.id) }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(item.category.rawValue)
                                    .font(.caption.weight(.semibold))
                                Text(abbreviate(item.url.path))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Text(item.reason)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(sizeText(item.sizeBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 300)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { onFinished(false) }
                .keyboardShortcut(.escape)
            Spacer()
            Button("Move to Trash", role: .destructive) {
                Task { await execute() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(checked.isEmpty || isRunning)
        }
    }

    private func doneView(failures: [String], removedBundle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if failures.isEmpty {
                Label("Moved to Trash — recoverable there, and the license record stays in your vault.",
                      systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                Label("\(failures.count) item\(failures.count == 1 ? "" : "s") could not be moved:",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                ForEach(failures, id: \.self) { path in
                    Text(abbreviate(path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            HStack {
                Spacer()
                Button("Done") { onFinished(removedBundle) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Actions

    private func scan() async {
        let scanner = LeftoverScanner()
        let found = await scanner.scan(appName: app.name, bundleID: app.bundleID, appPath: app.path)
        items = found
        checked = Set(found.map(\.id))
        refreshRunningState()
        phase = .list
    }

    private func refreshRunningState() {
        #if canImport(AppKit)
        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
        #endif
    }

    private func quitApp() {
        #if canImport(AppKit)
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
            running.terminate()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            refreshRunningState()
        }
        #endif
    }

    private func runBrewUninstall() {
        guard let token = app.homebrewCaskToken else { return }
        Task {
            let output = await Task.detached {
                HomebrewService().uninstallCask(token)
            }.value
            brewOutput = output
            // brew removed the bundle; drop it from the sweep list.
            items.removeAll(where: \.isAppBundle)
            checked = checked.intersection(Set(items.map(\.id)))
        }
    }

    private func execute() async {
        let targets = items.filter { checked.contains($0.id) }
        var failures: [String] = []
        var removedBundle = brewOutput != nil
        for item in targets {
            phase = .working(current: item.url.lastPathComponent)
            do {
                try await Task.detached {
                    var resulting: NSURL?
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: &resulting)
                }.value
                if item.isAppBundle { removedBundle = true }
            } catch {
                failures.append(item.url.path)
            }
        }
        phase = .done(failures: failures, removedBundle: removedBundle)
    }

    // MARK: - Formatting

    private var totalText: String {
        sizeText(items.filter { checked.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes })
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
