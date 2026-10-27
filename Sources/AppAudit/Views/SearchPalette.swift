import SwiftUI

/// Which apps the palette lists for a query: names that start with it first,
/// then names that contain it, each alphabetically.
enum PaletteSearch {
    static let limit = 8

    static func matches(in apps: [AppInfo], query: String, limit: Int = limit) -> [AppInfo] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let hits = apps.filter { $0.name.localizedCaseInsensitiveContains(needle) }
        let byName: (AppInfo, AppInfo) -> Bool = {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let starts = hits.filter { $0.name.lowercased().hasPrefix(needle.lowercased()) }.sorted(by: byName)
        let rest = hits.filter { !$0.name.lowercased().hasPrefix(needle.lowercased()) }.sorted(by: byName)
        return Array((starts + rest).prefix(limit))
    }
}

/// A small search-only palette near the top of the window (Kika's pick 3A,
/// 28 Oct). Solid background so it stays readable over the list; Return
/// opens the highlighted app, Escape or a click outside closes it.
struct SearchPalette: View {
    @Environment(AppListViewModel.self) private var viewModel
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private var results: [AppInfo] {
        PaletteSearch.matches(in: viewModel.apps, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .onSubmit(openHighlighted)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !results.isEmpty {
                Divider().opacity(0.5)
                VStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, app in
                        row(app, isHighlighted: index == highlighted)
                            .onTapGesture { viewModel.openFromSearch(appID: app.id) }
                            .onHover { if $0 { highlighted = index } }
                    }
                }
                .padding(6)
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Divider().opacity(0.5)
                Text("No app matches")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, _ in highlighted = 0 }
    }

    private func row(_ app: AppInfo, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            if let icon = app.icon?.image {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
            }
            Text(app.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(app.version)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHighlighted ? Color.accentColor.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }

    private func move(_ step: Int) {
        guard !results.isEmpty else { return }
        highlighted = (highlighted + step + results.count) % results.count
    }

    private func openHighlighted() {
        guard results.indices.contains(highlighted) else { return }
        viewModel.openFromSearch(appID: results[highlighted].id)
    }

    private func close() {
        viewModel.showingSearchPalette = false
    }
}
