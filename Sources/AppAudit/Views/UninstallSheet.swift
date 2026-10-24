import SwiftUI
import AppKit

/// The uninstall sweep panel: the app bundle plus every discovered leftover,
/// each pre-checked with a reason and size. A sweep moves files to the Trash.
/// `brew uninstall` removes the app for good; that copy is not in the Trash.
/// The AppRecord (license keys, notes, marks) is
/// never touched; the vault keeps gone apps under "No longer installed".
struct UninstallSheet: View {
    let app: AppInfo
    /// Called on close; `removedBundle` is true when the .app left the disk.
    /// Every other installed app, so a sibling's files (Chrome Canary next to
    /// Chrome) are never listed as this app's leftovers.
    var otherBundleIDs: [String] = []
    /// The names of those other apps. A folder matched only by name that one
    /// of them could own (1Password next to 1Password 7) starts unchecked.
    var otherAppNames: [String] = []
    /// Other copies with this bundle ID in the folders Sift scans (a test
    /// build next to the release). The sheet adds what Spotlight finds
    /// anywhere else on the Mac before it decides what to check.
    var knownOtherCopies: [String] = []
    let onFinished: (_ removedBundle: Bool) -> Void

    private enum Phase {
        case scanning
        case list
        case working(current: String)
        case done(failures: [TrashService.Failure], removedBundle: Bool, stoppedAtBundle: Bool)
    }

    @State private var phase: Phase = .scanning
    @State private var items: [LeftoverItem] = []
    @State private var checked: Set<String> = []
    @State private var isRunning = false
    @State private var quitting = false
    @State private var brewOutput: String? = nil
    @State private var brewFailure: String? = nil
    @State private var brewRunning = false
    /// The cask brew may uninstall, set only when brew's install record puts
    /// this exact bundle on disk. A name match alone could be another copy.
    @State private var brewToken: String? = nil
    /// Every other copy of this app, scanned folders and Spotlight together.
    @State private var copies: AppCopyFinder.Result = .unknown

