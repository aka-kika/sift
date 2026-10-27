import SwiftUI

// Centralized Liquid Glass adoption. All glass styling goes through these
// helpers so views carry no raw #available checks and macOS 14–15 keeps the
// exact pre-glass appearance. If a beta glass API misbehaves, change the
// fallback here rather than fighting it at call sites.
extension View {

    /// `.glassProminent` button style on macOS 26+, `.borderedProminent` earlier.
    @ViewBuilder
    func glassProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// `.glass` button style on macOS 26+, `.bordered` earlier.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// No toolbar band or hairline under the window's top bar, so the sidebar
    /// and the detail header read as one straight edge (Kika, 28 Oct).
    @ViewBuilder
    func plainWindowToolbar() -> some View {
        if #available(macOS 15.0, *) {
            self.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self.toolbarBackground(.hidden, for: .windowToolbar)
        }
    }

    /// Soft scroll-edge fade under translucent bars on macOS 26+, no-op earlier.
    @ViewBuilder
    func softTopScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

/// One color per license story, shared by the detail cube and the sidebar
/// badge so the same state always wears the same color everywhere.
extension MoneyCubeState {
    var tint: Color {
        switch self {
        case .subscription(let near): return near ? .orange : .teal
        case .appStore: return .blue
        case .licensed(let type):
            switch type {
            case .lifetime: return .indigo
            case .oneTime: return .purple
            case .annual: return .cyan
            case .other, nil: return .indigo
            }
        case .free: return .green
        case .none: return .secondary
        }
    }
}
