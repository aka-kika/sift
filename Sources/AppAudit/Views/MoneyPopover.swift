import SwiftUI

/// One panel for everything money: paid/free marks, license key, and
/// subscription. Replaces the separate license and subscription sheets.
/// Dumb view — state arrives as values/bindings, changes leave as callbacks.
struct MoneyPopover: View {
    let appName: String
    let isAppStoreInstall: Bool
    let isMyApp: Bool
    let isPaid: Bool
    let isFree: Bool
    let hasKey: Bool
    let hasSubscription: Bool
    let currentLicenseType: LicenseType?

    @Binding var draftLicenseKey: String
    @Binding var draftLicenseEmail: String
    @Binding var draftLicenseType: LicenseType?
    @Binding var draftSubPrice: String
    @Binding var draftSubCurrency: String
    @Binding var draftSubCycle: BillingCycle
    @Binding var draftSubRenewal: Date
    @Binding var draftSubEmail: String

    let onTogglePaid: () -> Void
    let onToggleFree: () -> Void
    let onSaveLicense: () -> Void
    let onCopyKey: () -> Void
    let onRemoveKey: () -> Void
    let onSaveSubscription: () -> Void
    let onRemoveSubscription: () -> Void

    @State private var revealed = false

    private static let currencies = ["USD", "EUR", "GBP", "ILS", "CAD", "AUD", "JPY", "CHF"]

    /// Always include the record's current currency even if it is not in the
    /// short list, so the picker can display it without losing the value.
    static func currencyOptions(including current: String) -> [String] {
        if current.isEmpty || currencies.contains(current) { return currencies }
        return [current] + currencies
    }

    private var parsedAmount: Double? {
        Double(draftSubPrice.replacingOccurrences(of: ",", with: "."))
    }

    private var licenseDisabled: Bool {
        UtilityCardRules.licenseDisabled(isMyApp: isMyApp, isFreeApp: isFree)
    }

    private var subscriptionDisabled: Bool {
        UtilityCardRules.subscriptionDisabled(isMyApp: isMyApp, isFreeApp: isFree,
                                              licenseType: currentLicenseType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Money — \(appName)")
                .font(.headline)

            marksSection
            Divider()
            if isAppStoreInstall {
                Label(isPaid ? "Mac App Store — paid, tied to your Apple ID"
                             : "Mac App Store — tied to your Apple ID",
                      systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                licenseSection
            }
            Divider()
            subscriptionSection
        }
        .padding(16)
        .frame(width: 360)
    }

    private var marksSection: some View {
        HStack(spacing: 8) {
            Toggle("Paid", isOn: Binding(get: { isPaid }, set: { _ in onTogglePaid() }))
            Toggle("Free", isOn: Binding(get: { isFree }, set: { _ in onToggleFree() }))
            Spacer()
            if let reason = UtilityCardRules.disabledReason(isMyApp: isMyApp, isFreeApp: isFree,
                                                            licenseType: currentLicenseType) {
                Text(reason).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .toggleStyle(.button)
        .controlSize(.small)
    }

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("License key").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Group {
                    if revealed {
                        TextField("Enter license key", text: $draftLicenseKey)
                    } else {
                        SecureField("Enter license key", text: $draftLicenseKey)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button {
                    if revealed {
                        revealed = false
                    } else {
                        Task { @MainActor in
                            if await LicenseKeyGuard.authenticate(reason: "reveal the license key for \(appName)") {
                                revealed = true
                            }
                        }
                    }
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(revealed ? "Hide license key" : "Reveal license key (Touch ID)")
            }

            TextField("Registered email (optional)", text: $draftLicenseEmail)
                .textFieldStyle(.roundedBorder)

            Picker("License type", selection: $draftLicenseType) {
                Text("Not set").tag(LicenseType?.none)
                ForEach(LicenseType.allCases) { type in
                    Text(type.displayName).tag(LicenseType?.some(type))
                }
            }
            .pickerStyle(.menu)

            HStack {
                if hasKey {
                    Button("Copy (Touch ID)") { onCopyKey() }
                        .controlSize(.small)
                    Button("Remove", role: .destructive) { onRemoveKey() }
                        .controlSize(.small)
                }
                Spacer()
                Button("Save Key") { onSaveLicense() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasKey)
            }
        }
        .disabled(licenseDisabled)
        .opacity(licenseDisabled ? 0.5 : 1)
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subscription").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                TextField("Amount", text: $draftSubPrice)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                Picker("", selection: $draftSubCurrency) {
                    ForEach(Self.currencyOptions(including: draftSubCurrency), id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 100)
            }
            Picker("Billing", selection: $draftSubCycle) {
                ForEach(BillingCycle.allCases) { c in
                    Text(c.label).tag(c)
                }
            }
            .pickerStyle(.segmented)
            DatePicker("Next renewal", selection: $draftSubRenewal, displayedComponents: .date)
            TextField("Billing email (optional)", text: $draftSubEmail)
                .textFieldStyle(.roundedBorder)

            HStack {
                if hasSubscription {
                    Button("Remove", role: .destructive) { onRemoveSubscription() }
                        .controlSize(.small)
                }
                Spacer()
                Button(hasSubscription ? "Save" : "Mark Subscribed") { onSaveSubscription() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draftSubPrice.isEmpty && parsedAmount == nil)
            }
        }
        .disabled(subscriptionDisabled)
        .opacity(subscriptionDisabled ? 0.5 : 1)
    }
}
