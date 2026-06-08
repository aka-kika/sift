import SwiftUI
import SwiftData

#if canImport(AppKit)
import AppKit
#endif

/// Shows license keys for apps that are no longer installed, so the user can still
/// copy a purchased key after uninstalling the app. Records persist after an app is
/// removed; this view surfaces the ones that still hold a key.
struct LicenseVaultView: View {
    let installedBundleIDs: Set<String>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    private let licenseKeyStore = LicenseKeyStore.shared

    @Query(filter: #Predicate<AppRecord> { $0.hasLicenseKey }, sort: \AppRecord.appName)
    private var keyedRecords: [AppRecord]

    @State private var copiedBundleID: String? = nil

    private var vaultRecords: [AppRecord] {
        keyedRecords.filter { !installedBundleIDs.contains($0.bundleID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("License Vault").font(.headline)
                    Text("Keys for apps no longer installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            if vaultRecords.isEmpty {
                ContentUnavailableView {
                    Label("Vault Empty", systemImage: "key.horizontal")
                } description: {
                    Text("When you uninstall an app that has a saved license key, it stays here so you can still copy the key later.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vaultRecords, id: \.bundleID) { record in
                        vaultRow(record)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 520, height: 420)
    }

    private func vaultRow(_ record: AppRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "key.horizontal.fill")
                .foregroundStyle(.secondary)
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
        let resolution = licenseKeyStore.resolveKey(bundleID: bundleID, legacyValue: nil)
        guard let key = resolution.value, !key.isEmpty else { return }
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        #endif
        copiedBundleID = bundleID
        Task {
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
