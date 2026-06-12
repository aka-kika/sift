import SwiftUI
import SwiftData

#if canImport(AppKit)
import AppKit
#endif

/// Shows all license keys in one place, split into Installed and No longer installed.
/// Records persist after an app is removed; uninstalled apps simply move to the
/// "No longer installed" section and move back when reinstalled.
struct LicenseVaultView: View {
    let installedBundleIDs: Set<String>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    private let licenseKeyStore = LicenseKeyStore.shared

    @Query(filter: #Predicate<AppRecord> { $0.hasLicenseKey }, sort: \AppRecord.appName)
    private var keyedRecords: [AppRecord]

    @State private var copiedBundleID: String? = nil

    private var installedRecords: [AppRecord] {
        keyedRecords.filter { installedBundleIDs.contains($0.bundleID) }
    }

    private var missingRecords: [AppRecord] {
        keyedRecords.filter { !installedBundleIDs.contains($0.bundleID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("License Vault").font(.headline)
                    Text("All your license keys in one place")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            if keyedRecords.isEmpty {
                ContentUnavailableView {
                    Label("No License Keys Yet", systemImage: "key.horizontal")
                } description: {
                    Text("Save a license key to any app — from its detail panel or right-click menu — and it appears here. Keys for apps you later uninstall stay safe in this vault.")
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
            } else {
                Image(systemName: "key.horizontal.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.appName).font(.body)
                Text(record.bundleID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
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
        }
        .padding(.vertical, 2)
    }

    private func copyKey(for bundleID: String) {
        Task {
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
}
