import SwiftUI
import SwiftData

#if canImport(AppKit)
import AppKit
#endif

/// Shows everything you've bought — license keys and paid Mac App Store apps —
/// split into Installed and No longer installed. Records persist after an app is
/// removed; uninstalled apps simply move to the "No longer installed" section and
/// move back when reinstalled.
struct LicenseVaultView: View {
    let installedBundleIDs: Set<String>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppListViewModel.self) private var viewModel
    private let licenseKeyStore = LicenseKeyStore.shared

    /// A recorded license type counts as a purchase on its own — that is the
    /// only trace a keyless App Store buy ever leaves, and losing it here
    /// would defeat the point of installing an app just to vault its license.
    @Query(filter: #Predicate<AppRecord> { $0.hasLicenseKey || $0.isPaidApp || $0.licenseType != nil },
           sort: \AppRecord.appName)
    private var ownedRecords: [AppRecord]

    @State private var copiedBundleID: String? = nil

    private var installedRecords: [AppRecord] {
        ownedRecords.filter { installedBundleIDs.contains($0.bundleID) }
    }

    private var missingRecords: [AppRecord] {
        ownedRecords.filter { !installedBundleIDs.contains($0.bundleID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("License Vault").font(.headline)
                    Text("Everything you've bought in one place")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            if ownedRecords.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Bought Yet", systemImage: "bag")
                } description: {
                    Text("Save a license key, set a license type, or mark a Mac App Store app as paid, and it appears here. Items stay in this vault even after you uninstall the app.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !installedRecords.isEmpty {
                        Section("Installed") {
                            ForEach(installedRecords, id: \.bundleID) { record in
                                vaultRow(record)
                            }
                        }
                    }
                    if !missingRecords.isEmpty {
                        Section("No longer installed") {
                            ForEach(missingRecords, id: \.bundleID) { record in
                                vaultRow(record)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 520, height: 460)
    }

    private func vaultRow(_ record: AppRecord) -> some View {
        HStack(spacing: 10) {
            if let data = record.iconPNG, let icon = NSImage(data: data) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)
            } else if let live = viewModel.apps.first(where: { $0.bundleID == record.bundleID })?.icon {
                // Older records (e.g. App Store apps marked paid before icons
                // were captured) fall back to the installed app's live icon.
                Image(nsImage: live.image)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)
            } else {
                Image(systemName: record.hasLicenseKey ? "key.horizontal.fill" : "bag.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                nameLink(record)
                Text(record.bundleID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let email = record.licenseEmail, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if record.hasLicenseKey {
                if copiedBundleID == record.bundleID {
                    Text("Copied")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    copyKey(for: record.bundleID)
                } label: {
                    Label("Copy Key", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                Button(role: .destructive) {
                    deleteKey(for: record)
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .help("Remove this key from the vault")
            } else {
                let type = record.licenseType.flatMap(LicenseType.init(rawValue:))
                let tint = type.map { MoneyCubeState.licensed($0).tint } ?? .green
                Text(type?.displayName ?? "Mac App Store · Paid")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.14), in: Capsule())
                Button(role: .destructive) {
                    removePurchase(record)
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .help("Remove from your purchases")
            }
        }
        .padding(.vertical, 2)
    }

    /// The name is the way back to the maker's site — the page that sells the
    /// app, holds the receipt, or lets you re-download it. A saved link wins,
    /// then Sift's suggestion, and failing both the name goes to a search
    /// rather than leaving you to look it up by hand.
    private func nameLink(_ record: AppRecord) -> some View {
        let destination = VaultLink.destination(appURL: record.appURL,
                                                suggestedAppURL: record.suggestedAppURL,
                                                appName: record.appName)
        return Button {
            #if canImport(AppKit)
            NSWorkspace.shared.open(destination.url)
            #endif
        } label: {
            HStack(spacing: 4) {
                Text(record.appName).font(.body)
                Image(systemName: destination.isSearch ? "magnifyingglass" : "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .help(VaultLink.help(for: destination, appName: record.appName))
        #if canImport(AppKit)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        #endif
    }

    private func copyKey(for bundleID: String) {
        Task { @MainActor in
            guard await LicenseKeyGuard.authenticate(reason: "copy a license key from the vault") else { return }
            let resolution = licenseKeyStore.resolveKey(bundleID: bundleID, legacyValue: nil)
            guard let key = resolution.value, !key.isEmpty else { return }
            #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(key, forType: .string)
            #endif
            await MainActor.run { copiedBundleID = bundleID }
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                if copiedBundleID == bundleID { copiedBundleID = nil }
            }
        }
    }

    private func deleteKey(for record: AppRecord) {
        licenseKeyStore.delete(bundleID: record.bundleID)
        record.hasLicenseKey = false
        record.licenseKey = nil
        try? modelContext.save()
    }

    /// Clears both traces of a keyless purchase — the Paid mark and the
    /// license type — so one trash click actually removes the row.
    private func removePurchase(_ record: AppRecord) {
        record.isPaidApp = false
        viewModel.setPaidApp(bundleID: record.bundleID, value: false)
        record.licenseType = nil
        viewModel.setLicenseType(bundleID: record.bundleID, rawValue: nil)
        try? modelContext.save()
    }
}
