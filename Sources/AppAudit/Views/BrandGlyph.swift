import SwiftUI
import AppKit

/// SF Symbols carries no brand logos, so the one brand Sift points at by name
/// is drawn from its path. A template image, so it tints like any symbol and
/// works where a SwiftUI shape would not (menus, labels).
///
/// Path data: Simple Icons (https://simpleicons.org, CC0). The mark itself is
/// GitHub's; it is used here only on links that open GitHub, which is what
/// GitHub's logo policy allows.
enum BrandGlyph {
    static let github: NSImage = templateImage(
        viewBox: 24,
        path: "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"
    )

    /// True for a link that opens a GitHub repo or page.
    static func isGitHub(_ urlString: String?) -> Bool {
        guard let urlString, let host = URL(string: urlString)?.host()?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com")
    }

    private static func templateImage(viewBox: CGFloat, path: String) -> NSImage {
        let cgPath = SVGPath.parse(path)
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: rect.width / viewBox, y: rect.height / viewBox)
            context.addPath(cgPath)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The icon for an update source: GitHub's own mark, an SF Symbol for the rest.
struct UpdateSourceIcon: View {
    let source: AppInfo.UpdateSource

    var body: some View {
        if source == .github {
            GitHubGlyph()
        } else {
            Image(systemName: source.actionSymbol)
        }
    }
}

/// The GitHub mark sized to sit beside text the way an SF Symbol does.
struct GitHubGlyph: View {
    @ScaledMetric(relativeTo: .caption) private var side: CGFloat = 13

    var body: some View {
        Image(nsImage: BrandGlyph.github)
            .resizable()
            .renderingMode(.template)
            .frame(width: side, height: side)
    }
}

/// The small slice of SVG path syntax the glyphs above use: move, line, cubic
/// curve and close, absolute or relative, with numbers run together the way
/// optimised SVG writes them (`.6.113.82-.258`).
enum SVGPath {
    static func parse(_ data: String) -> CGPath {
        let path = CGMutablePath()
        let scanner = Scanner(string: data)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n\t")

        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero

        func number() -> CGFloat? {
            // Scanner.scanDouble reads "-.258" and stops at the next sign or
            // second decimal point, which is exactly the run-together rule.
            scanner.scanDouble().map { CGFloat($0) }
        }
        func point(relative: Bool) -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while !scanner.isAtEnd {
            if let letter = scanner.scanCharacter(), letter.isLetter {
                command = letter
            } else if scanner.currentIndex > data.startIndex {
                // Not a letter: the previous command repeats with new numbers.
                scanner.currentIndex = data.index(before: scanner.currentIndex)
            }

            let relative = command.isLowercase
            switch command.lowercased() {
            case "m":
                guard let p = point(relative: relative) else { return path }
                path.move(to: p)
                current = p
                start = p
                command = relative ? "l" : "L"
            case "l":
                guard let p = point(relative: relative) else { return path }
                path.addLine(to: p)
                current = p
            case "c":
                guard let c1 = point(relative: relative),
                      let c2 = point(relative: relative),
                      let end = point(relative: relative) else { return path }
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
            case "z":
                path.closeSubpath()
                current = start
            default:
                return path
            }
        }
        return path
    }
}
