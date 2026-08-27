import SwiftUI

/// The 1–5 relevance scale's words and colours — one source for the sidebar
/// badge, the detail page, and anything else that paints a score.
enum ScoreScale {
    static func label(_ score: Int) -> String {
        switch score {
        case 1: return "Not needed"
        case 2: return "Unlikely needed"
        case 3: return "Possibly useful"
        case 4: return "Likely useful"
        case 5: return "Essential"
        default: return "Unknown"
        }
    }

    static func color(_ score: Int) -> Color {
        switch score {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .mint
        case 5: return .green
        default: return .gray
        }
    }
}
