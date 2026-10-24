import SwiftUI

/// One panel for everything the app costs: paid/free marks, license key,
/// and subscription. Replaces the separate license and subscription sheets.
/// Dumb view — state arrives as values/bindings, changes leave as callbacks.
///
/// Layout keeps one section visible at a time (Key | Subscription tabs) so
/// the panel stays small; App Store installs get a seal banner above the
/// tabs since their license lives with the Apple ID — but they keep every
/// field, so a store purchase can still be recorded as Lifetime and a
/// mis-detected install is never locked out of its key.
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
    /// Owned by the caller so an unlock survives the popover closing and
    /// reopening around the Touch ID prompt. A saved key is never read until
    /// the panel unlocks it (Reveal or Replace, each after Touch ID). Replace
    /// starts from an empty field and never reads the saved key.
    @Binding var keyUnlocked: Bool
    @Binding var revealed: Bool
    @Binding var draftLicenseEmail: String
    @Binding var draftLicenseType: LicenseType?
    @Binding var draftSubPrice: String
    @Binding var draftSubCurrency: String
    @Binding var draftSubCycle: BillingCycle
    @Binding var draftSubRenewal: Date?
    @Binding var draftSubEmail: String

    let onToggleFree: () -> Void
    /// `keyEditable` is false while a saved key is still locked: Save then
    /// leaves the key alone and stores only the email and type. Returns false
    /// when the Keychain refused the key: the panel then stays open with the
    /// typed key and says it was not saved.
    let onSaveLicense: (_ keyEditable: Bool) -> Bool
    /// Asks for Touch ID, then reads the saved key into `draftLicenseKey`
    /// and sets `keyUnlocked` and `revealed`. The system prompt takes focus
    /// and closes this popover, so the owner reopens it, already unlocked.
    let onRevealKey: () -> Void
    /// Asks for Touch ID, then opens an empty field so a new key can replace
    /// the saved one. The saved key is not read. The system prompt closes this
    /// popover; the owner reopens it, already unlocked, only after success.
    let onReplaceKey: () -> Void
    let onCopyKey: () -> Void
    let onRemoveKey: () -> Void
    let onSaveSubscription: () -> Void
    let onRemoveSubscription: () -> Void

    private enum Tab: String, CaseIterable {
        case key = "Key"
        case subscription = "Subscription"
    }

    @Environment(\.dismiss) private var dismiss

    private var keyEditable: Bool { !hasKey || keyUnlocked }
    @State private var tab: Tab = .key
    @State private var keySaveFailed = false

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

    /// Save stays live whenever the panel holds something worth writing.
    /// A key is not the only thing worth saving: correcting the license type
    /// — or recording "Lifetime" for a keyless App Store purchase — is a
    /// save on its own, and clearing the type back to Not set is too.
    private var licenseSaveDisabled: Bool {
        !LicenseDraftRules.hasSomethingToSave(
            key: keyEditable ? draftLicenseKey : "",
            email: draftLicenseEmail,
            type: draftLicenseType,
            hasKey: hasKey,
            currentType: currentLicenseType
        )
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
            }

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
        .padding(16)
        .frame(width: 320)
        .onAppear {
            if startOnSubscription || (hasSubscription && !hasKey) { tab = .subscription }
        }
    }

    // MARK: - Header

    /// Only the Free mark earns a pill — it drives real behavior (green
    /// gift, gated money fields). Paid is implied by a key or subscription;
    /// for the rare keyless purchase it lives in the cube's right-click.
    /// The pill hides once a key, a license type, or a subscription proves
    /// the app costs money.
    private var showsFreeMark: Bool {
        !hasKey && !hasSubscription && currentLicenseType == nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("License — \(appName)")
                .font(.headline)
            HStack(spacing: 6) {
                if showsFreeMark {
                    markPill("Free", active: isFree, tint: .green, action: onToggleFree)
                }
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
            if keyEditable {
                keyField
            } else {
                lockedKeyRow
            }

            if keySaveFailed {
                Label("Key not saved: the macOS Keychain refused it. Try Save again.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
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
                    Button(role: .destructive) {
                        onRemoveKey()
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove key (Touch ID)")
                }
                Spacer()
                Button("Save") {
                    if onSaveLicense(keyEditable) {
                        dismiss()
                    } else {
                        keySaveFailed = true
                    }
                }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(licenseSaveDisabled)
            }
        }
        .disabled(licenseDisabled)
        .opacity(licenseDisabled ? 0.5 : 1)
    }

    /// A saved key, still locked: nothing has been read from the Keychain.
    private var lockedKeyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Key saved", systemImage: "lock.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Button("Reveal") { onRevealKey() }
                .help("Show the key (Touch ID)")
                Button("Copy") { onCopyKey() }
                    .help("Copy the key (Touch ID)")
                Button("Replace") { onReplaceKey() }
                .help("Type a new key in place of the saved one (Touch ID)")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    /// The key as text: empty for a new key, or the saved key once revealed.
    private var keyField: some View {
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

            // The field only ever holds what you typed or a key you already
            // unlocked with Touch ID, so showing it needs no second prompt.
            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(revealed ? "Hide license key" : "Show license key")
        }
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if draftSubRenewal == nil {
                Button("Set renewal date") { draftSubRenewal = Date() }
                    .font(.callout)
                    .buttonStyle(.borderless)
            } else {
                DatePicker("Renews", selection: Binding(
                    get: { draftSubRenewal ?? Date() },
                    set: { draftSubRenewal = $0 }
                ), displayedComponents: .date)
                .font(.callout)
                Button("Clear renewal date") { draftSubRenewal = nil }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }

            quietField("Billing email (optional)", text: $draftSubEmail)

            HStack {
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

        if hasSubscription {
            Button(role: .destructive) {
                onRemoveSubscription()
                dismiss()
            } label: {
                Label("Remove subscription", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Remove subscription")
        }
        }
    }
}
