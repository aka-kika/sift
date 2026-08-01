import SwiftUI

/// One panel for everything the app costs: paid/free marks, license key,
/// and subscription. Replaces the separate license and subscription sheets.
/// Dumb view — state arrives as values/bindings, changes leave as callbacks.
///
/// Layout keeps one section visible at a time (Key | Subscription tabs) so
/// the panel stays small; App Store installs swap the Key tab for a seal
/// banner since their license lives with the Apple ID.
struct MoneyPopover: View {
    let appName: String
    let isAppStoreInstall: Bool
    let isMyApp: Bool
    let isPaid: Bool
    let isFree: Bool
    let hasKey: Bool
    let hasSubscription: Bool
    let currentLicenseType: LicenseType?
    /// Opens the panel on the Subscription tab (e.g. from "Edit Subscription…").
    var startOnSubscription: Bool = false

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

    private enum Tab: String, CaseIterable {
        case key = "Key"
        case subscription = "Subscription"
    }

    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false
    @State private var tab: Tab = .key

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
        VStack(alignment: .leading, spacing: 12) {
            header

            if isAppStoreInstall {
                appStoreBanner
                subscriptionSection
            } else {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch tab {
                case .key: licenseSection
                case .subscription: subscriptionSection
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            if startOnSubscription || (hasSubscription && !hasKey) { tab = .subscription }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("License — \(appName)")
                .font(.headline)
            HStack(spacing: 6) {
                markPill("Paid", active: isPaid, tint: .indigo, action: onTogglePaid)
                markPill("Free", active: isFree, tint: .green, action: onToggleFree)
                Spacer()
                if let reason = UtilityCardRules.disabledReason(isMyApp: isMyApp, isFreeApp: isFree,
                                                                licenseType: currentLicenseType) {
                    Text(reason).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func markPill(_ title: String, active: Bool, tint: Color,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(active ? tint.opacity(0.16) : Color.secondary.opacity(0.07),
                            in: Capsule())
                .foregroundStyle(active ? tint : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var appStoreBanner: some View {
        Label(isPaid ? "Mac App Store — paid, tied to your Apple ID"
                     : "Mac App Store — tied to your Apple ID",
              systemImage: "checkmark.seal.fill")
            .font(.caption)
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Fields

    private func quietField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - License key

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Group {
                    if revealed {
                        TextField("License key", text: $draftLicenseKey)
                    } else {
                        SecureField("License key", text: $draftLicenseKey)
                    }
                }
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

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

            quietField("Registered email (optional)", text: $draftLicenseEmail)

            Picker("Type", selection: $draftLicenseType) {
                Text("Not set").tag(LicenseType?.none)
                ForEach(LicenseType.allCases) { type in
                    Text(type.displayName).tag(LicenseType?.some(type))
                }
            }
            .pickerStyle(.menu)

            HStack {
                if hasKey {
                    Button {
                        onCopyKey()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Copy key (Touch ID)")
                    Button(role: .destructive) {
                        onRemoveKey()
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove key")
                }
                Spacer()
                Button("Save") {
                    onSaveLicense()
                    dismiss()
                }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasKey)
            }
        }
        .disabled(licenseDisabled)
        .opacity(licenseDisabled ? 0.5 : 1)
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                quietField("Amount", text: $draftSubPrice)
                    .frame(maxWidth: 110)
                Picker("", selection: $draftSubCurrency) {
                    ForEach(Self.currencyOptions(including: draftSubCurrency), id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 90)
                Spacer()
            }

            Picker("", selection: $draftSubCycle) {
                ForEach(BillingCycle.allCases) { c in
                    Text(c.label).tag(c)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            DatePicker("Renews", selection: $draftSubRenewal, displayedComponents: .date)
                .font(.callout)

            quietField("Billing email (optional)", text: $draftSubEmail)

            HStack {
                if hasSubscription {
                    Button(role: .destructive) {
                        onRemoveSubscription()
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove subscription")
                }
                Spacer()
                Button(hasSubscription ? "Save" : "Mark Subscribed") {
                    onSaveSubscription()
                    dismiss()
                }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draftSubPrice.isEmpty && parsedAmount == nil)
            }
        }
        .disabled(subscriptionDisabled)
        .opacity(subscriptionDisabled ? 0.5 : 1)
    }
}