    /// Another copy shares this bundle ID, or Sift could not rule one out.
    /// Its settings, caches, and containers are the same folders, so they
    /// start unchecked and only this copy is quit.
    private var hasOtherCopy: Bool { copies != .onlyThisCopy }

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
                if hasOtherCopy { otherCopyNote }
                if brewToken != nil { brewNote }
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
            case .done(let failures, let removedBundle, let stoppedAtBundle):
                doneView(failures: failures, removedBundle: removedBundle, stoppedAtBundle: stoppedAtBundle)
            }
        }
        .padding(16)
        .frame(width: 560)
        .task {
            await scan()
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            if let icon = app.icon {
                Image(nsImage: icon.image)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(8)
            }
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
            Button(quitting ? "Quitting…" : "Quit & Continue") {
                quitApp()
            }
            .controlSize(.small)
            .disabled(quitting)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var otherCopyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.on.square")
                .foregroundStyle(.secondary)
            Text(otherCopyText)
                .font(.caption)
                .foregroundStyle(.secondary)
                // Wrap in full: the path and the "check it yourself" part
                // are the point of the note.
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var otherCopyText: String {
        switch copies {
        case .others(let paths):
            let place = paths.first.map { " at \(abbreviate($0))" } ?? ""
            let more = paths.count > 1 ? " (and \(paths.count - 1) more)" : ""
            return "Another copy of \(app.name) is\(place)\(more) and uses the same settings and data, so only this copy's app is checked."
        case .unknown:
            return "Spotlight could not confirm this is the only copy of \(app.name), so only the app is checked. Check the rest too if no other copy is on this Mac."
        case .onlyThisCopy:
            return ""
        }
    }

    private var brewNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text(brewOutput != nil
                 ? "Homebrew finished; leftovers below can still be swept"
                 : brewFailure.map { "brew could not remove it — \($0) The app bundle stays in the list below." }
                   ?? "Installed with Homebrew — you can let brew remove the app instead")
                .font(.caption)
                .foregroundStyle(brewFailure == nil ? .secondary : .primary)
                .lineLimit(3)
            Spacer()
            if brewOutput == nil {
                Button("brew uninstall") {
                    runBrewUninstall()
                }
                .controlSize(.small)
                .disabled(!BrewUninstallFooter.brewButtonEnabled(running: brewRunning))
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
                        Text(AppFacts.sizeText(item.sizeBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        // A sheet sizes a ScrollView to almost nothing; without a floor the
        // notes above push the list (and its checkboxes) out of sight.
        .frame(minHeight: 160, maxHeight: 440)
    }

    private var footer: some View {
        HStack {
            if BrewUninstallFooter.action(homebrewRemovedTheApp: brewOutput != nil, anythingChecked: !checked.isEmpty) == .doneRemoved {
                Spacer()
                Button("Done") { onFinished(true) }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") { onFinished(false) }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Move to Trash", role: .destructive) {
                    // The app may have been opened again since the list loaded.
                    refreshRunningState()
                    guard !isRunning else { return }
                    guard confirmDataOnlySweepIfNeeded() else { return }
                    Task { await execute() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(checked.isEmpty || isRunning || brewRunning)
            }
        }
    }

    private func doneView(failures: [TrashService.Failure], removedBundle: Bool, stoppedAtBundle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if stoppedAtBundle {
                Label("\(app.name) could not be moved to the Trash, so its settings and data were left alone. Nothing was moved.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if failures.isEmpty {
                Label(UninstallDoneCopy.success(homebrewRemovedTheApp: brewOutput != nil),
                      systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                Label("\(failures.count) item\(failures.count == 1 ? "" : "s") could not be moved:",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                ForEach(failures, id: \.path) { failure in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(abbreviate(failure.path))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(failure.reason)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: failure.path)])
                        }
                        .controlSize(.small)
                    }
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
        let found = await scanner.scan(appName: app.name, bundleID: app.bundleID, appPath: app.path,
                                       otherBundleIDs: otherBundleIDs, otherAppNames: otherAppNames)
        // Spotlight sees copies outside the scanned folders (~/Downloads,
        // Toolbox, Setapp). No answer counts as "maybe": data starts unchecked.
        let spotlight = await AppCopyFinder.spotlightPaths(bundleID: app.bundleID)
        copies = AppCopyFinder.classify(found: spotlight, thisPath: app.path, knownOtherPaths: knownOtherCopies)
        if let token = app.homebrewCaskToken {
            let path = app.path
            let owns = await Task.detached {
                HomebrewService.caskOwnsBundle(token: token, bundlePath: path)
            }.value
            brewToken = owns ? token : nil
        }
        items = found
        checked = UninstallSweep.initiallyChecked(found, hasOtherCopy: hasOtherCopy)
        refreshRunningState()
        phase = .list
    }

    private func refreshRunningState() {
        isRunning = !runningInstances.isEmpty
    }

    /// The running processes of this app. With a second copy installed, only
    /// the one launched from this path: quitting must not close the other.
    private var runningInstances: [NSRunningApplication] {
        let all = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        guard hasOtherCopy else { return all }
        let path = URL(fileURLWithPath: app.path).standardizedFileURL.path
        return all.filter { $0.bundleURL?.standardizedFileURL.path == path }
    }

    private func quitApp() {
        for running in runningInstances {
            running.terminate()
        }
        quitting = true
        Task { @MainActor in
            _ = await QuitWait.untilQuit { !runningInstances.isEmpty }
            quitting = false
            refreshRunningState()
        }
    }

    private func runBrewUninstall() {
        guard let token = brewToken, !brewRunning else { return }
        brewRunning = true
        brewFailure = nil
        Task {
            let outcome = await RunningWork.shared.run(.homebrew) {
                await Task.detached {
                    HomebrewService().uninstall(cask: token)
                }.value
            }
            brewRunning = false
            guard outcome.succeeded else {
                brewFailure = outcome.message
                return
            }
            brewOutput = outcome.output
            // brew removed the bundle; drop it from the sweep list.
            items.removeAll(where: \.isAppBundle)
            checked = checked.intersection(Set(items.map(\.id)))
        }
    }

    /// Unticking the app row keeps the app, so a sweep of its data alone is
    /// asked about first. Cancel is the default button, Return included.
    private func confirmDataOnlySweepIfNeeded() -> Bool {
        guard UninstallSweep.needsDataOnlyConfirmation(items: items, checked: checked) else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = UninstallSweep.DataOnlyConfirmation.title
        alert.informativeText = UninstallSweep.DataOnlyConfirmation.message(appName: app.name)
        // NSAlert gives a button titled Cancel the Escape key, not Return, so
        // Return is set by hand to keep Cancel the default, and Escape is
        // caught while the alert runs so it still cancels too.
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\r"
        let confirm = alert.addButton(withTitle: UninstallSweep.DataOnlyConfirmation.confirm)
        confirm.hasDestructiveAction = true
        confirm.keyEquivalent = ""
        let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            NSApp.stopModal(withCode: .alertFirstButtonReturn)
            return nil
        }
        let answer = alert.runModal()
        escape.map(NSEvent.removeMonitor)
        // stopModal leaves the alert on screen; a button click does not.
        alert.window.orderOut(nil)
        return answer == .alertSecondButtonReturn
    }

    @MainActor
    private func execute() async {
        // Checked again after the question: the app may have been opened meanwhile.
        refreshRunningState()
        guard !isRunning else { return }
        let targets = items.filter { checked.contains($0.id) }
        // Quitting mid-sweep would leave half the items behind.
        RunningWork.shared.begin(.trashSweep)
        defer { RunningWork.shared.end(.trashSweep) }
        // The bundle goes first, and a bundle that stays put stops the sweep:
        // the app still runs, so its data must stay with it.
        let outcome = await UninstallSweep.run(
            targets,
            progress: { phase = .working(current: $0.url.lastPathComponent) },
            beforeTrash: { await LaunchAgentUnload.bootout(plistPath: $0.url.path) },
            trash: { await TrashService.trash($0.url, isAppBundle: $0.isAppBundle) }
        )
        phase = .done(failures: outcome.failures,
                      removedBundle: outcome.removedBundle || brewOutput != nil,
                      stoppedAtBundle: outcome.stoppedAtBundle)
    }

    // MARK: - Formatting

    private var totalText: String {
        AppFacts.sizeText(items.filter { checked.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes })
    }

    private func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
