import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// The About tab: what this app is, who made it, and where to find her.
/// Deliberately not a Form — About pages read as a page, not a settings list.
struct AboutSettingsTab: View {
    /// Every link in one place, so adding one is a line rather than a layout.
    private struct Destination: Identifiable {
        let title: String
        let detail: String
        let symbol: String
        let url: URL
        var id: String { url.absoluteString }
    }

    private let destinations: [Destination] = [
        Destination(title: "akakika.com", detail: "Where the work gets written up",
                    symbol: "globe", url: URL(string: "https://akakika.com")!),
        Destination(title: "undrdr.com", detail: "The next one, nearly out",
                    symbol: "arrow.up.forward.app", url: URL(string: "https://undrdr.com")!),
        Destination(title: "@akakikaaa", detail: "X",
                    symbol: "at", url: URL(string: "https://x.com/akakikaaa")!),
        Destination(title: "aka-kika/sift", detail: "GitHub — private for now",
                    symbol: "chevron.left.forwardslash.chevron.right",
                    url: URL(string: "https://github.com/aka-kika/sift")!),
    ]

    var body: some View {
        VStack(spacing: 0) {
            masthead
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(destinations) { destination in
                        DestinationRow(title: destination.title,
                                       detail: destination.detail,
                                       symbol: destination.symbol,
                                       url: destination.url)
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(spacing: 8) {
            #if canImport(AppKit)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
            #endif
            Text("Sift")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(Self.versionLine)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("My organized chaos, wearing a cape.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .padding(.horizontal, 20)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("Made by KIKA")
            Text("·")
            Text("Everything stays on this Mac")
            Spacer()
            if let commit = Self.gitCommit {
                Text(commit)
                    .monospaced()
                    .textSelection(.enabled)
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Bundle facts

    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String, build != short else {
            return "Version \(short)"
        }
        return "Version \(short) (\(build))"
    }

    private static var gitCommit: String? {
        Bundle.main.infoDictionary?["GitCommit"] as? String
    }
}

/// One link: glyph, name, what it is, and an arrow out. The whole row is the
/// target — a link you have to aim at is a link you don't click.
private struct DestinationRow: View {
    let title: String
    let detail: String
    let symbol: String
    let url: URL

    @State private var hovering = false

    var body: some View {
        Button {
            #if canImport(AppKit)
            NSWorkspace.shared.open(url)
            #endif
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.quaternary.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hovering ? .secondary : .tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.45))
                                 : AnyShapeStyle(.quaternary.opacity(0.18)),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url.absoluteString)
    }
}
